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
    def make_uninstall_environment(self, root: pathlib.Path) -> dict[str, str]:
        config_home = root / "config"
        state_home = root / "state"
        data_home = root / "data"
        cache_home = root / "cache"
        plugin = config_home / "omarchy" / "plugins" / "io.omanome.shell"
        plugin.mkdir(parents=True)
        (plugin / "manifest.json").write_text('{"id":"io.omanome.shell","version":"0.6.0","kinds":["service"]}\n', encoding="utf-8")
        config_dir = config_home / "omanome"
        config_dir.mkdir(parents=True)
        (config_dir / "config.json").write_text('{"schemaVersion":2,"personal":"keep"}\n', encoding="utf-8")
        (config_dir / "safe-mode").write_text('{"enabled":true}\n', encoding="utf-8")
        state_dir = state_home / "omanome"
        state_dir.mkdir(parents=True)
        ownership = {
            "schemaVersion": 1,
            "pluginId": "io.omanome.shell",
            "managedPaths": {
                "plugin": str(plugin),
                "config": str(config_dir),
                "state": str(state_dir),
                "cache": str(cache_home / "omanome"),
                "companion": str(data_home / "omanome" / "companion"),
            },
        }
        (state_dir / "ownership.json").write_text(json.dumps(ownership), encoding="utf-8")
        (cache_home / "omanome").mkdir(parents=True)
        (data_home / "omanome" / "companion").mkdir(parents=True)
        (root / "untouched.txt").write_text("keep\n", encoding="utf-8")
        fake_bin = root / "bin"
        fake_bin.mkdir()
        (fake_bin / "omarchy").write_text(
            "#!/usr/bin/env bash\nprintf '%s\\n' called >\"${OMANOME_OMARCHY_CALLED}\"\nexit 0\n",
            encoding="utf-8",
        )
        (fake_bin / "omarchy").chmod((fake_bin / "omarchy").stat().st_mode | stat.S_IXUSR)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(config_home),
                "XDG_STATE_HOME": str(state_home),
                "XDG_DATA_HOME": str(data_home),
                "XDG_CACHE_HOME": str(cache_home),
                "PATH": f"{fake_bin}:{env['PATH']}",
                "OMANOME_OMARCHY_CALLED": str(root / "omarchy-called"),
            }
        )
        return env

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

    def test_uninstall_dry_run_is_verified_and_non_destructive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env = self.make_uninstall_environment(root)
            result = subprocess.run([str(CLI), "uninstall", "--dry-run", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertTrue(payload["dryRun"])
            self.assertEqual(payload["ownership"]["status"], "verified")
            self.assertTrue(payload["targets"]["plugin"]["exists"])
            self.assertTrue((root / "config" / "omarchy" / "plugins" / "io.omanome.shell").exists())
            self.assertFalse((root / "omarchy-called").exists())

    def test_uninstall_refuses_symlink_targets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            config_home = root / "config"
            plugins = config_home / "omarchy" / "plugins"
            plugins.mkdir(parents=True)
            outside = root / "outside"
            outside.mkdir()
            (plugins / "io.omanome.shell").symlink_to(outside, target_is_directory=True)
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(root),
                    "XDG_CONFIG_HOME": str(config_home),
                    "XDG_STATE_HOME": str(root / "state"),
                    "XDG_DATA_HOME": str(root / "data"),
                    "XDG_CACHE_HOME": str(root / "cache"),
                }
            )
            result = subprocess.run([str(CLI), "uninstall", "--dry-run", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("unsafe plugin path", result.stderr)
            self.assertTrue(outside.exists())

    def test_uninstall_removes_owned_paths_but_keeps_settings_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env = self.make_uninstall_environment(root)
            result = subprocess.run([str(CLI), "uninstall", "--yes", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertTrue(payload["removed"])
            self.assertTrue(payload["omarchyPluginRemoved"])
            self.assertFalse((root / "config" / "omarchy" / "plugins" / "io.omanome.shell").exists())
            self.assertFalse((root / "state" / "omanome").exists())
            self.assertFalse((root / "cache" / "omanome").exists())
            self.assertFalse((root / "data" / "omanome" / "companion").exists())
            self.assertTrue((root / "config" / "omanome" / "config.json").exists())
            self.assertFalse((root / "config" / "omanome" / "safe-mode").exists())
            self.assertTrue((root / "untouched.txt").exists())


if __name__ == "__main__":
    unittest.main()
