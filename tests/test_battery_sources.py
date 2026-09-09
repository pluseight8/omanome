from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class BatterySourceTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_multiple_actual_sources_are_separate_and_private(self) -> None:
        result = self.run_node(
            "const B=require('./shell/models/BatterySources.js'); "
            "const state=B.fromSnapshot({batterySources:["
            "{nativePath:'/org/freedesktop/UPower/devices/battery_BAT0',model:'Tablet',role:'system',percentage:'75%',state:'discharging',serial:'PRIVATE',address:'aa:bb:cc:dd:ee:ff'},"
            "{nativePath:'/org/freedesktop/UPower/devices/battery_CMB0',model:'Cover',role:'peripheral',percent:60,state:'discharging'}]}); "
            "console.log(JSON.stringify({state,summary:B.summary(state),primary:B.primary(state),text:JSON.stringify(B.summary(state))}));"
        )
        self.assertTrue(result["state"]["available"])
        self.assertEqual(len(result["state"]["sources"]), 2)
        self.assertEqual(result["state"]["aggregate"]["percent"], 75)
        self.assertEqual(result["state"]["sources"][1]["role"], "peripheral")
        self.assertNotIn("/org/freedesktop/UPower", result["text"])
        self.assertNotIn("PRIVATE", result["text"])
        self.assertNotIn("aa:bb:cc:dd:ee:ff", result["text"])
        self.assertTrue(result["state"]["privacy"]["rawPathsEmitted"] is False)

    def test_absent_sources_do_not_create_a_fake_keyboard_or_battery(self) -> None:
        result = self.run_node(
            "const B=require('./shell/models/BatterySources.js'); "
            "const empty=B.fromSnapshot({batterySources:[]}); "
            "const invalid=B.fromSnapshot({batterySources:[{},null,{present:false,id:'removed'}, {id:'bad',percent:150,state:'wat'}]}); "
            "const event=B.applyEvent(empty,{type:'power.event',source:'upower',action:'change',nativePath:'/private'}); "
            "console.log(JSON.stringify({empty,invalid,event,text:JSON.stringify(event)}));"
        )
        self.assertFalse(result["empty"]["available"])
        self.assertEqual(result["empty"]["sources"], [])
        self.assertEqual(result["invalid"]["sources"], [])
        self.assertTrue(result["event"]["pendingRefresh"])
        self.assertEqual(result["event"]["lastEvent"]["type"], "power.event")
        self.assertNotIn("/private", result["text"])

    def test_service_and_config_expose_event_driven_power_contract(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        monitor = (ROOT / "input/power-monitor.sh").read_text(encoding="utf-8")
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertIn('"models/BatterySources.js" as BatterySourcesModel', service)
        self.assertIn("BatterySourcesModel.fromSnapshot", service)
        self.assertIn("function updatePowerEvent", service)
        self.assertIn("function startPowerMonitor", service)
        self.assertIn("gdbus monitor", monitor)
        self.assertIn("org.freedesktop.UPower", monitor)
        self.assertIn("power.event", monitor)
        self.assertNotIn("upower -e", monitor)
        self.assertTrue(defaults["power"]["batteryMonitor"])
        self.assertEqual(schema["properties"]["power"]["properties"]["schemaVersion"]["const"], 1)


if __name__ == "__main__":
    unittest.main()
