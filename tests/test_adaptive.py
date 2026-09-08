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

    def test_profiles_keep_selected_source_and_effective_modes_separate(self) -> None:
        result = self.run_node(
            "const A=require('./shell/models/AdaptiveMode.js'); "
            "const auto=A.effective('auto',{}, {signals:{touchscreen:true,physicalKeyboard:false,lastInput:'touch'}}); "
            "const desktop=A.effective('desktop',{}, {baseMode:'tablet'}); "
            "const presentation=A.effective('presentation',{}, {baseMode:'tablet'}); "
            "const paused=A.effective('auto',{adaptive:{enabled:true,automaticTransitions:false}}, {baseMode:'tablet',currentMode:'desktop'}); "
            "console.log(JSON.stringify({profiles:A.profiles().map(row=>row.id),auto,desktop,presentation,paused}));"
        )
        self.assertEqual(result["profiles"], ["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"])
        self.assertEqual(result["auto"]["sourceMode"], "tablet")
        self.assertEqual(result["auto"]["effectiveMode"], "tablet")
        self.assertEqual(result["desktop"]["sourceMode"], "tablet")
        self.assertEqual(result["desktop"]["effectiveMode"], "desktop")
        self.assertEqual(result["presentation"]["effectiveMode"], "tablet")
        self.assertEqual(result["presentation"]["componentPolicy"]["gestures"], "disabled")
        self.assertFalse(result["presentation"]["componentPolicy"]["notificationPopups"])
        self.assertEqual(result["paused"]["effectiveMode"], "desktop")
        self.assertFalse(result["paused"]["automatic"])

    def test_custom_profile_changes_component_policy_without_mutating_config(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const A=require('./shell/models/AdaptiveMode.js'); "
            "const config=C.defaults(); const before=JSON.stringify(config); "
            "const custom=C.set(config,'adaptive.profiles.custom.componentBehavior',{mode:'tablet',osk:'auto',dock:'tablet',gestures:'enabled',windowControls:'always',touchTargetSize:60,animationPreset:'playful'}); "
            "const state=A.effective('custom',custom,{baseMode:'desktop'}); "
            "console.log(JSON.stringify({same:before===JSON.stringify(config),profile:state.profile,mode:state.effectiveMode,policy:state.componentPolicy,adaptive:custom.adaptive.profiles.custom}));"
        )
        self.assertTrue(result["same"])
        self.assertEqual(result["profile"], "custom")
        self.assertEqual(result["mode"], "tablet")
        self.assertEqual(result["policy"]["touchTargetSize"], 60)
        self.assertEqual(result["policy"]["osk"], "auto")
        self.assertEqual(result["policy"]["windowControls"], "always")
        self.assertEqual(result["policy"]["animationPreset"], "playful")

    def test_service_and_surfaces_use_effective_adaptive_mode(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        tokens = (ROOT / "shell/components/DesignTokens.qml").read_text(encoding="utf-8")
        control_center = (ROOT / "shell/views/ControlCenter.qml").read_text(encoding="utf-8")
        settings = (ROOT / "shell/views/Settings.qml").read_text(encoding="utf-8")
        widget = (ROOT / "shell/BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn('"models/AdaptiveMode.js" as AdaptiveModeModel', service)
        self.assertIn("AdaptiveModeModel.effective", service)
        self.assertIn("property string effectiveMode", service)
        self.assertIn("effectiveMode: root.effectiveMode", service)
        self.assertIn("service.effectiveMode", tokens)
        self.assertIn("service.adaptiveProfiles()", control_center)
        self.assertIn("setAdaptiveProfile(modelData.id)", settings)
        self.assertIn("service.effectiveMode", widget)


if __name__ == "__main__":
    unittest.main()
