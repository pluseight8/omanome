from __future__ import annotations

import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = ROOT / "cli/omanome"


class HardwareGraphCliTests(unittest.TestCase):
    def test_service_response_is_whitelisted_before_cli_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_bin = temp_path / "bin"
            fake_bin.mkdir()
            service_payload = json.dumps({
                "schemaVersion": 1,
                "source": "service",
                "graph": {
                    "revision": 7,
                    "nodes": [{
                        "id": "device:keyboard:0123456789abcdef",
                        "label": "/sys/devices/SECRET-SERIAL",
                        "serial": "SECRET-SERIAL",
                        "path": "/dev/input/event9",
                        "transport": "usb",
                        "category": "keyboard",
                        "capabilities": {"keyboard": True, "typedText": True},
                        "seat": "seat0",
                        "connected": True,
                        "parent": "device:dock:fedcba9876543210",
                        "relation": "attached-to",
                        "mappedOutput": "display:0123456789abcdef",
                        "mappingStatus": "mapped",
                        "formFactorRole": "external",
                        "capabilitySource": ["udev", "/sys/private"],
                        "confidence": "confirmed",
                    }],
                    "relationships": [{
                        "from": "device:keyboard:0123456789abcdef",
                        "to": "device:dock:fedcba9876543210",
                        "type": "attached-to",
                        "confidence": "confirmed",
                        "source": "/sys/private",
                    }],
                    "outputs": [{
                        "id": "display:0123456789abcdef",
                        "name": "HDMI-SECRET",
                        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                        "scale": 1,
                        "orientation": "normal",
                        "role": "external",
                        "connected": True,
                        "capabilitySource": ["compositor"],
                        "confidence": "confirmed",
                    }],
                    "health": {"available": True, "backend": "compositor", "reason": "ready"},
                },
                "battery": {
                    "available": True,
                    "backend": "upower",
                    "sourceCount": 1,
                    "sources": [{
                        "id": "device:battery:1111111111111111",
                        "label": "System battery",
                        "role": "system",
                        "kind": "battery",
                        "percent": 80,
                        "state": "discharging",
                        "connected": True,
                        "confidence": "confirmed",
                    }],
                    "aggregate": {"available": True, "id": "device:battery:1111111111111111", "role": "system", "percent": 80, "state": "discharging", "sourceCount": 1, "mixedState": False},
                    "reason": "upower-snapshot",
                },
                "powerMonitor": {"available": True, "reason": "upower-event-stream"},
                "quirks": {
                    "available": True,
                    "source": "config",
                    "matchedCount": 1,
                    "entries": 1,
                    "applied": [{
                        "id": "tablet-note",
                        "deviceId": "device:keyboard:0123456789abcdef",
                        "category": "keyboard",
                        "knownIssue": "Requires confirmation",
                        "workaround": "Use manual mapping",
                        "testedVersion": "1.3",
                        "criticalMapping": True,
                    }],
                    "criticalMappingBlocked": 1,
                    "reason": "quirks-matched",
                },
            }, separators=(",", ":"))
            (fake_bin / "omarchy-shell").write_text(
                f"#!/bin/sh\nprintf '%s\\n' '{service_payload}'\n",
                encoding="utf-8",
            )
            (fake_bin / "omarchy-shell").chmod(0o755)
            environment = os.environ.copy()
            environment.update({
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(temp_path / "home"),
                "XDG_CONFIG_HOME": str(temp_path / "config"),
                "XDG_STATE_HOME": str(temp_path / "state"),
                "XDG_CACHE_HOME": str(temp_path / "cache"),
            })
            result = subprocess.run([str(CLI), "hardware", "graph", "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["source"], "service")
        self.assertEqual(payload["graph"]["nodes"][0]["id"], "device:keyboard:0123456789abcdef")
        self.assertEqual(payload["graph"]["nodes"][0]["label"], "keyboard")
        self.assertNotIn("SECRET-SERIAL", result.stdout)
        self.assertNotIn("/sys", result.stdout)
        self.assertNotIn("event9", result.stdout)
        self.assertEqual(payload["graph"]["nodes"][0]["capabilities"], {"keyboard": True})
        self.assertNotIn('"typedText":', result.stdout)
        self.assertEqual(payload["battery"]["sourceCount"], 1)
        self.assertEqual(payload["battery"]["sources"][0]["id"], "device:battery:1111111111111111")
        self.assertTrue(payload["powerMonitor"]["available"])
        self.assertEqual(payload["quirks"]["criticalMappingBlocked"], 1)
        self.assertFalse(payload["quirks"]["automaticMappingApplied"])

    def test_graph_command_has_unavailable_fallback_without_a_second_probe(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            environment = os.environ.copy()
            environment.update({
                "PATH": "/usr/bin:/bin",
                "HOME": temp_dir,
                "XDG_CONFIG_HOME": str(pathlib.Path(temp_dir) / "config"),
                "XDG_STATE_HOME": str(pathlib.Path(temp_dir) / "state"),
                "XDG_CACHE_HOME": str(pathlib.Path(temp_dir) / "cache"),
            })
            result = subprocess.run([str(CLI), "hardware", "graph", "--json"], cwd=ROOT, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["source"], "unavailable")
        self.assertFalse(payload["graph"]["health"]["available"])
        self.assertTrue(payload["privacy"]["eventNodesEmitted"] is False)
        self.assertEqual(payload["battery"]["sourceCount"], 0)
        self.assertFalse(payload["powerMonitor"]["available"])
        self.assertEqual(payload["quirks"]["source"], "none")

    def test_cli_and_ipc_contract_are_declared(self) -> None:
        cli = CLI.read_text(encoding="utf-8")
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn("hardware graph [--json]", cli)
        self.assertIn("hardware_graph_cmd", cli)
        self.assertIn('hardwareGraph 2>/dev/null', cli)
        self.assertIn('function hardwareGraph(): string', service)
        self.assertIn('function hardwareGraphJson()', service)
        self.assertNotIn("hyprctl devices", cli[cli.index("hardware_graph_cmd") : cli.index("input_info_cmd")])


if __name__ == "__main__":
    unittest.main()
