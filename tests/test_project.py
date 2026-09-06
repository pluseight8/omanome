from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class OmanomeProjectTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_github_install_contract_is_explicit(self) -> None:
        url = "https://github.com/pluseight8/omanome.git"
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        readme_ru = (ROOT / "README.ru.md").read_text(encoding="utf-8")
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertIn(url, readme)
        self.assertIn(url, readme_ru)
        self.assertIn(url, cli)
        self.assertNotIn("<repo-url>", readme + readme_ru + cli)
        self.assertIn("install) install_cmd", cli)

    def test_manifest_preserves_the_standard_bar(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["version"], "0.4.0")
        self.assertNotIn("bar", manifest["kinds"])
        self.assertEqual(set(manifest["entryPoints"]), {"service", "barWidget", "panel"})
        for entry in manifest["entryPoints"].values():
            self.assertTrue((ROOT / entry).is_file(), entry)

    def test_config_is_versioned_and_has_core_sections(self) -> None:
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertEqual(defaults["schemaVersion"], 1)
        self.assertEqual(schema["properties"]["schemaVersion"]["const"], 1)
        for key in ("tabletMode", "touch", "stylus", "keyboard", "clipboard", "updates", "animations", "performance", "applicationRules", "wobbly", "cube", "forceQuit"):
            self.assertIn(key, defaults)
        self.assertEqual(defaults["dock"]["mode"], "floating")
        self.assertIn("favoritesFirst", defaults["launcher"])
        self.assertEqual(defaults["overview"]["workspaceMode"], "dynamic")

    def test_favorites_persistence_and_dock_config_helpers(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const D=require('./shell/models/Dock.js'); "
            "const base=C.defaults(); const next=C.set(base,'launcher.favorites',['org.gnome.Nautilus','firefox']); "
            "console.log(JSON.stringify({favorites:C.get(next,'launcher.favorites',[]),dock:D.config(next),order:D.reorder(['a','b','c'],'c',0)}));"
        )
        self.assertEqual(result["favorites"], ["org.gnome.Nautilus", "firefox"])
        self.assertEqual(result["dock"]["mode"], "floating")
        self.assertEqual(result["order"], ["c", "a", "b"])

    def test_workspace_movement_helper_uses_real_dispatch_commands(self) -> None:
        result = self.run_node(
            "const W=require('./shell/models/Workspaces.js'); "
            "console.log(JSON.stringify({dynamic:W.ids([{id:1,windows:[1]},{id:2,windows:[1]},{id:3,windows:[]},{id:4,windows:[]}],'dynamic',5), "
            "fixed:W.ids([{id:1}],'fixed',3), focus:W.focusCommand(4), move:W.moveCommand(4), adjacent:W.adjacent(2,'right',[1,2,3])}));"
        )
        self.assertEqual(result["dynamic"], [1, 2, 3])
        self.assertEqual(result["fixed"], [1, 2, 3])
        self.assertEqual(result["focus"], "workspace 4")
        self.assertEqual(result["move"], "movetoworkspace 4")
        self.assertEqual(result["adjacent"], 3)

    def test_quick_settings_and_stylus_are_capability_aware(self) -> None:
        result = self.run_node(
            "const Q=require('./shell/models/QuickSettings.js'); const S=require('./shell/models/Stylus.js'); "
            "console.log(JSON.stringify({state:Q.stateFromSystem({wifiEnabled:true,bluetoothPowered:false,volumeMuted:true,nightLightEnabled:true,powerProfile:'balanced'}), "
            "cycle:Q.cyclePowerProfile('balanced'), touch:S.isTouchscreen({type:'touchpad',name:'Touchpad'}), "
            "stylus:S.classify([{name:'Generic Linux Tablet Pen',type:'tablet',pressure:true,tiltX:true,buttons:2}])[0].capabilities}));"
        )
        self.assertTrue(result["state"]["wifi"])
        self.assertFalse(result["state"]["volume"])
        self.assertTrue(result["state"]["nightLight"])
        self.assertEqual(result["cycle"], "performance")
        self.assertFalse(result["touch"])
        self.assertTrue(result["stylus"]["pressure"])
        self.assertTrue(result["stylus"]["tilt"])
        self.assertTrue(result["stylus"]["barrelButtons"])

    def test_stylus_fixtures_use_types_and_capabilities_not_vendor_names(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/Stylus.js'); const F=require('./tests/fixtures/stylus-devices.json'); "
            "const list=Object.keys(F).map(k=>F[k]); const classified=S.classify(list,'fixture'); "
            "console.log(JSON.stringify({count:classified.length, names:classified.map(x=>x.name), "
            "pressure:classified.filter(x=>x.capabilities.pressure).length, "
            "eraser:classified.filter(x=>x.capabilities.eraser).length, "
            "serial:classified.filter(x=>x.capabilities.serial !== '').length, "
            "touch:S.isTouchscreen(F.touchscreen), pad:S.isTabletPad({type:'tablet-pad'}), "
            "keyboard:S.classifyKeyboards([{name:'external-keyboard'},{name:'consumer-control',main:true},{name:'tablet-tool',type:'tablet-tool'}]).length}));"
        )
        self.assertEqual(result["count"], 6)
        self.assertEqual(result["pressure"], 5)
        self.assertEqual(result["eraser"], 1)
        self.assertEqual(result["serial"], 2)
        self.assertTrue(result["touch"])
        self.assertTrue(result["pad"])
        self.assertEqual(result["keyboard"], 1)
        stylus_source = (ROOT / "shell/models/Stylus.js").read_text(encoding="utf-8").lower()
        self.assertNotIn("wacom", stylus_source)
        self.assertNotIn('name.indexof("pen")', stylus_source)

    def test_osk_has_modifiers_and_real_key_layers(self) -> None:
        result = self.run_node(
            "const O=require('./shell/models/Osk.js'); const rows=O.rows('en',true); "
            "console.log(JSON.stringify({caps:rows[3].includes('Caps'),numeric:O.rows('numeric',true)[0],"
            "control:O.isControl('Control'),alt:O.isControl('Alt'),space:O.isControl('Space')}));"
        )
        self.assertTrue(result["caps"])
        self.assertEqual(result["numeric"][0], "1")
        self.assertTrue(result["control"])
        self.assertTrue(result["alt"])
        self.assertTrue(result["space"])

    def test_osk_0_3_layouts_and_touch_features_are_data_driven(self) -> None:
        result = self.run_node(
            "const O=require('./shell/models/Osk.js'); "
            "console.log(JSON.stringify({modes:O.modes, profile:O.modeProfile('one_handed_left'), "
            "symbols:O.rows('symbols',false)[1], split:O.splitRows('en',false)[0], "
            "editing:O.editingRows()[1], emoji:O.emojiItems('smileys','smileys').length, "
            "alternates:O.alternateKeys('e','en'), repeat:O.isRepeatable('Backspace'), "
            "action:O.keyAction('SelectAll'), toolbar:O.toolbarItems()}));"
        )
        self.assertIn("one-handed-left", result["modes"])
        self.assertEqual(result["profile"]["anchor"], "left")
        self.assertIn("€", result["symbols"])
        self.assertEqual(result["split"]["left"][0], "q")
        self.assertIn("Copy", result["editing"])
        self.assertGreater(result["emoji"], 0)
        self.assertIn("é", result["alternates"])
        self.assertTrue(result["repeat"])
        self.assertEqual(result["action"], "select-all")
        self.assertIn("clipboard", result["toolbar"])

    def test_keyboard_config_contains_real_0_3_controls(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const K=C.defaults().keyboard; "
            "console.log(JSON.stringify(K));"
        )
        self.assertTrue(result["toolbar"])
        self.assertTrue(result["keyPopup"])
        self.assertTrue(result["spaceCursor"])
        self.assertEqual(result["floating"]["width"], 0.82)
        self.assertEqual(result["split"]["gap"], 24)

    def test_stylus_button_map_is_generic_and_validated(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/Stylus.js'); "
            "console.log(JSON.stringify(S.normalizeButtonMap({primary:'annotation',secondary:'not-a-real-action'})));"
        )
        self.assertEqual(result["primary"], "annotation")
        self.assertEqual(result["secondary"], "right-click")
        self.assertIn("annotation", self.run_node("const S=require('./shell/models/Stylus.js'); console.log(JSON.stringify(S.buttonActions));"))

    def test_config_migrations_keep_old_user_intent(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); "
            "console.log(JSON.stringify(C.load(JSON.stringify({tablet:{touchTarget:60},osk:{mode:'split'},launcher:{favorites:['demo']}}))));"
        )
        self.assertEqual(result["schemaVersion"], 1)
        self.assertEqual(result["tabletMode"]["touchTarget"], 60)
        self.assertEqual(result["keyboard"]["mode"], "split")
        self.assertEqual(result["launcher"]["favorites"], ["demo"])

    def test_repository_does_not_use_x11_or_second_shell(self) -> None:
        code_suffixes = {".qml", ".js", ".sh", ".py", ".json"}
        text = "\n".join(
            path.read_text(encoding="utf-8", errors="ignore")
            for path in ROOT.rglob("*")
            if path.is_file() and path != ROOT / "tests/test_project.py" and path.suffix in code_suffixes and "work" not in path.parts
        ).lower()
        self.assertNotIn("xdotool", text)
        self.assertNotIn("gnome-shell --replace", text)
        self.assertNotIn('"bar"', (ROOT / "manifest.json").read_text(encoding="utf-8"))

    def test_shell_scripts_parse(self) -> None:
        for script in (
            ROOT / "cli/omanome",
            ROOT / "input/clipboard-capture.sh",
            ROOT / "input/system-state.sh",
            ROOT / "input/wifi-scan.sh",
            ROOT / "input/bluetooth-scan.sh",
            ROOT / "input/rotation-monitor.sh",
            ROOT / "input/sensor-info.sh",
            ROOT / "input/audio-devices.sh",
        ):
            result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_system_state_probe_is_json_and_marks_unavailable_backends(self) -> None:
        jq = shutil.which("jq")
        if not jq:
            self.skipTest("jq is not installed")
        result = subprocess.run(
            [str(ROOT / "input/system-state.sh")], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(result.stdout)
        for key in ("wifiAvailable", "volumeAvailable", "recordingAvailable", "rotationAvailable"):
            self.assertIn(key, state)
            self.assertIsInstance(state[key], bool)
        for key in ("rotationSensorAvailable", "rotationDbusAvailable", "rotationAccelerometerAvailable"):
            self.assertIn(key, state)
            self.assertIsInstance(state[key], bool)
        self.assertIn(state["rotationSensorBackend"], ("manual", "monitor-sensor", "dbus-iio"))
        for key in ("touchTransform", "tabletTransform"):
            self.assertIn(key, state)
            self.assertIsInstance(state[key], int)

    def test_sensor_and_touch_diagnostics_contracts(self) -> None:
        sensor = subprocess.run([str(ROOT / "input/sensor-info.sh")], capture_output=True, text=True)
        self.assertEqual(sensor.returncode, 0, sensor.stderr)
        payload = json.loads(sensor.stdout)
        for key in ("monitorSensorAvailable", "dbusAvailable", "accelerometerAvailable", "autoRotationSupported"):
            self.assertIn(key, payload)
            self.assertIsInstance(payload[key], bool)
        self.assertIn(payload["selectedBackend"], ("manual", "monitor-sensor", "dbus-iio"))
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertIn("touch-info", cli)
        self.assertIn("sensor-info", cli)

    def test_companion_contract_is_optional_and_version_aware(self) -> None:
        companion = ROOT / "hypr/omanome-hypr"
        source = (companion / "omanome-hypr.cpp").read_text(encoding="utf-8")
        metadata = json.loads((companion / "compatibility.json").read_text(encoding="utf-8"))
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertEqual(metadata["protocolVersion"], 1)
        self.assertEqual(metadata["pluginVersion"], "0.4.0")
        self.assertIn("__hyprland_api_get_hash", source)
        self.assertIn("__hyprland_api_get_client_hash", source)
        self.assertIn("HyprlandAPI::getHyprlandVersion", source)
        self.assertIn("companion_doctor_cmd", cli)
        self.assertIn("companion_enable_cmd", cli)
        self.assertNotIn("sudo pacman", cli)
        self.assertNotIn("LD_PRELOAD", source)

        result = self.run_node(
            "const C=require('./shell/models/Companion.js'); "
            "const good={installed:true,built:true,loaded:true,protocolVersion:1,pluginVersion:'0.4.0'," \
            "runtime:{abi:'same'},build:{abi:'same'},compatibility:{pluginVersion:'0.4.0'}," \
            "capabilities:{desktopCube:true}}; " \
            "const bad={...good,runtime:{abi:'new'},build:{abi:'old'}}; " \
            "console.log(JSON.stringify({good:C.normalize(good),bad:C.normalize(bad),cube:C.effectAvailable(good,'desktopCube')}));"
        )
        self.assertTrue(result["good"]["compatible"])
        self.assertFalse(result["bad"]["compatible"])
        self.assertTrue(result["cube"])

    def test_effects_animation_and_rules_are_adaptive_without_fake_backends(self) -> None:
        result = self.run_node(
            "const E=require('./shell/models/Effects.js'); const A=require('./shell/models/Animations.js'); "
            "const P=require('./shell/models/Performance.js'); const R=require('./shell/models/AppRules.js'); "
            "const blur=E.effectiveBlur({enabled:true,quality:'quality',highGpuThreshold:0.85,defaults:{},surfaces:{}},'dock',{batterySaver:true,backendAvailable:true}); "
            "const rule=R.decision([{id:'game',appId:'steam',fullscreen:true,disableBlur:true,disableWobbly:true}],{appId:'steam',fullscreen:1},{inputKind:'touch'}); "
            "const motion=A.transition({enabled:true,preset:'Smooth'},180,true); "
            "const performance=P.snapshot({qualityPreset:'balanced',adaptiveQuality:true,highGpuThreshold:0.85},{gpuLoad:0.92}); "
            "const caps=E.capabilityState({desktopCube:false},{desktopCube:true,desktopCubeBackend:'omarchy-desktop-cube'}); "
            "console.log(JSON.stringify({blur,rule,motion,performance,caps}));"
        )
        self.assertEqual(result["blur"]["quality"], "battery-saver")
        self.assertEqual(result["blur"]["passes"], 0)
        self.assertIn("game", result["rule"]["matched"])
        self.assertTrue(result["rule"]["disableBlur"])
        self.assertTrue(result["motion"]["duration"] <= 80)
        self.assertEqual(result["performance"]["quality"], "performance")
        self.assertEqual(result["caps"]["desktopCubeBackend"], "omarchy-desktop-cube")

    def test_touch_policy_separates_fullscreen_conflicts_and_target_sizes(self) -> None:
        result = self.run_node(
            "const T=require('./shell/models/Touch.js'); const config={enabled:true,disableOnFullscreen:true,conflictPolicy:'disable-fullscreen',fullscreenAllowList:[]}; "
            "const full=[{class:'demo-game',fullscreen:1}]; const allowed=[{class:'demo-game',fullscreen:1}]; "
            "allowed[0].class='allowed-app'; config.fullscreenAllowList=['allowed-*']; "
            "console.log(JSON.stringify({disabled:T.shouldDisableWorkspaceSwipe(full,{disableOnFullscreen:true,fullscreenAllowList:[]}), "
            "allowed:T.shouldDisableWorkspaceSwipe(allowed,config),mouse:T.targetSize({touchTarget:52},'mouse'), "
            "touch:T.targetSize({touchTarget:52},'touch'),large:T.targetSize({touchTarget:52,largeUi:true},'touch'), "
            "stylus:T.targetSize({touchTarget:52},'stylus'),enabled:T.workspaceSwipeEnabled(config,[])}));"
        )
        self.assertTrue(result["disabled"])
        self.assertFalse(result["allowed"])
        self.assertEqual(result["mouse"], 40)
        self.assertEqual(result["touch"], 52)
        self.assertEqual(result["large"], 64)
        self.assertEqual(result["stylus"], 52)
        self.assertTrue(result["enabled"])

    def test_rotation_is_dynamic_and_uses_atomic_batch(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('"hyprctl", "--batch"', service)
        self.assertIn("rotationTargetMonitors", service)
        self.assertIn("rotationRollbackBatch", service)
        for output in ("eDP-1", "DP-1", "HDMI-A-1"):
            self.assertNotIn(output, service)

    def test_uninstall_is_scoped_to_omanome_paths(self) -> None:
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertIn('omarchy plugin remove "$plugin_id"', cli)
        self.assertIn('rm -rf -- "$omanome_state_dir" "$omanome_cache_dir"', cli)
        self.assertNotIn('rm -rf -- "$config_home/omarchy"', cli)
        self.assertNotIn('rm -rf -- "$OMARCHY_PATH"', cli)

    def test_clipboard_capture_redacts_sensitive_state(self) -> None:
        capture = ROOT / "input/clipboard-capture.sh"
        with tempfile.TemporaryDirectory() as temp:
            env = os.environ.copy()
            env["XDG_STATE_HOME"] = temp
            normal = subprocess.run(
                [str(capture), "text"], input="hello\n", text=True, capture_output=True, env=env
            )
            self.assertEqual(normal.returncode, 0, normal.stderr)
            self.assertEqual(json.loads(normal.stdout)["text"], "hello")

            env["CLIPBOARD_STATE"] = "sensitive"
            sensitive = subprocess.run(
                [str(capture), "text"], input="secret", text=True, capture_output=True, env=env
            )
            self.assertEqual(sensitive.returncode, 0, sensitive.stderr)
            self.assertEqual(sensitive.stdout, "")

    def test_native_omarchy_validator_when_available(self) -> None:
        omarchy = shutil.which("omarchy")
        if not omarchy:
            self.skipTest("omarchy is not installed")
        result = subprocess.run(
            [omarchy, "plugin", "validate", str(ROOT)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
