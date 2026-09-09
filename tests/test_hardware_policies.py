from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class HardwarePolicyTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_display_roles_require_explicit_evidence_and_primary_is_user_policy(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const H=require('./shell/models/HardwarePolicies.js'); "
            "const graph=G.fromSnapshot({monitors:["
            "{name:'Panel',geometry:{x:0,y:0,width:1920,height:1080},builtin:true,role:'internal'},"
            "{name:'External',geometry:{x:1920,y:0,width:1920,height:1080}},"
            "{name:'eDP-1',geometry:{x:3840,y:0,width:1920,height:1080}}]}); "
            "const policy={primaryDisplay:graph.outputs[0].id,roles:{}}; "
            "const first=H.displayRows(graph,policy); const set=H.setDisplayRole(policy,graph.outputs[1].id,'presentation'); "
            "const second=H.displayRows(graph,set.policy); console.log(JSON.stringify({first,second,text:JSON.stringify(second)}));"
        )
        self.assertEqual(result["first"]["rows"][0]["role"], "primary")
        self.assertEqual(result["first"]["rows"][0]["baseRole"], "internal")
        self.assertEqual(result["first"]["rows"][1]["role"], "unknown")
        self.assertEqual(result["first"]["unknownCount"], 2)
        self.assertEqual(result["second"]["rows"][1]["role"], "presentation")
        self.assertEqual(result["second"]["rows"][1]["roleSource"], "user")
        self.assertNotIn("/dev/", result["text"])

    def test_osk_target_never_guesses_between_displays(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const H=require('./shell/models/HardwarePolicies.js'); "
            "const graph=G.fromSnapshot({monitors:["
            "{name:'Internal',builtin:true,role:'internal',geometry:{x:0,y:0,width:1920,height:1080}},"
            "{name:'External',external:true,role:'external',geometry:{x:1920,y:0,width:1920,height:1080}}],devices:["
            "{name:'Touch',type:'touchscreen',vendorId:'1',productId:'2',path:'usb-1-2',mappedOutput:'External',capabilities:{touchscreen:true}}]}); "
            "const touch=graph.nodes.find(n=>n.category==='touchscreen'); const primary={primaryDisplay:graph.outputs[0].id,oskTarget:'primary-touch',roles:{}}; "
            "const mapped=H.resolveOskTarget(graph,touch,primary,{}); "
            "const focused=H.resolveOskTarget(graph,touch,{...primary,oskTarget:'focused-display'},{focusedDisplayId:graph.outputs[1].id}); "
            "const missing=H.resolveOskTarget(graph,{...touch,mappedOutput:''},{...primary,primaryDisplay:'',oskTarget:'primary-touch'},{}); "
            "const asked=H.resolveOskTarget(graph,touch,{...primary,oskTarget:'ask'},{}); "
            "console.log(JSON.stringify({mapped,focused,missing,asked}));"
        )
        self.assertEqual(result["mapped"]["status"], "resolved")
        self.assertEqual(result["mapped"]["reason"], "explicit-input-mapping")
        self.assertEqual(result["mapped"]["outputId"], result["focused"]["outputId"])
        self.assertEqual(result["focused"]["source"], "focused-display")
        self.assertEqual(result["missing"]["status"], "unavailable")
        self.assertEqual(result["missing"]["outputId"], "")
        self.assertEqual(result["asked"]["status"], "ask")

    def test_power_policy_is_battery_aware_but_does_not_claim_unknown_state(self) -> None:
        result = self.run_node(
            "const H=require('./shell/models/HardwarePolicies.js'); "
            "const critical=H.powerDecision({powerProfileAvailable:true,powerProfile:'performance',batteryAvailable:true,batteryState:'discharging',batteryPercent:10},{powerPolicy:'performance'},{disablePerformanceOnBattery:true}); "
            "const normal=H.powerDecision({powerProfileAvailable:true,powerProfile:'performance',batteryAvailable:true,batteryState:'discharging',batteryPercent:45},{powerPolicy:'performance'},{disablePerformanceOnBattery:true}); "
            "const unknown=H.powerDecision({powerProfileAvailable:true,powerProfile:'balanced',batteryState:'unknown',batteryPercent:-1},{powerPolicy:'performance'},{disablePerformanceOnBattery:true}); "
            "const unavailable=H.powerDecision({powerProfileAvailable:false,powerProfile:'balanced',batteryState:'discharging',batteryPercent:5},{powerPolicy:'performance'},{}); "
            "console.log(JSON.stringify({critical,normal,unknown,unavailable}));"
        )
        self.assertEqual(result["critical"]["desired"], "power-saver")
        self.assertEqual(result["critical"]["reason"], "critical-battery")
        self.assertEqual(result["normal"]["desired"], "balanced")
        self.assertEqual(result["normal"]["reason"], "performance-disabled-on-battery")
        self.assertEqual(result["unknown"]["desired"], "performance")
        self.assertEqual(result["unknown"]["batteryPercent"], -1)
        self.assertEqual(result["unavailable"]["desired"], "")
        self.assertFalse(result["unavailable"]["applyAllowed"])

    def test_setup_profiles_are_whitelisted_and_auto_selection_uses_runtime_mode(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const H=require('./shell/models/HardwarePolicies.js'); const C=require('./shell/models/Config.js'); "
            "const display='display:0123456789abcdef'; const store=H.normalizeStore({selected:'evil',profiles:{tablet:{label:'Tablet',powerPolicy:'power-saver'},evil:{label:'/private/path',powerPolicy:'performance'},presentation:{displayRole:'presentation',oskTarget:'disabled'}},displayPolicy:{primaryDisplay:display,roles:{[display]:'external',raw:'/tmp'}}}); "
            "const graph=G.fromSnapshot({monitors:[{name:'Panel',id:'panel',geometry:{x:0,y:0,width:1920,height:1080},role:'internal'}]}); const resolved=H.resolveSetup(graph,store,{mode:'tablet',system:{powerProfileAvailable:true,powerProfile:'balanced',batteryState:'unknown'}}); const migrated=C.migrateDetailed({schemaVersion:2,adaptive:{profile:'tablet'}}); "
            "console.log(JSON.stringify({store,resolved:migrated.ok&&resolved,summary:H.summary(resolved),config:migrated.config.hardwareSetupProfiles,applied:migrated.applied}));"
        )
        self.assertEqual(result["store"]["selected"], "auto")
        self.assertIn("tablet", result["store"]["profiles"])
        self.assertNotIn("evil", result["store"]["profiles"])
        self.assertEqual(len(result["store"]["displayPolicy"]["roles"]), 1)
        self.assertEqual(result["resolved"]["selected"], "tablet")
        self.assertEqual(result["summary"]["selected"], "tablet")
        self.assertEqual(result["config"]["schemaVersion"], 1)
        self.assertIn("hardware-setup-profiles-1.0-defaults", result["applied"])

    def test_service_and_config_schema_expose_hardware_policy_state(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertIn('"models/HardwarePolicies.js" as HardwarePoliciesModel', service)
        self.assertIn("property var hardwareSetupStore", service)
        self.assertIn("property var hardwarePolicyState", service)
        self.assertIn("HardwarePoliciesModel.resolveSetup", service)
        self.assertIn("hardwarePolicies: HardwarePoliciesModel.summary", service)
        self.assertIn("hardwareSetupProfiles", defaults)
        self.assertEqual(schema["properties"]["hardwareSetupProfiles"]["properties"]["schemaVersion"]["const"], 1)

    def test_setup_profiles_store_policy_and_match_complete_topology_only(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const H=require('./shell/models/HardwarePolicies.js'); "
            "const graph=G.fromSnapshot({monitors:[{id:'panel',name:'Panel',builtin:true,role:'internal'}],devices:[{id:'kbd',type:'keyboard',capabilities:{keyboard:true}}]}); "
            "const display=graph.outputs[0].id; const keyboard=graph.nodes.find(row=>row.category==='keyboard').id; "
            "let store=H.emptyStore(); const saved=H.saveTopologyMatch(store,{setupId:'desk',devices:[keyboard],outputs:[display],confidence:'confirmed'}); store=saved.store; store=H.setMatchPolicy(store,{mode:'auto-apply'}).store; "
            "const resolved=H.resolveSetup(graph,store,{mode:'tablet'}); const partial=H.matchTopology(G.fromSnapshot({monitors:[],devices:[{id:'kbd',type:'keyboard',capabilities:{keyboard:true}}]}),store); "
            "const custom=H.normalizeSetupProfile({id:'custom',preferredAdaptiveProfile:'gaming',dockTarget:'primary-display',inputMappings:{[keyboard]:display},deviceBehavior:{[keyboard]:{ignored:true}}}); "
            "console.log(JSON.stringify({ids:H.SETUP_IDS,resolved,partial,custom}));"
        )
        self.assertIn("portable", result["ids"])
        self.assertIn("custom", result["ids"])
        self.assertEqual(result["resolved"]["selected"], "desk")
        self.assertEqual(result["resolved"]["source"], "topology-match")
        self.assertEqual(result["resolved"]["profile"]["preferredAdaptiveProfile"], "desktop")
        self.assertEqual(result["partial"]["status"], "partial")
        self.assertFalse(result["partial"]["complete"])
        self.assertEqual(result["custom"]["preferredAdaptiveProfile"], "gaming")
        self.assertEqual(len(result["custom"]["inputMappings"]), 1)
        self.assertTrue(next(iter(result["custom"]["inputMappings"].values())).startswith("display:"))
        self.assertTrue(next(iter(result["custom"]["deviceBehavior"].values()))["ignored"])

    def test_topology_match_preserves_explicit_zero_minimums(self) -> None:
        result = self.run_node(
            "const H=require('./shell/models/HardwarePolicies.js'); "
            "const match=H.normalizeTopologyMatch({setupId:'portable',devices:['device:keyboard:0123456789abcdef'],outputs:['display:0123456789abcdef'],minimumDevices:0,minimumOutputs:0}); "
            "console.log(JSON.stringify(match));"
        )
        self.assertEqual(result["minimumDevices"], 0)
        self.assertEqual(result["minimumOutputs"], 0)

    def test_power_policy_keeps_multiple_real_sources_without_fabrication(self) -> None:
        result = self.run_node(
            "const H=require('./shell/models/HardwarePolicies.js'); "
            "const multi=H.normalizePowerState({powerProfileAvailable:true,powerProfile:'balanced',batterySources:["
            "{id:'device:battery:0123456789abcdef',label:'System battery',role:'system',percent:75,state:'discharging'},"
            "{id:'device:battery:fedcba9876543210',label:'Attached battery',role:'peripheral',percent:60,state:'discharging'}]}); "
            "const empty=H.normalizePowerState({powerProfileAvailable:true,powerProfile:'balanced',batterySources:[]}); "
            "console.log(JSON.stringify({multi,empty,decision:H.powerDecision({powerProfileAvailable:true,powerProfile:'power-saver',batterySources:multi.batterySources},{powerPolicy:'performance'},{disablePerformanceOnBattery:true,criticalBatteryPercent:15})}));"
        )
        self.assertEqual(len(result["multi"]["batterySources"]), 2)
        self.assertEqual(result["multi"]["batteryPercent"], 75)
        self.assertEqual(result["multi"]["batterySources"][1]["role"], "peripheral")
        self.assertFalse(result["empty"]["batteryAvailable"])
        self.assertEqual(result["decision"]["batterySourceCount"], 2)
        self.assertTrue(result["decision"]["consentRequired"])


if __name__ == "__main__":
    unittest.main()
