from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class AdaptiveStateTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_registry_separates_master_state_from_user_preferences(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const F=require('./shell/models/FeatureState.js'); "
            "const config=C.defaults(); const context={config,profile:'auto',masterEnabled:false,suspended:false,"
            "capabilities:{touchscreen:true,touchpad:true,stylus:true,rotation:true,osk:true,textInput:true,effects:true}}; "
            "const snap=F.state(context,'snap-assist'); console.log(JSON.stringify({snap,summary:F.summary(context)}));"
        )
        snap = result["snap"]
        self.assertTrue(snap["userEnabled"])
        self.assertFalse(snap["effectiveEnabled"])
        self.assertEqual(snap["disabledReason"], "Omanome master toggle is off")
        self.assertTrue(snap["temporarilySuppressed"])
        self.assertEqual(snap["overrideSource"], "safety")
        self.assertFalse(result["summary"]["partial"])

    def test_suspend_is_distinct_from_safe_mode_and_master_off(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const F=require('./shell/models/FeatureState.js'); "
            "const config=C.defaults(); const caps={touchscreen:true,touchpad:true,stylus:true,rotation:true,osk:true,textInput:true,effects:true}; "
            "console.log(JSON.stringify({suspend:F.state({config,capabilities:caps,suspended:true},'gestures'),"
            "safe:F.state({config,capabilities:caps,safeMode:true},'gestures'),off:F.state({config,capabilities:caps,masterEnabled:false},'gestures')}));"
        )
        self.assertEqual(result["suspend"]["disabledReason"], "Omanome is suspended")
        self.assertEqual(result["safe"]["disabledReason"], "Safe Mode")
        self.assertEqual(result["off"]["disabledReason"], "Omanome master toggle is off")

    def test_unavailable_features_are_not_toggleable(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const F=require('./shell/models/FeatureState.js'); "
            "const config=C.defaults(); const context={config,capabilities:{touchscreen:false,touchpad:false,stylus:false,rotation:false,osk:false,textInput:false,effects:false}}; "
            "const ids=['touch-mode','gestures','stylus','rotation','osk','effects']; "
            "console.log(JSON.stringify(ids.map(id=>{const row=F.state(context,id); return {id,available:row.available,can:F.canToggle(row),reason:row.disabledReason}})));"
        )
        for row in result:
            self.assertFalse(row["available"], row["id"])
            self.assertFalse(row["can"], row["id"])
            self.assertTrue(row["reason"], row["id"])

    def test_profile_override_does_not_change_user_setting(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const F=require('./shell/models/FeatureState.js'); "
            "const config=C.defaults(); const caps={touchscreen:true,touchpad:true,stylus:true,rotation:true,osk:true,textInput:true,effects:true}; "
            "const gaming=F.state({config,profile:'gaming',capabilities:caps},'snap-assist'); "
            "const desktop=F.state({config,profile:'desktop',capabilities:caps},'snap-assist'); "
            "const customConfig=C.set(config,'adaptive.profiles.custom.featureOverrides.snap-assist',false); "
            "const custom=F.state({config:customConfig,profile:'custom',capabilities:caps},'snap-assist'); "
            "console.log(JSON.stringify({gaming,desktop,custom}));"
        )
        self.assertTrue(result["gaming"]["userEnabled"])
        self.assertFalse(result["gaming"]["effectiveEnabled"])
        self.assertEqual(result["gaming"]["disabledReason"], "Gaming profile")
        self.assertTrue(result["desktop"]["effectiveEnabled"])
        self.assertFalse(result["custom"]["effectiveEnabled"])

    def test_11_to_12_migration_preserves_existing_sections(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); "
            "const migrated=C.migrateDetailed({schemaVersion:2,general:{profile:'Tablet'},input:{nativeBackend:'native'},"
            "performance:{mode:'performance'},accessibility:{largeUi:true},multitasking:{snapAssist:{enabled:true}}}); "
            "console.log(JSON.stringify({applied:migrated.applied,adaptive:migrated.config.adaptive,controlCenter:migrated.config.controlCenter,"
            "native:migrated.config.input.nativeBackend,performance:migrated.config.performance.mode,largeUi:migrated.config.accessibility.largeUi,"
            "snap:migrated.config.multitasking.snapAssist.enabled}));"
        )
        self.assertIn("adaptive-1.2-defaults", result["applied"])
        self.assertEqual(result["adaptive"]["profile"], "tablet")
        self.assertEqual(result["controlCenter"]["widget"]["position"], "right")
        self.assertEqual(result["native"], "native")
        self.assertEqual(result["performance"], "performance")
        self.assertTrue(result["largeUi"])
        self.assertTrue(result["snap"])


if __name__ == "__main__":
    unittest.main()
