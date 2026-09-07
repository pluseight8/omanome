from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import tarfile
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = ROOT / "cli" / "omanome"


class DiagnosticsTests(unittest.TestCase):
    def test_hardware_fixture_is_explicitly_not_certification(self) -> None:
        result = subprocess.run(
            ["python3", str(ROOT / "scripts/hardware_test.py"), "--fixture", str(ROOT / "tests/fixtures/hardware-tablet.json"), "--json"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["mode"], "fixture")
        self.assertFalse(payload["realHardwareValidated"])
        self.assertTrue(payload["capabilities"]["touchscreen"]["available"])
        self.assertTrue(payload["capabilities"]["stylus"]["available"])

    def test_support_bundle_excludes_personal_config_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(root),
                    "XDG_CONFIG_HOME": str(root / "config"),
                    "XDG_STATE_HOME": str(root / "state"),
                    "XDG_CACHE_HOME": str(root / "cache"),
                }
            )
            config = root / "config" / "omanome"
            config.mkdir(parents=True)
            (config / "config.json").write_text('{"schemaVersion":2,"secret":"do-not-export"}\n', encoding="utf-8")
            output = root / "support.tar.gz"
            result = subprocess.run([str(CLI), "diagnostics", "bundle", str(output)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with tarfile.open(output, "r:gz") as archive:
                report = archive.extractfile("report.json").read().decode("utf-8")
            self.assertNotIn("do-not-export", report)
            self.assertIn('"redacted"', result.stdout)

    def test_safe_mode_has_explicit_status_and_does_not_need_omarchy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            omarchy = fake_bin / "omarchy"
            omarchy.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            omarchy.chmod(omarchy.stat().st_mode | stat.S_IXUSR)
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(root),
                    "XDG_CONFIG_HOME": str(root / "config"),
                    "XDG_STATE_HOME": str(root / "state"),
                    "XDG_CACHE_HOME": str(root / "cache"),
                    "PATH": f"{fake_bin}:{env['PATH']}",
                }
            )
            enabled = subprocess.run([str(CLI), "safe-mode", "on", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(enabled.returncode, 0, enabled.stderr)
            self.assertTrue(json.loads(enabled.stdout)["active"])
            status = subprocess.run([str(CLI), "safe-mode", "status", "--json"], env=env, capture_output=True, text=True)
            self.assertTrue(json.loads(status.stdout)["active"])
            disabled = subprocess.run([str(CLI), "safe-mode", "off", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(disabled.returncode, 0, disabled.stderr)
            self.assertFalse(json.loads(disabled.stdout)["active"])


if __name__ == "__main__":
    unittest.main()
