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
        self.assertEqual(payload["certification"]["evidence"], "fixture")
        self.assertEqual(payload["certification"]["status"], "Untested")
        self.assertTrue(payload["capabilities"]["touchscreen"]["available"])
        self.assertTrue(payload["capabilities"]["stylus"]["available"])

    def test_extended_hardware_fixtures_report_capabilities_without_certifying_hardware(self) -> None:
        cases = (
            ("stylus-events.json", ("pressure", "tilt", "distance", "rotation", "eraser", "buttons", "proximity")),
            ("suspend-resume.json", ("pressure", "proximity")),
        )
        for filename, features in cases:
            with self.subTest(filename=filename):
                result = subprocess.run(
                    ["python3", str(ROOT / "scripts/hardware_test.py"), "--fixture", str(ROOT / "tests/fixtures" / filename), "--json"],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                payload = json.loads(result.stdout)
                self.assertFalse(payload["realHardwareValidated"])
                for feature in features:
                    self.assertTrue(payload["capabilities"]["stylusFeatures"][feature]["available"])
                for section in ("display", "touch", "multitouch", "stylus", "pressure", "tilt", "eraser", "stylusButtons", "keyboard", "detachableKeyboard", "orientation", "osk", "suspendResume", "multiMonitor"):
                    self.assertIn(section, payload["capabilities"]["certification"])
                self.assertTrue(payload["capabilities"]["lifecycle"]["hotplug"]["available"])
                if filename == "suspend-resume.json":
                    self.assertTrue(payload["capabilities"]["lifecycle"]["suspendResume"]["available"])
                    for section in ("display", "multitouch", "detachableKeyboard", "orientation", "osk", "multiMonitor"):
                        self.assertTrue(payload["capabilities"]["certification"][section]["available"])
                self.assertFalse(payload["capabilities"]["handwriting"]["cloud"]["available"])

    def test_hardware_session_is_private_resumable_and_never_mixes_fixture_evidence(self) -> None:
        script = ROOT / "scripts" / "hardware_test.py"
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            session = root / "session.json"
            report = root / "report.json"
            first = subprocess.run(
                [
                    "python3",
                    str(script),
                    "--session",
                    str(session),
                    "--record",
                    "display=Skipped",
                    "--report",
                    str(report),
                    "--json",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            first_payload = json.loads(first.stdout)
            self.assertFalse(first_payload["realHardwareValidated"])
            self.assertEqual(first_payload["certification"]["status"], "Skipped")
            self.assertEqual(stat.S_IMODE(session.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(report.stat().st_mode), 0o600)
            session_payload = json.loads(session.read_text(encoding="utf-8"))
            self.assertEqual(session_payload["records"]["display"]["result"], "Skipped")
            self.assertNotIn("serial", session.read_text(encoding="utf-8").lower())

            resumed = subprocess.run(
                [
                    "python3",
                    str(script),
                    "--session",
                    str(session),
                    "--resume",
                    "--record",
                    "keyboard=Unavailable",
                    "--report",
                    str(report),
                    "--json",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            resumed_payload = json.loads(resumed.stdout)
            self.assertEqual(resumed_payload["certification"]["recordedCount"], 2)
            self.assertEqual(resumed_payload["certification"]["status"], "Unavailable")
            self.assertTrue(resumed_payload["certification"]["sessionPresent"])

    def test_hardware_pass_fail_require_explicit_live_confirmation(self) -> None:
        script = ROOT / "scripts" / "hardware_test.py"
        with tempfile.TemporaryDirectory() as temporary:
            session = pathlib.Path(temporary) / "session.json"
            result = subprocess.run(
                [
                    "python3",
                    str(script),
                    "--session",
                    str(session),
                    "--record",
                    "display=Pass",
                    "--json",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 78)
            self.assertIn("--confirm-hardware", result.stdout)
            self.assertFalse(session.exists())

    def test_fixture_record_is_rejected_as_hardware_certification(self) -> None:
        script = ROOT / "scripts" / "hardware_test.py"
        with tempfile.TemporaryDirectory() as temporary:
            session = pathlib.Path(temporary) / "session.json"
            result = subprocess.run(
                [
                    "python3",
                    str(script),
                    "--fixture",
                    str(ROOT / "tests" / "fixtures" / "hardware-tablet.json"),
                    "--session",
                    str(session),
                    "--record",
                    "stylus=Pass",
                    "--confirm-hardware",
                    "--json",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 78)
            self.assertIn("fixture evidence", result.stdout)
            self.assertFalse(session.exists())

    def test_stylus_and_touch_diagnostics_remain_json_without_hyprland(self) -> None:
        for operation in ("input-info", "stylus-info", "touch-info"):
            with self.subTest(operation=operation):
                result = subprocess.run([str(CLI), operation], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                payload = json.loads(result.stdout)
                self.assertEqual(payload["schemaVersion"], 1)
                self.assertIn("nativeBackend", payload)
                if operation == "input-info":
                    self.assertIn("protocolSupport", payload)
                    self.assertIn("privacy", payload)
                    self.assertIn("handwriting", payload)
                else:
                    self.assertIn("privacy", payload)
                if operation == "touch-info":
                    self.assertIn("modeReasoning", payload)

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

    def test_setup_refuses_symlink_managed_parent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            config_home = root / "config"
            config_home.mkdir()
            outside = root / "outside"
            outside.mkdir()
            (config_home / "omanome").symlink_to(outside, target_is_directory=True)
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
            result = subprocess.run([str(CLI), "setup"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("unsafe Omanome config directory", result.stderr)
            self.assertFalse((outside / "config.json").exists())

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

    def test_uninstall_stops_only_explicitly_owned_processes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env = self.make_uninstall_environment(root)
            owned_env = env.copy()
            owned_env["OMANOME_OWNER"] = "io.omanome.shell"
            owned_env["OMANOME_COMPONENT"] = "test-helper"
            owned = subprocess.Popen(["sleep", "30"], env=owned_env)
            foreign = subprocess.Popen(["sleep", "30"], env=env)
            try:
                result = subprocess.run([str(CLI), "uninstall", "--yes", "--json"], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                payload = json.loads(result.stdout)
                self.assertGreaterEqual(payload["ownedProcessesStopped"], 1)
                self.assertIsNotNone(owned.poll())
                self.assertIsNone(foreign.poll())
            finally:
                for process in (owned, foreign):
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
