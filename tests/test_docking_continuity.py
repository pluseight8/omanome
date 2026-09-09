from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DockingContinuityTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_docking_is_debounced_and_captures_only_opaque_continuity_intent(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const D=require('./shell/models/DockingContinuity.js'); "
            "const graph=G.fromSnapshot({monitors:["
            "{name:'Panel',builtin:true,role:'internal',geometry:{x:0,y:0,width:1920,height:1080}},"
            "{name:'Dock monitor',external:true,role:'external',geometry:{x:1920,y:0,width:2560,height:1440}}]}); "
            "const context={docked:true,keyboardConnected:true,keyboardStable:true,mode:'desktop',orientation:'normal',primaryDisplayId:graph.outputs[0].id,oskOutputId:graph.outputs[1].id,surfaceOutputs:[graph.outputs[1].id],setupId:'desk'}; "
            "const first=D.observe(D.emptyState(),graph,context,1000,{debounceMs:180}); const second=D.observe(first.state,graph,context,1180,{debounceMs:180}); "
            "console.log(JSON.stringify({first,second,summary:D.summary(second.state),text:JSON.stringify(second.state)}));"
        )
        self.assertTrue(result["first"]["pending"])
        self.assertEqual(result["first"]["state"]["phase"], "docking")
        self.assertTrue(result["second"]["changed"])
        self.assertEqual(result["summary"]["phase"], "docked")
        self.assertTrue(result["summary"]["active"])
        self.assertTrue(result["summary"]["continuity"]["valid"])
        self.assertEqual(len(result["summary"]["continuity"]["savedExternalIds"]), 1)
        self.assertNotIn("Dock monitor", result["text"])
        self.assertNotIn("1920", result["text"])

    def test_disconnect_creates_bounded_restore_plan_and_requires_choice_without_target(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const D=require('./shell/models/DockingContinuity.js'); "
            "const full=G.fromSnapshot({monitors:[{name:'Dock monitor',role:'external',external:true,geometry:{x:0,y:0,width:2560,height:1440}}]}); "
            "const none=G.fromSnapshot({monitors:[]}); const context={docked:true,keyboardConnected:true,keyboardStable:true,mode:'desktop',orientation:'normal',surfaceOutputs:[full.outputs[0].id],oskOutputId:full.outputs[0].id,setupId:'desk'}; "
            "let dock=D.observe(D.emptyState(),full,context,2000,{debounceMs:100}); dock=D.observe(dock.state,full,context,2100,{debounceMs:100}); "
            "const undock=D.observe(dock.state,none,{docked:false,keyboardConnected:true,keyboardStable:true,mode:'desktop'},2200,{debounceMs:100}); const acknowledged=D.acknowledgeRestore(undock.state,true); "
            "console.log(JSON.stringify({dock,undock,acknowledged,summary:D.summary(undock.state)}));"
        )
        self.assertEqual(result["dock"]["state"]["phase"], "docked")
        self.assertTrue(result["undock"]["changed"])
        self.assertEqual(result["summary"]["phase"], "recovering")
        self.assertTrue(result["summary"]["rollback"]["required"])
        self.assertTrue(result["summary"]["restore"]["pending"])
        self.assertTrue(result["summary"]["restore"]["requiresChoice"])
        self.assertEqual(result["summary"]["restore"]["targetDisplayId"], "")
        self.assertIn("restore-layout", result["summary"]["restore"]["actions"])
        self.assertFalse(result["acknowledged"]["restore"]["pending"])

    def test_unknown_display_role_does_not_activate_docking_and_resume_is_recovering(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const D=require('./shell/models/DockingContinuity.js'); "
            "const unknown=G.fromSnapshot({monitors:[{name:'Monitor',geometry:{x:0,y:0,width:1920,height:1080}}]}); "
            "const initial=D.observe(D.emptyState(),unknown,{keyboardConnected:true,keyboardStable:true,mode:'desktop'},3000,{debounceMs:80}); "
            "const paused=D.lifecycle(initial.state,{event:'suspend'},3100); const resumed=D.lifecycle(paused,{event:'resume'},3200); "
            "console.log(JSON.stringify({initial,paused,resumed,summary:D.summary(resumed)}));"
        )
        self.assertFalse(result["initial"]["state"]["active"])
        self.assertEqual(result["initial"]["state"]["phase"], "undocked")
        self.assertEqual(result["paused"]["phase"], "paused")
        self.assertTrue(result["paused"]["paused"])
        self.assertEqual(result["summary"]["phase"], "recovering")
        self.assertFalse(result["summary"]["paused"])
        self.assertTrue(result["summary"]["pending"])

    def test_service_wires_docking_continuity_and_config_keeps_policy_separate(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('"models/DockingContinuity.js" as DockingContinuityModel', service)
        self.assertIn("property var dockingContinuityState", service)
        self.assertIn("DockingContinuityModel.observe", service)
        self.assertIn("DockingContinuityModel.lifecycle", service)
        self.assertIn("dockingContinuity: DockingContinuityModel.summary", service)
        expression = (
            "const C=require('./shell/models/Config.js'); const d=C.defaults(); "
            "console.log(JSON.stringify({hardware:d.hardwareSetupProfiles,adaptive:d.adaptive.dockedMode,"
            "migrate:C.migrateDetailed({schemaVersion:2,adaptive:{profile:'desktop'}}).config.hardwareSetupProfiles}));"
        )
        result = self.run_node(expression)
        self.assertEqual(result["hardware"]["schemaVersion"], 1)
        self.assertEqual(result["hardware"]["displayPolicy"]["oskTarget"], "focused-display")
        self.assertIn("trigger", result["adaptive"])
        self.assertEqual(result["migrate"]["schemaVersion"], 1)


if __name__ == "__main__":
    unittest.main()
