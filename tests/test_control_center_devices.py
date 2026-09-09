from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ControlCenterDeviceTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_compact_status_keeps_unknown_external_role_honest_and_exposes_mode(self) -> None:
        result = self.run_node(
            "const D=require('./shell/models/DeviceStatus.js'); "
            "const graph={revision:4,nodes:["
            "{category:'keyboard',connected:true,confidence:'confirmed'},"
            "{category:'touchscreen',connected:true,confidence:'probable'},"
            "{category:'stylus',connected:false,confidence:'confirmed'}],outputs:["
            "{id:'display:0123456789abcdef',connected:true,role:'unknown',confidence:'unknown'}]}; "
            "const state=D.snapshot(graph,{displays:{rows:[{connected:true,role:'unknown',confidence:'unknown'}]}},{effectiveMode:'tablet',adaptiveProfile:'auto',hasStylus:true}); "
            "console.log(JSON.stringify(state));"
        )
        rows = {row["key"]: row for row in result["rows"]}
        self.assertEqual(rows["mode"]["value"], "tablet")
        self.assertEqual(rows["keyboard"]["status"], "connected")
        self.assertEqual(rows["touch"]["status"], "connected")
        self.assertEqual(rows["stylus"]["status"], "disconnected")
        self.assertEqual(rows["external-display"]["status"], "unknown")
        self.assertEqual(rows["external-display"]["reason"], "external-role-unresolved")

    def test_grouped_notice_coalesces_multi_category_hotplug(self) -> None:
        result = self.run_node(
            "const D=require('./shell/models/DeviceStatus.js'); "
            "const before={nodes:[],outputs:[]}; const after={nodes:["
            "{category:'keyboard',connected:true},{category:'stylus',connected:true}],outputs:["
            "{connected:true,role:'external'}]}; "
            "console.log(JSON.stringify(D.connectionNotice(before,after,{eventCount:5,coalescedEvents:4},1000,null,{durationMs:2600})));"
        )
        self.assertTrue(result["visible"])
        self.assertEqual(result["key"], "connected")
        self.assertTrue(result["grouped"])
        self.assertEqual(result["coalescedEvents"], 4)
        self.assertIn("display", result["categories"])

    def test_control_center_is_compact_and_routes_to_device_center(self) -> None:
        view = (ROOT / "shell/views/ControlCenter.qml").read_text(encoding="utf-8")
        for marker in [
            "compactDeviceStatus",
            'value === "mode"',
            'value === "keyboard"',
            'value === "touch"',
            'value === "stylus"',
            'value === "external-display"',
            "Open Device Center",
            'activeView = "devices"',
            "grouped hotplug events",
        ]:
            self.assertIn(marker, view)
        self.assertNotIn("hyprctl", view)
        self.assertNotIn("Process", view)

    def test_service_exposes_compact_device_projection_and_grouped_notice(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        for marker in [
            '"models/DeviceStatus.js" as DeviceStatusModel',
            "property var compactDeviceState",
            "property var deviceConnectionNotice",
            "function updateCompactDeviceState",
            "function compactDeviceStatus",
            "DeviceStatusModel.connectionNotice",
            "compactDevices: root.compactDeviceStatus()",
        ]:
            self.assertIn(marker, service)


if __name__ == "__main__":
    unittest.main()
