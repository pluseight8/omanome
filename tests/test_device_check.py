from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "device_check.py"
FIXTURE = ROOT / "tests" / "fixtures" / "hardware-device-graph.json"


class DeviceCheckTests(unittest.TestCase):
    def run_check(self, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_device_gate_passes_portable_contracts_without_certifying_fixture(self) -> None:
        payload = self.run_check("--fixture", str(FIXTURE), "--json")
        self.assertTrue(payload["ok"])
        self.assertTrue(all(item["result"] == "Pass" for item in payload["checks"]))
        self.assertEqual(payload["hardware"]["evidence"], "fixture")
        self.assertFalse(payload["hardware"]["realHardwareValidated"])
        self.assertTrue(all(item["result"] == "Untested" for item in payload["hardware"]["scenarios"].values()))

    def test_device_gate_exposes_required_safety_checks(self) -> None:
        payload = self.run_check("--json")
        names = {item["name"] for item in payload["checks"]}
        self.assertTrue({
            "graph-contract",
            "public-privacy-boundary",
            "relationship-confidence",
            "calibration-timeout-rollback",
            "calibration-disconnect-rollback",
            "event-burst-coalescing",
            "mapping-wizard-safety",
        }.issubset(names))


if __name__ == "__main__":
    unittest.main()
