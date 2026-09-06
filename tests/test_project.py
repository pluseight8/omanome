from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class OmanomeProjectTests(unittest.TestCase):
    def test_manifest_preserves_the_standard_bar(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertNotIn("bar", manifest["kinds"])
        self.assertEqual(set(manifest["entryPoints"]), {"service", "barWidget", "panel"})
        for entry in manifest["entryPoints"].values():
            self.assertTrue((ROOT / entry).is_file(), entry)

    def test_config_is_versioned_and_has_core_sections(self) -> None:
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertEqual(defaults["schemaVersion"], 1)
        self.assertEqual(schema["properties"]["schemaVersion"]["const"], 1)
        for key in ("tabletMode", "touch", "stylus", "keyboard", "clipboard", "updates"):
            self.assertIn(key, defaults)

    def test_repository_does_not_use_x11_or_second_shell(self) -> None:
        code_suffixes = {".qml", ".js", ".sh", ".py", ".json"}
        text = "\n".join(
            path.read_text(encoding="utf-8", errors="ignore")
            for path in ROOT.rglob("*")
            if path.is_file() and path != ROOT / "tests/test_project.py" and path.suffix in code_suffixes and "work" not in path.parts
        ).lower()
        self.assertNotIn("xdotool", text)
        self.assertNotIn("gnome-shell --replace", text)
        self.assertNotIn('"bar"', (ROOT / "manifest.json").read_text(encoding="utf-8"))

    def test_shell_scripts_parse(self) -> None:
        for script in (ROOT / "cli/omanome", ROOT / "input/clipboard-capture.sh"):
            result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_clipboard_capture_redacts_sensitive_state(self) -> None:
        capture = ROOT / "input/clipboard-capture.sh"
        with tempfile.TemporaryDirectory() as temp:
            env = os.environ.copy()
            env["XDG_STATE_HOME"] = temp
            normal = subprocess.run(
                [str(capture), "text"], input="hello\n", text=True, capture_output=True, env=env
            )
            self.assertEqual(normal.returncode, 0, normal.stderr)
            self.assertEqual(json.loads(normal.stdout)["text"], "hello")

            env["CLIPBOARD_STATE"] = "sensitive"
            sensitive = subprocess.run(
                [str(capture), "text"], input="secret", text=True, capture_output=True, env=env
            )
            self.assertEqual(sensitive.returncode, 0, sensitive.stderr)
            self.assertEqual(sensitive.stdout, "")

    def test_native_omarchy_validator_when_available(self) -> None:
        omarchy = shutil.which("omarchy")
        if not omarchy:
            self.skipTest("omarchy is not installed")
        result = subprocess.run(
            [omarchy, "plugin", "validate", str(ROOT)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
