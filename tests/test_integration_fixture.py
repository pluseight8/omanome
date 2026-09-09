from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "scripts" / "integration_fixture.py"


class IntegrationFixtureTests(unittest.TestCase):
    def run_fixture(self, *arguments: str) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
        result = subprocess.run(
            [sys.executable, str(FIXTURE), *arguments, "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        return result, json.loads(result.stdout)

    def test_full_fixture_covers_lifecycle_surfaces_and_releases_preview(self) -> None:
        _, report = self.run_fixture()
        self.assertTrue(report["passed"])
        self.assertTrue(report["fixtureTested"])
        self.assertFalse(report["runtimeProbed"])
        self.assertFalse(report["hardwareTested"])
        self.assertEqual(report["cycles"], 100)
        self.assertEqual(set(report["surfaces"]), {"control-center", "overview", "launcher", "settings", "osk", "quick-settings"})
        self.assertTrue(all(value == 100 for value in report["surfaces"].values()))
        self.assertEqual(report["preview"], {"finalActive": 0, "maxActive": 1})
        self.assertEqual(report["process"]["ownerCount"], 1)
        self.assertEqual(report["process"]["subprocesses"], 0)
        self.assertTrue(all(report["lifecycle"].values()))

    def test_fixture_is_deterministic_for_a_short_reproducible_run(self) -> None:
        _, first = self.run_fixture("--cycles", "7")
        _, second = self.run_fixture("--cycles", "7")
        self.assertEqual(first, second)
        self.assertEqual(first["geometryChecks"], 14)

    def test_fixture_rejects_an_unbounded_cycle_request(self) -> None:
        result = subprocess.run(
            [sys.executable, str(FIXTURE), "--cycles", "501", "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        self.assertFalse(report["passed"])
        self.assertFalse(report["fixtureTested"])
        self.assertIn("between 1 and 500", report["checks"][0]["detail"])


if __name__ == "__main__":
    unittest.main()
