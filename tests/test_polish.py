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
        self.assertEqual(report["version"], "1.3.0")
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

    def test_14_shared_tokens_and_semantic_icons_are_wired(self) -> None:
        tokens = (ROOT / "shell/components/DesignTokens.qml").read_text(encoding="utf-8")
        button = (ROOT / "shell/components/ActionButton.qml").read_text(encoding="utf-8")
        icon = (ROOT / "shell/components/Icon.qml").read_text(encoding="utf-8")
        glyphs = (ROOT / "shell/components/IconGlyphs.js").read_text(encoding="utf-8")
        panel = (ROOT / "shell/Panel.qml").read_text(encoding="utf-8")
        for marker in ("spacingXs", "radiusMd", "targetTouch", "animationFast", "fontSize"):
            self.assertIn(marker, tokens)
        for marker in ("property var tokens", "root.tokens", "focusRing"):
            self.assertIn(marker, button)
        self.assertIn("IconGlyphs.glyph", icon)
        self.assertIn("function glyph", glyphs)
        self.assertIn('icon: "overview"', panel)


if __name__ == "__main__":
    unittest.main()
