from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PolishContractTests(unittest.TestCase):
    def run_polish_check(self) -> dict[str, object]:
        result = subprocess.run(
            [sys.executable, "scripts/polish_check.py", "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        report = json.loads(result.stdout)
        self.assertTrue(report["passed"])
        return report

    def test_14_polish_gate_covers_all_contracts(self) -> None:
        report = self.run_polish_check()
        self.assertEqual(
            {item["name"] for item in report["checks"]},
            {
                "source-integrity",
                "executable-modes",
                "config-consistency",
                "i18n-parity",
                "version-consistency",
                "performance-safety",
                "accessibility-critical-controls",
                "privacy-boundary",
                "deterministic-fuzz-lite",
            },
        )

    def test_14_polish_fuzz_report_is_deterministic(self) -> None:
        first = self.run_polish_check()
        second = self.run_polish_check()
        self.assertEqual(first, second)
        self.assertEqual(first["fuzz"]["iterations"], 160)
        self.assertEqual(first["fuzz"]["seed"], 1372173)


if __name__ == "__main__":
    unittest.main()
