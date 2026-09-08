from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import tarfile
import tempfile
import unittest

from scripts import support_bundle


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

    def test_multitasking_fixture_reports_guided_matrix_without_certifying_hardware(self) -> None:
        script = ROOT / "scripts" / "hardware_test.py"
        result = subprocess.run(
            ["python3", str(script), "--fixture", str(ROOT / "tests" / "fixtures" / "hardware-multitasking.json"), "--json"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        expected = {
            "touch-drag-window", "touch-snap", "divider-drag", "dock-to-split",
            "overview-to-split", "portrait-split", "rotation", "stylus-drag",
        }
        scenarios = payload["capabilities"]["multitasking"]
        self.assertEqual(set(scenarios), expected)
        self.assertTrue(all(item["result"] == "Untested" for item in scenarios.values()))
        self.assertFalse(payload["realHardwareValidated"])
        self.assertFalse(payload["guided"]["available"])

    def test_multitasking_portable_gate_separates_contract_pass_from_fixture_evidence(self) -> None:
        result = subprocess.run(
            ["python3", str(ROOT / "scripts" / "multitasking_check.py"), "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["portableSafety"]["result"], "Pass")
        self.assertFalse(payload["hardware"]["realHardwareValidated"])
        self.assertTrue(all(item["result"] == "Untested" for item in payload["hardware"]["scenarios"].values()))

    def test_guided_multitasking_requires_an_interactive_confirmed_session(self) -> None:
        script = ROOT / "scripts" / "hardware_test.py"
        with tempfile.TemporaryDirectory() as temporary:
            session = pathlib.Path(temporary) / "session.json"
            result = subprocess.run(
                ["python3", str(script), "--guided", "--session", str(session), "--confirm-hardware", "--json"],
                capture_output=True,
                text=True,
                input="",
            )
            self.assertEqual(result.returncode, 78)
            self.assertIn("interactive terminal", result.stdout)
            self.assertFalse(session.exists())

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

    def test_adaptive_cli_mode_features_controls_and_device_privacy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            shell = fake_bin / "omarchy-shell"
            shell.write_text(
                "#!/usr/bin/env bash\n"
                "case \"${2:-}\" in\n"
                "  status)\n"
                "    printf '%s\\n' '{\"version\":\"1.2.0\",\"service\":\"ready\",\"enabled\":true,\"suspended\":false,\"profile\":\"auto\",\"mode\":\"tablet\",\"effectiveMode\":\"tablet\",\"transitioning\":false,\"keyboardState\":\"disconnected\",\"keyboardStable\":true,\"hasTouchscreen\":true,\"physicalKeyboard\":false,\"detachableKeyboard\":false,\"bluetoothKeyboard\":false,\"physicalKeyboardCount\":0,\"tabletMode\":{\"mode\":\"tablet\",\"reason\":\"touchscreen present without physical keyboard\"},\"dockedMode\":{\"active\":false,\"externalMonitor\":false,\"externalMonitorCount\":0,\"phase\":\"undocked\",\"reason\":\"not-evaluated\"},\"keyboardTransition\":{\"phase\":\"Disconnected\",\"modeReason\":\"keyboard detached\"},\"keyboards\":[{\"id\":\"aa:bb:cc:dd:ee:ff\",\"name\":\"PRIVATE-SERIAL-123\",\"classification\":\"detachable\",\"transport\":\"bluetooth\",\"connected\":false,\"behavior\":\"hybrid\",\"capabilities\":{\"normalKeyboard\":true}}],\"features\":{\"total\":2,\"available\":2,\"active\":1,\"partial\":true,\"states\":[{\"id\":\"gestures\",\"label\":\"Gestures\",\"configPath\":\"multitasking.gestures.enabled\",\"available\":true,\"effectiveEnabled\":true,\"userEnabled\":true,\"disabledReason\":\"\",\"temporarilySuppressed\":false,\"overrideSource\":\"user\",\"profile\":\"auto\"},{\"id\":\"snap-assist\",\"label\":\"Snap Assist\",\"configPath\":\"multitasking.snapAssist.enabled\",\"available\":true,\"effectiveEnabled\":false,\"userEnabled\":true,\"disabledReason\":\"Gaming profile\",\"temporarilySuppressed\":true,\"overrideSource\":\"profile\",\"profile\":\"gaming\"}]}}'\n"
                "    ;;\n"
                "  enable|disable|suspend|resume|feature) printf 'ok\\n' ;;\n"
                "  *) exit 1 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            shell.chmod(shell.stat().st_mode | stat.S_IXUSR)
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

            mode = subprocess.run([str(CLI), "mode-info", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(mode.returncode, 0, mode.stderr)
            mode_payload = json.loads(mode.stdout)
            self.assertEqual(mode_payload["policy"], "Auto")
            self.assertEqual(mode_payload["effective"], "Tablet")
            self.assertEqual(mode_payload["keyboard"], "detached")
            self.assertEqual(mode_payload["posture"], "Tablet")
            self.assertEqual(mode_payload["touch"], "present")
            self.assertFalse(mode_payload["externalMonitor"])
            self.assertFalse(mode_payload["privacy"]["serialsEmitted"])

            feature_list = subprocess.run([str(CLI), "feature", "list", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(feature_list.returncode, 0, feature_list.stderr)
            feature_payload = json.loads(feature_list.stdout)
            self.assertEqual(feature_payload["summary"]["total"], 2)
            self.assertFalse(feature_payload["features"][1]["effectiveEnabled"])

            for command in (("enable",), ("disable",), ("suspend",), ("resume",), ("master", "off"), ("feature", "disable", "gestures")):
                with self.subTest(command=command):
                    result = subprocess.run([str(CLI), *command, "--json"], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(json.loads(result.stdout)["ok"])

            devices = subprocess.run([str(CLI), "devices", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(devices.returncode, 0, devices.stderr)
            device_payload = json.loads(devices.stdout)
            self.assertEqual(device_payload["physicalKeyboards"][0]["classification"], "detachable")
            self.assertNotIn("aa:bb:cc:dd:ee:ff", devices.stdout)
            self.assertNotIn("PRIVATE-SERIAL-123", devices.stdout)

    def test_status_redacts_hotplug_and_mapping_identifiers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            shell = fake_bin / "omarchy-shell"
            shell.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' '{\"service\":\"ready\",\"inputDevices\":{\"hotplug\":{\"available\":true,\"lastEvent\":\"input\",\"lastAction\":\"remove\",\"lastDevice\":\"/devices/private/serial/AA:BB:CC:DD:EE:FF\"}},\"inputMapping\":{\"plan\":[{\"id\":\"/dev/input/event9\",\"role\":\"keyboard\",\"output\":\"DP-1\"}],\"explanation\":[\"/dev/input/event9 -> DP-1\"]},\"keyboards\":[{\"id\":\"aa:bb:cc:dd:ee:ff\",\"name\":\"PRIVATE-SERIAL-123\",\"classification\":\"external\",\"transport\":\"bluetooth\"}]}'\n",
                encoding="utf-8",
            )
            shell.chmod(shell.stat().st_mode | stat.S_IXUSR)
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
            result = subprocess.run([str(CLI), "status", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("/devices/private/serial", result.stdout)
            self.assertNotIn("/dev/input/event9", result.stdout)
            self.assertNotIn("aa:bb:cc:dd:ee:ff", result.stdout.lower())
            self.assertNotIn("private-serial-123", result.stdout.lower())

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

    def test_private_support_bundle_uses_aggressive_redaction_contract(self) -> None:
        redacted = support_bundle.redact(
            {
                "name": "Private serial label",
                "address": "AA:BB:CC:DD:EE:FF",
                "text": "typed content",
                "safe": "capability-only",
            },
            "/tmp/private-home",
            True,
        )
        self.assertEqual(redacted["name"], "<redacted>")
        self.assertEqual(redacted["address"], "<redacted>")
        self.assertEqual(redacted["text"], "<redacted>")
        self.assertEqual(redacted["safe"], "capability-only")

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
            output = root / "private-support.tar.gz"
            result = subprocess.run(
                [str(CLI), "diagnostics", "export", str(output), "--private"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)["private"])
            with tarfile.open(output, "r:gz") as archive:
                report = archive.extractfile("report.json").read().decode("utf-8")
            self.assertIn('"mode": "private"', report)
            self.assertNotIn("do-not-export", report)

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
