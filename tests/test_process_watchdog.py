from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))


def load_watchdog():
    spec = importlib.util.spec_from_file_location("omanome_process_watchdog", ROOT / "scripts/process_watchdog.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load watchdog module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ProcessWatchdogTests(unittest.TestCase):
    def test_pressure_must_be_sustained_before_warning(self) -> None:
        watchdog = load_watchdog()
        report = {
            "measuredAt": "2026-09-07T00:00:00Z",
            "systemCpuPercent": 91.0,
            "ownerCpuPercent": 99.0,
            "processCount": 1,
            "processes": [{"pid": 123, "component": "optional-helper", "cpuPercent": 99.0, "memoryBytes": 1024}],
        }
        state, first = watchdog.evaluate(report, {}, 100.0, cpu_threshold=80.0, duration_seconds=10.0)
        self.assertEqual(first["warnings"], [])
        _, second = watchdog.evaluate(report, state, 110.0, cpu_threshold=80.0, duration_seconds=10.0)
        self.assertEqual(len(second["warnings"]), 1)
        self.assertEqual(second["warnings"][0]["component"], "optional-helper")
        self.assertFalse(second["warnings"][0]["automaticTermination"])
        self.assertEqual(second["warnings"][0]["action"], "notify-only")

    def test_watchdog_source_has_no_process_termination_path(self) -> None:
        source = (ROOT / "scripts/process_watchdog.py").read_text(encoding="utf-8")
        self.assertIn("foreignProcessesExcluded", source)
        self.assertIn("automaticTermination", source)
        self.assertNotIn("os.kill", source)
        self.assertNotIn("subprocess", source)


if __name__ == "__main__":
    unittest.main()
