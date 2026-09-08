from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class AdaptiveSafetyGateTests(unittest.TestCase):
    def run_json(self, *args: str) -> dict[str, object]:
        result = subprocess.run(
            ["python3", *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_adaptive_fixture_is_explicitly_not_hardware_certification(self) -> None:
        payload = self.run_json(
            "scripts/hardware_test.py",
            "--fixture",
            "tests/fixtures/hardware-adaptive.json",
            "--json",
        )
        scenarios = payload["capabilities"]["adaptive"]
        self.assertEqual(
            set(scenarios),
            {
                "keyboard-attach",
                "keyboard-detach",
                "bluetooth-keyboard",
                "second-keyboard",
                "tablet-switch",
                "dock-undock",
                "external-monitor-keyboard",
                "transition-reversal",
            },
        )
        self.assertTrue(all(row["result"] == "Untested" for row in scenarios.values()))
        self.assertFalse(payload["realHardwareValidated"])

    def test_adaptive_gate_passes_portable_contracts_but_keeps_fixture_unverified(self) -> None:
        payload = self.run_json("scripts/adaptive_check.py", "--json")
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["portableSafety"]["result"], "Pass")
        self.assertFalse(payload["hardware"]["realHardwareValidated"])
        self.assertTrue(all(row["result"] == "Untested" for row in payload["hardware"]["scenarios"].values()))
        self.assertEqual(
            {row["name"] for row in payload["portableSafety"]["checks"]},
            {
                "device-model",
                "transitions",
                "feature-registry",
                "bar-widget-coexistence",
                "hotplug-process-boundary",
                "master-input-release",
                "adaptive-profile-boundary",
                "hotplug-no-config-write",
            },
        )

    def test_adaptive_gate_rejects_a_fixture_with_a_missing_scenario(self) -> None:
        fixture = json.loads((ROOT / "tests/fixtures/hardware-adaptive.json").read_text(encoding="utf-8"))
        del fixture["adaptive"]["scenarios"]["transition-reversal"]
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "incomplete.json"
            path.write_text(json.dumps(fixture), encoding="utf-8")
            result = subprocess.run(
                ["python3", "scripts/adaptive_check.py", "--fixture", str(path), "--json"],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("scenario catalog", result.stdout)


if __name__ == "__main__":
    unittest.main()
