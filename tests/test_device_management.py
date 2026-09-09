from __future__ import annotations

import copy
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = ROOT / "cli" / "omanome"
CONFIG_TOOL = ROOT / "scripts" / "config_tool.py"
DEFAULTS = json.loads((ROOT / "config" / "defaults.json").read_text(encoding="utf-8"))


class DeviceManagementTests(unittest.TestCase):
    def run_config_tool(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CONFIG_TOOL), *arguments],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def test_device_rollback_restores_persistent_lkg_and_reset_removes_owned_metadata(self) -> None:
        device = "device:touchscreen:1111111111111111"
        previous_output = "display:2222222222222222"
        current_output = "display:3333333333333333"
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "config.json"
            config = copy.deepcopy(DEFAULTS)
            config["deviceProfiles"]["profiles"][device] = {
                "schemaVersion": 2,
                "id": device,
                "category": "touchscreen",
                "touch": {"mappingOutput": current_output, "calibrationId": "calibration-touchscreen-1"},
            }
            config["deviceProfiles"]["calibrations"]["entries"] = {
                "calibration-touchscreen-1": {
                    "schemaVersion": 1,
                    "id": "calibration-touchscreen-1",
                    "kind": "touchscreen",
                    "deviceId": device,
                    "outputId": current_output,
                    "mapping": {"outputId": current_output, "scale": {"x": 1, "y": 1}, "offset": {"x": 0, "y": 0}, "rotation": 90},
                    "lastKnownGood": {"outputId": previous_output, "scale": {"x": 1, "y": 1}, "offset": {"x": 0, "y": 0}, "rotation": 0},
                    "status": "confirmed",
                    "revision": 2,
                    "updatedAt": 2,
                }
            }
            path.write_text(json.dumps(config), encoding="utf-8")

            rollback = self.run_config_tool("device", "rollback", str(path), device, "--json")
            self.assertEqual(rollback.returncode, 0, rollback.stderr)
            rollback_payload = json.loads(rollback.stdout)
            self.assertEqual(rollback_payload["action"], "rollback")
            self.assertEqual(rollback_payload["restored"][0]["outputId"], previous_output)
            restored = json.loads(path.read_text(encoding="utf-8"))
            entry = restored["deviceProfiles"]["calibrations"]["entries"]["calibration-touchscreen-1"]
            self.assertEqual(entry["mapping"]["outputId"], previous_output)
            self.assertIsNone(entry["lastKnownGood"])
            self.assertEqual(restored["deviceProfiles"]["profiles"][device]["touch"]["mappingOutput"], previous_output)
            self.assertTrue(pathlib.Path(rollback_payload["backup"]).is_file())

            reset = self.run_config_tool("device", "reset", str(path), device, "--json")
            self.assertEqual(reset.returncode, 0, reset.stderr)
            reset_payload = json.loads(reset.stdout)
            self.assertTrue(reset_payload["profileRemoved"])
            self.assertEqual(reset_payload["calibrationsRemoved"], 1)
            final = json.loads(path.read_text(encoding="utf-8"))
            self.assertNotIn(device, final["deviceProfiles"]["profiles"])
            self.assertEqual(final["deviceProfiles"]["calibrations"]["entries"], {})

    def test_hardware_setup_namespace_lists_applies_and_reports_without_replacing_installer_setup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            environment = os.environ.copy()
            environment.update({
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_STATE_HOME": str(root / "state"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "PATH": f"/usr/bin:/bin:{environment['PATH']}",
            })
            listed = subprocess.run([str(CLI), "hardware-setup", "list", "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(listed.returncode, 0, listed.stderr)
            self.assertIn("portable", {row["id"] for row in json.loads(listed.stdout)["setups"]})

            applied = subprocess.run([str(CLI), "hardware-setup", "apply", "portable", "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(applied.returncode, 0, applied.stderr)
            status = subprocess.run([str(CLI), "hardware-setup", "status", "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(status.returncode, 0, status.stderr)
            status_payload = json.loads(status.stdout)
            self.assertEqual(status_payload["selected"], "portable")
            self.assertEqual(status_payload["setup"]["preferredAdaptiveProfile"], "hybrid")
            self.assertEqual(status_payload["runtime"]["source"], "unavailable")

            installer = subprocess.run([str(CLI), "setup"], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(installer.returncode, 0, installer.stderr)
            self.assertIn("Omanome setup is user-only", installer.stdout)

    def test_device_info_and_test_use_one_sanitized_graph_boundary(self) -> None:
        device = "device:touchscreen:aaaaaaaaaaaaaaaa"
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            shell = fake_bin / "omarchy-shell"
            graph = {
                "schemaVersion": 1,
                "source": "service",
                "graph": {
                    "health": {"available": True, "backend": "compositor", "reason": "ready"},
                    "nodes": [{"id": device, "label": "Touch panel", "category": "touchscreen", "transport": "usb", "connected": True, "confidence": "confirmed", "capabilities": {"absolute": True}}],
                    "outputs": [{"id": "display:bbbbbbbbbbbbbbbb", "name": "Internal", "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080}, "connected": True, "role": "internal", "confidence": "confirmed"}],
                    "relationships": [],
                },
            }
            shell.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"${2:-}\" == hardwareGraph ]]; then\n"
                f"  printf '%s\\n' {json.dumps(json.dumps(graph))}\n"
                "else\n"
                "  exit 1\n"
                "fi\n",
                encoding="utf-8",
            )
            shell.chmod(shell.stat().st_mode | stat.S_IXUSR)
            environment = os.environ.copy()
            environment.update({
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_STATE_HOME": str(root / "state"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "PATH": f"{fake_bin}:/usr/bin:/bin",
            })
            info = subprocess.run([str(CLI), "device", "info", device, "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(info.returncode, 0, info.stderr)
            info_payload = json.loads(info.stdout)
            self.assertTrue(info_payload["health"]["connected"])
            self.assertEqual(info_payload["node"]["id"], device)
            self.assertTrue(info_payload["privacy"]["rawHardwareIdentifiersEmitted"] is False)

            test = subprocess.run([str(CLI), "device", "test", device, "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(test.returncode, 0, test.stderr)
            test_payload = json.loads(test.stdout)
            self.assertTrue(test_payload["overall"])
            self.assertFalse(test_payload["physicalInputTested"])
            self.assertEqual(test_payload["certification"]["status"], "Untested")

    def test_device_mutations_recover_from_malformed_revision_values(self) -> None:
        device = "device:touchscreen:aaaaaaaaaaaaaaaa"
        output = "display:bbbbbbbbbbbbbbbb"
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "config.json"
            config = copy.deepcopy(DEFAULTS)
            config["deviceProfiles"]["revision"] = "not-a-number"
            config["deviceProfiles"]["calibrations"]["revision"] = "also-not-a-number"
            config["deviceProfiles"]["profiles"][device] = {
                "schemaVersion": 2,
                "id": device,
                "category": "touchscreen",
                "touch": {"mappingOutput": output, "calibrationId": "calibration-touchscreen-2"},
            }
            config["deviceProfiles"]["calibrations"]["entries"] = {
                "calibration-touchscreen-2": {
                    "schemaVersion": 1,
                    "id": "calibration-touchscreen-2",
                    "kind": "touchscreen",
                    "deviceId": device,
                    "outputId": output,
                    "mapping": {"outputId": output, "scale": {"x": 1, "y": 1}, "offset": {"x": 0, "y": 0}, "rotation": 0},
                    "lastKnownGood": None,
                },
            }
            path.write_text(json.dumps(config), encoding="utf-8")
            reset = self.run_config_tool("device", "reset", str(path), device, "--json")
            self.assertEqual(reset.returncode, 0, reset.stderr)
            payload = json.loads(reset.stdout)
            self.assertTrue(payload["ok"])
            self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["deviceProfiles"]["revision"], 1)


if __name__ == "__main__":
    unittest.main()
