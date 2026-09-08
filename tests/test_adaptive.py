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

    def test_keyboard_lifecycle_debounces_flapping_and_keeps_multiple_keyboards_aggregate(self) -> None:
        result = self.run_node(
            "const K=require('./shell/models/KeyboardTransitions.js'); "
            "const config={adaptive:{profile:'auto',automaticTransitions:true,externalKeyboardPolicy:'hybrid',"
            "transition:{debounceMs:100,stabilityMs:200}}}; "
            "const key=(id,relation='detachable',transport='pogo-pin')=>({id,name:id,formFactorRelation:relation,"
            "classification:relation,transport,connected:true,capabilities:{normalKeyboard:true}}); "
            "let state=K.observe(K.emptyState(),[],config,{touchscreen:true},0).state; "
            "let pending=K.observe(state,[key('cover')],config,{touchscreen:true},1); "
            "let flapped=K.observe(pending.state,[],config,{touchscreen:true},50); "
            "let attach=K.observe(flapped.state,[key('cover')],config,{touchscreen:true},100); "
            "let settled=K.observe(attach.state,[key('cover')],config,{touchscreen:true},401); "
            "let two=K.observe(settled.state,[key('cover'),key('usb','external','usb')],config,{touchscreen:true},402); "
            "let twoSettled=K.observe(two.state,[key('cover'),key('usb','external','usb')],config,{touchscreen:true},703); "
            "let one=K.observe(twoSettled.state,[key('usb','external','usb')],config,{touchscreen:true},704); "
            "let oneSettled=K.observe(one.state,[key('usb','external','usb')],config,{touchscreen:true},1005); "
            "console.log(JSON.stringify({pending:K.summary(pending.state),flapped:K.summary(flapped.state),settled:K.summary(settled.state),two:K.summary(twoSettled.state),one:K.summary(one.state),oneSettled:K.summary(oneSettled.state)}));"
        )
        self.assertEqual(result["pending"]["phase"], "Connecting")
        self.assertTrue(result["pending"]["pending"])
        self.assertEqual(result["flapped"]["phase"], "Disconnected")
        self.assertFalse(result["flapped"]["pending"])
        self.assertEqual(result["settled"]["event"]["type"], "keyboard-attached")
        self.assertEqual(result["settled"]["connectedCount"], 1)
        self.assertEqual(result["two"]["connectedCount"], 2)
        self.assertEqual(result["one"]["phase"], "Disconnecting")
        self.assertEqual(result["one"]["connectedCount"], 1)
        self.assertEqual(result["one"]["externalCount"], 1)
        self.assertEqual(result["oneSettled"]["phase"], "Connected")
        self.assertTrue(result["oneSettled"]["stableConnected"])

    def test_keyboard_rules_and_external_policies_are_local_and_non_aggressive(self) -> None:
        result = self.run_node(
            "const K=require('./shell/models/KeyboardTransitions.js'); "
            "const device={id:'keyboard:transport-bluetooth/vendor-1/product-2',name:'Wireless',"
            "formFactorRelation:'external',classification:'external',transport:'bluetooth',connected:true,"
            "capabilities:{normalKeyboard:true}}; "
            "const ignored=K.resolve([device],{adaptive:{externalKeyboardPolicy:'desktop',deviceRules:[{id:device.id,ignore:true}]}},{}); "
            "const remembered=K.resolve([device],{adaptive:{externalKeyboardPolicy:'desktop',deviceRules:[{id:device.id,preferredProfile:'hybrid'}]}},{}); "
            "const hide=K.resolve([device],{adaptive:{externalKeyboardPolicy:'hide-osk'}},{}); "
            "const builtin=K.resolve([{...device,id:'builtin',formFactorRelation:'built-in',classification:'built-in',transport:'i2c'}],{adaptive:{externalKeyboardPolicy:'desktop'}},{}); "
            "console.log(JSON.stringify({ignored,remembered,hide,builtin,limited:K.rules({adaptive:{deviceRules:Array(200).fill({id:'x'})}}).length}));"
        )
        self.assertEqual(result["ignored"]["activeCount"], 0)
        self.assertEqual(result["ignored"]["ignoredCount"], 1)
        self.assertEqual(result["remembered"]["targetMode"], "hybrid")
        self.assertEqual(result["remembered"]["oskAction"], "preserve")
        self.assertEqual(result["hide"]["targetMode"], "")
        self.assertEqual(result["hide"]["oskAction"], "hide")
        self.assertEqual(result["builtin"]["targetMode"], "")
        self.assertEqual(result["limited"], 128)

    def test_keyboard_transition_wiring_preserves_safe_runtime_boundaries(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('"models/KeyboardTransitions.js" as KeyboardTransitionsModel', service)
        self.assertIn("KeyboardTransitionsModel.observe", service)
        self.assertIn("KeyboardTransitionsModel.noteEvent", service)
        self.assertIn("keyboardTransitionTimer", service)
        self.assertIn("keyboardModeSignals", service)
        self.assertIn("keyboardTransition: root.keyboardTransitionSummary()", service)
        self.assertIn("root.keyboardTransitionState.modeReady !== false", service)

    def test_docked_mode_requires_external_monitor_and_stable_keyboard_then_restores_auto(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const D=require('./shell/models/DockedMode.js'); const A=require('./shell/models/AdaptiveMode.js'); "
            "const config=C.defaults(); const internal={name:'eDP-1',builtin:true}; const external={name:'HDMI-A-1'}; "
            "const context={selectedProfile:'auto',adaptiveEnabled:true,automaticTransitions:true,autoMode:'tablet'}; "
            "let initial=D.observe(D.emptyState(),{monitors:[internal],physicalKeyboard:false,keyboardStable:true},config,context,0); "
            "let pending=D.observe(initial.state,{monitors:[internal,external],physicalKeyboard:true,keyboardCount:1,keyboardStable:true},config,context,500); "
            "let docked=D.observe(pending.state,{monitors:[internal,external],physicalKeyboard:true,keyboardCount:1,keyboardStable:true},config,context,941); "
            "let undocking=D.observe(docked.state,{monitors:[internal],physicalKeyboard:true,keyboardCount:1,keyboardStable:true},config,context,1500); "
            "let restored=D.observe(undocking.state,{monitors:[internal],physicalKeyboard:true,keyboardCount:1,keyboardStable:true},config,context,1941); "
            "const state=A.effective('auto',config,{baseMode:'tablet',signals:{touchscreen:true,physicalKeyboard:true,externalMonitor:true},dockedState:docked.state}); "
            "const manual=D.resolve({monitors:[internal,external],physicalKeyboard:true,keyboardCount:1,keyboardStable:true},config,{selectedProfile:'tablet',adaptiveEnabled:true,automaticTransitions:true}); "
            "console.log(JSON.stringify({pending:D.summary(pending.state),docked:D.summary(docked.state),undocking:D.summary(undocking.state),restored:D.summary(restored.state),effective:{mode:state.effectiveMode,policy:state.componentPolicy},manual}));"
        )
        self.assertTrue(result["pending"]["pending"])
        self.assertEqual(result["pending"]["phase"], "docking")
        self.assertTrue(result["docked"]["active"])
        self.assertEqual(result["docked"]["targetMode"], "desktop")
        self.assertEqual(result["docked"]["previousAutoMode"], "tablet")
        self.assertEqual(result["effective"]["mode"], "desktop")
        self.assertTrue(result["effective"]["policy"]["docked"])
        self.assertTrue(result["effective"]["policy"]["dockedKeepTouch"])
        self.assertEqual(result["effective"]["policy"]["osk"], "suppressed")
        self.assertTrue(result["undocking"]["pending"])
        self.assertFalse(result["restored"]["active"])
        self.assertEqual(result["restored"]["restoredMode"], "tablet")
        self.assertTrue(result["manual"]["suppressed"])
        self.assertFalse(result["manual"]["active"])

    def test_docked_mode_monitor_detection_is_conservative_and_profile_policies_are_component_scoped(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const D=require('./shell/models/DockedMode.js'); const A=require('./shell/models/AdaptiveMode.js'); "
            "const config=C.set(C.defaults(),'adaptive.profiles.tablet.componentBehavior',{quickSettings:'compact',windowControls:'always',touchTargetSize:60,osk:{mode:'manual',autoShow:false}}); "
            "const policy=A.effective('tablet',config,{baseMode:'tablet'}).componentPolicy; "
            "console.log(JSON.stringify({one:D.inventory([{name:'eDP-1',builtin:true}]),two:D.inventory([{name:'eDP-1',builtin:true},{name:'HDMI-A-1'}]),unknown:D.inventory([{name:'panel-a'},{name:'panel-b'}]),policy}));"
        )
        self.assertFalse(result["one"]["externalMonitor"])
        self.assertEqual(result["two"]["externalMonitorCount"], 1)
        self.assertTrue(result["two"]["externalMonitor"])
        self.assertFalse(result["unknown"]["externalMonitor"])
        self.assertEqual(result["policy"]["quickSettings"], "compact")
        self.assertEqual(result["policy"]["windowControls"], "always")
        self.assertEqual(result["policy"]["touchTargetSize"], 60)
        self.assertEqual(result["policy"]["osk"], "manual")

    def test_docked_mode_service_status_is_runtime_only_and_not_a_window_layout_trigger(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        model = (ROOT / "shell/models/DockedMode.js").read_text(encoding="utf-8")
        self.assertIn('"models/DockedMode.js" as DockedModeModel', service)
        self.assertIn("DockedModeModel.observe", service)
        self.assertIn("DockedModeModel.inventory", service)
        self.assertIn("dockedModeTimer", service)
        self.assertIn("dockedMode: root.dockedModeSummary()", service)
        self.assertIn("never returned by the summary API", model)
        self.assertNotIn("hyprctl", model)
        self.assertNotIn("config.write", model)

    def test_adaptive_settings_profiles_reset_preview_and_feature_overrides(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const S=require('./shell/models/AdaptiveSettings.js'); "
            "const A=require('./shell/models/AdaptiveMode.js'); const F=require('./shell/models/FeatureState.js'); "
            "let config=C.set(C.defaults(),'adaptive.profiles.tablet.componentBehavior',{dock:'desktop',touchControls:'always',touchTargetSize:60}); "
            "config=C.set(config,'adaptive.profiles.tablet.featureOverrides.gestures',false); "
            "const cards=S.profiles(config,'tablet'); const detail=S.profile(config,'tablet'); "
            "const reset=S.reset(config,'tablet'); let preview=S.beginPreview(S.emptyPreviewState(),'tablet',1000,6000); "
            "const active=S.previewSummary(preview,1200); const expired=S.previewSummary(preview,8000); "
            "const policy=A.preview('tablet',config,{activeProfile:'auto',baseMode:'desktop',currentMode:'desktop',signals:{touchscreen:true}}); "
            "const feature=F.state({config,profile:'tablet',capabilities:{touchscreen:true,touchpad:true,stylus:false,rotation:true,osk:true,textInput:true,effects:true}},'gestures'); "
            "console.log(JSON.stringify({ids:cards.map(row=>row.id),card:cards[2],detail,reset:S.profile(reset,'tablet'),active,expired,preview:{mode:policy.effectiveMode,profile:policy.previewProfile,component:policy.componentPolicy},feature}));"
        )
        self.assertEqual(result["ids"], ["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"])
        self.assertTrue(result["card"]["configured"])
        self.assertEqual(result["detail"]["componentBehavior"]["dock"], "desktop")
        self.assertFalse(result["feature"]["effectiveEnabled"])
        self.assertEqual(result["feature"]["overrideSource"], "profile")
        self.assertEqual(result["reset"]["componentBehavior"], {})
        self.assertEqual(result["reset"]["featureOverrides"], {})
        self.assertTrue(result["active"]["active"])
        self.assertFalse(result["expired"]["active"])
        self.assertEqual(result["preview"]["mode"], "desktop")
        self.assertEqual(result["preview"]["profile"], "tablet")
        self.assertEqual(result["preview"]["component"]["mode"], "tablet")
        self.assertEqual(result["preview"]["component"]["touchTargetSize"], 60)

    def test_adaptive_settings_ui_has_explicit_sections_and_runtime_preview_boundary(self) -> None:
        settings = (ROOT / "shell/views/Settings.qml").read_text(encoding="utf-8")
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        model = (ROOT / "shell/models/AdaptiveSettings.js").read_text(encoding="utf-8")
        for section in ("adaptiveMode", "physicalKeyboards", "deviceRules", "modeTransitions", "profiles", "componentBehavior", "dockedMode", "adaptiveNotifications", "adaptiveAdvanced"):
            self.assertIn(section, settings)
        for marker in ("controlCenter.widget.position", "resetAdaptiveProfile", "beginAdaptivePreview", "cancelAdaptivePreview", "adaptivePreviewTimer", "AdaptiveModeModel.preview", "adaptivePreview: root.adaptivePreviewSummary()"):
            self.assertIn(marker, service if "AdaptiveMode" in marker or "Preview" in marker or "adaptivePreview" in marker else settings)
        self.assertIn("profileDefaults", model)
        self.assertIn("temporary profile preview", model)
        self.assertIn("profileFeatures", settings)

    def test_mode_transition_coordinator_reverses_without_frame_ipc(self) -> None:
        result = self.run_node(
            "const M=require('./shell/models/ModeTransitionCoordinator.js'); "
            "const config={adaptive:{transition:{enabled:true,durationMs:260}},animations:{enabled:true}}; "
            "let first=M.begin(M.emptyState(),'tablet','desktop','keyboard-attached',0,config,{}); "
            "let middle=M.tick(first.state,100); "
            "let reversed=M.begin(middle.state,'desktop','tablet','keyboard-detached',100,config,{}); "
            "let end=M.tick(reversed.state,360); "
            "const reduced=M.begin(M.emptyState(),'desktop','tablet','reduced-motion',0,config,{reducedMotion:true}); "
            "const components=M.allComponents(end.state,{quickSettings:'large',windowControls:'always'},['dock','quick-settings','window-controls']); "
            "console.log(JSON.stringify({first:M.summary(first.state),middle:M.summary(middle.state),reversed:M.summary(reversed.state),end:M.summary(end.state),reduced:M.summary(reduced.state),components}));"
        )
        self.assertEqual(result["first"]["phase"], "running")
        self.assertGreater(result["middle"]["progress"], 0)
        self.assertTrue(result["reversed"]["interrupted"])
        self.assertEqual(result["reversed"]["fromMode"], "desktop")
        self.assertEqual(result["reversed"]["toMode"], "tablet")
        self.assertEqual(result["end"]["phase"], "completed")
        self.assertEqual(result["end"]["progress"], 1)
        self.assertEqual(result["reduced"]["durationMs"], 1)
        self.assertFalse(result["reduced"]["active"])
        self.assertEqual([row["component"] for row in result["components"]], ["dock", "quick-settings", "window-controls"])
        self.assertTrue(all("fromMode" in row and "toMode" in row and "reason" in row for row in result["components"]))

    def test_mode_transition_service_is_local_and_accessible_to_components(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        tokens = (ROOT / "shell/components/DesignTokens.qml").read_text(encoding="utf-8")
        self.assertIn('"models/ModeTransitionCoordinator.js" as ModeTransitionModel', service)
        self.assertIn("ModeTransitionModel.begin", service)
        self.assertIn("ModeTransitionModel.tick", service)
        self.assertIn("ModeTransitionModel.componentState", service)
        self.assertIn("modeTransitionTimer", service)
        self.assertIn("no compositor IPC", service)
        self.assertIn("componentTransition", service)
        self.assertIn("transitionComponent", tokens)


if __name__ == "__main__":
    unittest.main()
