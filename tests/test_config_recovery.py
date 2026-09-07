from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG_TOOL = ROOT / "scripts" / "config_tool.py"
DEFAULTS = json.loads((ROOT / "config" / "defaults.json").read_text(encoding="utf-8"))


class ConfigRecoveryTests(unittest.TestCase):
    def run_tool(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CONFIG_TOOL), *arguments],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def test_corrupt_config_is_preserved_and_last_known_good_is_restored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.json"
            lkg = pathlib.Path(f"{config}.lkg")
            known_good = json.loads(json.dumps(DEFAULTS))
            known_good["general"]["language"] = "ru"
            lkg.write_text(json.dumps(known_good), encoding="utf-8")
            config.write_text('{"schemaVersion": 2, "general": ', encoding="utf-8")

            result = self.run_tool("recover", str(config), "--json")

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertTrue(payload["recovered"])
            self.assertEqual(payload["source"], str(lkg))
            self.assertTrue(payload["preservedCorrupt"])
            self.assertEqual(json.loads(config.read_text(encoding="utf-8"))["general"]["language"], "ru")
            self.assertEqual(json.loads(lkg.read_text(encoding="utf-8"))["general"]["language"], "ru")
            preserved = pathlib.Path(payload["preservedCorrupt"])
            self.assertTrue(preserved.is_file())
            self.assertEqual(preserved.read_text(encoding="utf-8"), '{"schemaVersion": 2, "general": ')
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(lkg.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(preserved.stat().st_mode), 0o600)

    def test_missing_config_is_created_from_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.json"
            result = self.run_tool("recover", str(config), "--json")

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertTrue(payload["recovered"])
            self.assertEqual(payload["source"], "defaults")
            self.assertEqual(json.loads(config.read_text(encoding="utf-8")), DEFAULTS)
            self.assertEqual(json.loads(pathlib.Path(f"{config}.lkg").read_text(encoding="utf-8")), DEFAULTS)
            self.assertIsNone(payload["preservedCorrupt"])

    def test_future_schema_is_json_error_and_is_not_modified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.json"
            original = '{"schemaVersion": 99, "future": true}\n'
            config.write_text(original, encoding="utf-8")

            result = self.run_tool("recover", str(config), "--json")

            self.assertEqual(result.returncode, 78)
            self.assertEqual(json.loads(result.stdout)["reason"], "future-schema")
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            self.assertEqual(list(pathlib.Path(temporary).glob("config.json.corrupt.*")), [])

    def test_symlink_target_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            outside = root / "outside.json"
            outside.write_text("{}", encoding="utf-8")
            target = root / "config.json"
            target.symlink_to(outside)

            result = self.run_tool("recover", str(target), "--json")

            self.assertEqual(result.returncode, 78)
            self.assertEqual(json.loads(result.stdout)["reason"], "symlink-refused")
            self.assertEqual(outside.read_text(encoding="utf-8"), "{}")


if __name__ == "__main__":
    unittest.main()
