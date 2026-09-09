from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DeviceQuirkTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_structural_match_is_visible_but_never_applied(self) -> None:
        result = self.run_node(
            "const Q=require('./shell/models/DeviceQuirks.js'); "
            "const db=Q.normalizeDatabase({entries:["
            "{id:'touch-panel',match:{category:'touchscreen',transport:'i2c',capabilitiesAll:['touchscreen']},knownIssue:'requires a confirmed mapping',workaround:'ask before mapping',documentation:'https://example.test/panel',testedVersion:'6.1',criticalMapping:true,overrides:{mappingMode:'manual'}},"
            "{id:'pretty-model-only',match:{model:'Panel'}}]}); "
            "const state=Q.evaluate(db,{nodes:[{id:'device:touchscreen:0123456789abcdef',category:'touchscreen',transport:'i2c',capabilities:{touchscreen:true}}]}); "
            "console.log(JSON.stringify({db,state,summary:Q.summary(state),text:JSON.stringify(Q.summary(state))}));"
        )
        self.assertEqual(len(result["db"]["entries"]), 1)
        self.assertEqual(result["state"]["matchedCount"], 1)
        self.assertTrue(result["state"]["applied"][0]["criticalMapping"])
        self.assertFalse(result["state"]["applied"][0]["applied"])
        self.assertEqual(result["state"]["applied"][0]["deviceId"], "device:touchscreen:0123456789abcdef")
        self.assertTrue(result["summary"]["criticalMappingBlocked"] == 1)
        self.assertNotIn("/dev/", result["text"])

    def test_generic_hardware_has_no_default_quirks_and_raw_values_are_rejected(self) -> None:
        result = self.run_node(
            "const Q=require('./shell/models/DeviceQuirks.js'); "
            "const empty=Q.evaluate({enabled:true,entries:[]},{nodes:[{id:'device:keyboard:0123456789abcdef',category:'keyboard',transport:'usb',capabilities:{keyboard:true}}]}); "
            "const unsafe=Q.normalizeDatabase({entries:[{id:'bad',match:{category:'keyboard'},knownIssue:'/dev/input/event4 aa:bb:cc:dd:ee:ff'}]}); "
            "console.log(JSON.stringify({empty,unsafe}));"
        )
        self.assertEqual(result["empty"]["matchedCount"], 0)
        self.assertEqual(result["empty"]["reason"], "no-quirks-configured")
        self.assertEqual(result["unsafe"]["entries"], [])

    def test_service_uses_quirks_as_a_diagnostics_boundary(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertIn('"models/DeviceQuirks.js" as DeviceQuirksModel', service)
        self.assertIn("DeviceQuirksModel.evaluate", service)
        self.assertIn("quirks: DeviceQuirksModel.summary", service)
        self.assertFalse(defaults["quirks"]["allowCriticalMapping"])
        self.assertEqual(schema["properties"]["quirks"]["properties"]["entries"]["maxItems"], 64)


if __name__ == "__main__":
    unittest.main()
