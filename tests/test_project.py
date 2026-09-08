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
        self.assertEqual(manifest["version"], "1.0.0")
        self.assertNotIn("bar", manifest["kinds"])
        self.assertEqual(set(manifest["entryPoints"]), {"service", "barWidget", "panel"})
        for entry in manifest["entryPoints"].values():
            self.assertTrue((ROOT / entry).is_file(), entry)

    def test_10_release_and_performance_contract_are_documented(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        readme_ru = (ROOT / "README.ru.md").read_text(encoding="utf-8")
        performance = (ROOT / "docs/PERFORMANCE.md").read_text(encoding="utf-8")
        release = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("runnable 1.0.0 release", readme)
        self.assertIn("версии 1.0.0", readme_ru)
        self.assertIn("ownerCpuPercent", performance)
        self.assertIn("systemCpuPercent", performance)
        self.assertIn("notify-only", performance)
        self.assertIn("refs/tags/${TAG_VERSION}", release)
        self.assertNotIn("0.7.0", release)

    def test_i18n_locales_have_equal_key_sets(self) -> None:
        result = self.run_node(
            "const fs=require('fs'); const vm=require('vm'); const context={console}; "
            "vm.runInNewContext(fs.readFileSync('shell/models/I18n.js','utf8')+"
            "'; console.log(JSON.stringify({en:Object.keys(en).sort(),ru:Object.keys(ru).sort()}));', context);"
        )
        self.assertEqual(result["en"], result["ru"])

    def test_accessibility_contract_is_wired_to_shared_controls(self) -> None:
        action_button = (ROOT / "shell/components/ActionButton.qml").read_text(encoding="utf-8")
        settings = (ROOT / "shell/views/Settings.qml").read_text(encoding="utf-8")
        tokens = (ROOT / "shell/components/DesignTokens.qml").read_text(encoding="utf-8")
        self.assertIn("Accessible.name", action_button)
        self.assertIn("Accessible.description", action_button)
        self.assertIn("Accessible.role: Accessible.Button", action_button)
        self.assertIn("minimumHeight: 48", action_button)
        self.assertIn('accessibility.textScale', settings)
        self.assertIn('accessibility.highContrast', settings)
        self.assertIn('accessibility.reduceTransparency', settings)
        self.assertIn('accessibility.reducedMotion', settings)
        self.assertIn('accessibility.screenReaderHints', settings)
        self.assertIn('textScale: textScale', tokens)

    def test_config_is_versioned_and_has_core_sections(self) -> None:
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertEqual(defaults["schemaVersion"], 2)
        self.assertEqual(schema["properties"]["schemaVersion"]["const"], 2)
        for key in ("tabletMode", "input", "onboarding", "accessibility", "touch", "stylus", "keyboard", "clipboard", "updates", "recovery", "diagnostics", "animations", "performance", "applicationRules", "wobbly", "cube", "forceQuit"):
            self.assertIn(key, defaults)
        self.assertTrue(defaults["effects"]["enabled"])
        self.assertEqual(defaults["wobbly"]["maxVertices"], 1024)
        self.assertEqual(defaults["dock"]["mode"], "floating")
        self.assertIn("favoritesFirst", defaults["launcher"])
        self.assertEqual(defaults["overview"]["workspaceMode"], "dynamic")
        self.assertEqual(defaults["performance"]["mode"], "balanced")

    def test_tablet_mode_uses_multiple_signals_and_upgrade_skips_onboarding(self) -> None:
        result = self.run_node(
            "const T=require('./shell/models/TabletMode.js'); const C=require('./shell/models/Config.js'); "
            "const fresh=C.defaults(); const legacy=C.migrate({schemaVersion:1,general:{mode:'automatic'},touch:{enabled:true}}); "
            "console.log(JSON.stringify({tablet:T.decide({touchscreen:true,stylus:false,physicalKeyboard:false,orientation:'portrait',lastInput:'keyboard'},{mode:'automatic',tabletMode:{enabled:true}}), "
            "hybrid:T.decide({touchscreen:true,stylus:false,physicalKeyboard:true,orientation:'landscape',lastInput:'keyboard'},{mode:'automatic',tabletMode:{enabled:true}}), "
            "switch:T.decide({touchscreen:true,tabletSwitchAvailable:true,tabletSwitchActive:true},{mode:'automatic',tabletMode:{enabled:true}}), "
            "profile:T.profile('tablet',{tabletMode:{touchTarget:52,dockPreference:'adaptive'},keyboard:{autoShow:true},dock:{position:'bottom'}},{orientation:'portrait'}), "
            "legacyMode:C.migrate({schemaVersion:2,performance:{qualityPreset:'performance'}}).performance.mode, "
            "fresh:fresh.onboarding,legacy:legacy.onboarding}));"
        )
        self.assertEqual(result["tablet"]["mode"], "tablet")
        self.assertEqual(result["hybrid"]["mode"], "hybrid")
        self.assertEqual(result["switch"]["mode"], "tablet")
        self.assertEqual(result["profile"]["dockPosition"], "left")
        self.assertTrue(result["profile"]["oskAutoShow"])
        self.assertFalse(result["fresh"]["completed"])
        self.assertTrue(result["legacy"]["completed"])
        self.assertEqual(result["legacyMode"], "performance")

    def test_08_to_09_input_migration_preserves_user_intent(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); "
            "const migrated=C.migrateDetailed({schemaVersion:2,performance:{mode:'performance'},keyboard:{layout:'ru',autoShow:false},stylus:{pressureCurve:'soft'},rotation:{orientation:'portrait'},tabletMode:{enabled:true}}); "
            "console.log(JSON.stringify({applied:migrated.applied,input:migrated.config.input,keyboard:migrated.config.keyboard,stylus:migrated.config.stylus,rotation:migrated.config.rotation}));"
        )
        self.assertIn("input-v1", result["applied"])
        self.assertEqual(result["input"]["nativeBackend"], "auto")
        self.assertEqual(result["input"]["deviceMappings"], {})
        self.assertEqual(result["keyboard"]["layout"], "ru")
        self.assertFalse(result["keyboard"]["autoShow"])
        self.assertEqual(result["stylus"]["pressureCurve"], "soft")
        self.assertEqual(result["rotation"]["orientation"], "portrait")

        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        panel = (ROOT / "shell/Panel.qml").read_text(encoding="utf-8")
        onboarding = (ROOT / "shell/views/Onboarding.qml").read_text(encoding="utf-8")
        self.assertIn("TabletModeModel.decide", service)
        self.assertIn("InputDevicesModel", service)
        self.assertIn("postureTransition", service)
        self.assertIn("needsOnboarding", service)
        self.assertIn('"onboarding"', panel)
        self.assertIn("onboarding.skipped", onboarding)
        self.assertIn("onboarding.completed", onboarding)

    def test_responsive_context_uses_logical_size_and_input_density(self) -> None:
        result = self.run_node(
            "const R=require('./shell/models/Responsive.js'); "
            "console.log(JSON.stringify({small:R.context(1280,800,1.25,'mouse','desktop',{}),"
            "portrait:R.context(1600,2560,2,'touch','tablet',{touchTargetSize:'large'}),"
            "wide:R.classify(3440,1440,1),cols:R.columns(1600,1000,1,'touch','tablet',144)}));"
        )
        self.assertEqual(result["small"]["breakpoint"], "small-laptop")
        self.assertEqual(result["small"]["logicalWidth"], 1024)
        self.assertEqual(result["portrait"]["orientation"], "portrait")
        self.assertGreaterEqual(result["portrait"]["targetSize"], 56)
        self.assertEqual(result["wide"], "ultrawide")
        self.assertGreaterEqual(result["cols"], 2)

    def test_input_mode_hysteresis_ignores_single_spikes(self) -> None:
        result = self.run_node(
            "const I=require('./shell/models/Input.js'); let s=I.state({current:'keyboard'}); "
            "s=I.observe(s,'touch',1000,320); const spike=s.current; "
            "s=I.observe(s,'keyboard',1100,320); const cancelled=s.current; "
            "s=I.observe(s,'touch',2000,320); s=I.commit(s,2300,320); const before=s.current; "
            "s=I.commit(s,2400,320); console.log(JSON.stringify({spike,cancelled,before,after:s.current,delay:I.delay('touch',100)}));"
        )
        self.assertEqual(result["spike"], "keyboard")
        self.assertEqual(result["cancelled"], "keyboard")
        self.assertEqual(result["before"], "keyboard")
        self.assertEqual(result["after"], "touch")
        self.assertGreaterEqual(result["delay"], 360)

    def test_design_tokens_and_service_expose_responsive_state(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        tokens = (ROOT / "shell/components/DesignTokens.qml").read_text(encoding="utf-8")
        self.assertIn("ResponsiveModel.context", service)
        self.assertIn("inputModeCommit", service)
        self.assertIn("Responsive.context", tokens)
        self.assertIn("reduceTransparency", tokens)

    def test_favorites_persistence_and_dock_config_helpers(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const D=require('./shell/models/Dock.js'); "
            "const base=C.defaults(); const next=C.set(base,'launcher.favorites',['org.gnome.Nautilus','firefox']); "
            "console.log(JSON.stringify({favorites:C.get(next,'launcher.favorites',[]),dock:D.config(next),order:D.reorder(['a','b','c'],'c',0)}));"
        )
        self.assertEqual(result["favorites"], ["org.gnome.Nautilus", "firefox"])
        self.assertEqual(result["dock"]["mode"], "floating")
        self.assertEqual(result["order"], ["c", "a", "b"])

    def test_launcher_favorites_are_ordered_and_folders_are_persistent(self) -> None:
        result = self.run_node(
            "const A=require('./shell/models/Apps.js'); "
            "const rows=A.sorted([{id:'one',name:'One'},{id:'two',name:'Two'},{id:'three',name:'Three'}],'',10,['two','one'],[]); "
            "let folders=A.normalizeFolders([{id:'work',name:'Work',apps:['one','one']}]); "
            "folders=A.addToFolder(folders,'work','two'); folders=A.renameFolder(folders,'work','Projects'); "
            "console.log(JSON.stringify({order:rows.map(x=>x.id),folder:folders[0],removed:A.removeFromFolder(folders,'work','one')[0].apps,deleted:A.deleteFolder(folders,'work')}));"
        )
        self.assertEqual(result["order"][:2], ["two", "one"])
        self.assertEqual(result["folder"]["name"], "Projects")
        self.assertEqual(result["folder"]["apps"], ["one", "two"])
        self.assertEqual(result["removed"], ["two"])
        self.assertEqual(result["deleted"], [])
        launcher = (ROOT / "shell/views/Launcher.qml").read_text(encoding="utf-8")
        self.assertIn("adaptiveColumns", launcher)
        self.assertIn('Drag.keys: ["omanome-app"', launcher)
        self.assertIn("launcher.folders", launcher)

    def test_dock_contains_only_user_favorites_running_apps_and_explicit_items(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const D=require('./shell/models/Dock.js'); "
            "const d=D.config(C.defaults()); console.log(JSON.stringify({running:d.runningApplications,launcher:d.showLauncher,apps:C.defaults().dock.showApplications||false}));"
        )
        self.assertTrue(result["running"])
        self.assertTrue(result["launcher"])
        self.assertFalse(result["apps"])
        dock = (ROOT / "shell/views/Dock.qml").read_text(encoding="utf-8")
        self.assertIn("if (root.dockConfig.runningApplications)", dock)
        self.assertNotIn("result.length < 18", dock)
        self.assertNotIn("for (var a = 0; a < root.applications.length", dock)

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

    def test_dynamic_workspace_keeps_active_empty_and_window_layout_is_mosaic(self) -> None:
        result = self.run_node(
            "const W=require('./shell/models/Workspaces.js'); const L=require('./shell/models/WindowLayout.js'); "
            "const ids=W.ids([{id:1,windows:[1]},{id:2,windows:[]}],'dynamic',5,2); "
            "const rects=L.rects([{width:1600,height:900},{width:900,height:1600},{width:1200,height:800}],900,500,12); "
            "console.log(JSON.stringify({ids,rects,overlap:rects.some((a,i)=>rects.slice(i+1).some(b=>a.x<b.x+b.width&&a.x+a.width>b.x&&a.y<b.y+b.height&&a.y+a.height>b.y))}));"
        )
        self.assertEqual(result["ids"], [1, 2])
        self.assertFalse(result["overlap"])
        self.assertEqual(len(result["rects"]), 3)

    def test_overview_search_has_apps_windows_settings_and_actions(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/Search.js'); const rows=S.all('перо',{"
            "apps:[{id:'ink',name:'Ink',comment:'drawing'}],windows:[],"
            "settings:[{key:'stylus',title:'Stylus',description:'Pen settings',aliases:['перо']}],"
            "actions:[{key:'settings',title:'Settings',description:'Open settings',aliases:[]} ]}); "
            "console.log(JSON.stringify({kinds:rows.map(x=>x.kind),setting:rows[0]&&rows[0].id}));"
        )
        self.assertIn("setting", result["kinds"])
        self.assertEqual(result["setting"], "stylus")
        overview = (ROOT / "shell/views/Overview.qml").read_text(encoding="utf-8")
        self.assertIn("Search.all", overview)
        self.assertIn("WindowLayout.rects", overview)
        self.assertIn("Current workspace first", overview)

    def test_settings_2_0_has_deep_links_search_accessibility_and_safe_diagnostics(self) -> None:
        settings = (ROOT / "shell/views/Settings.qml").read_text(encoding="utf-8")
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        button = (ROOT / "shell/components/ActionButton.qml").read_text(encoding="utf-8")
        for value in ("openDeepLink", "filteredCategories", "settings:", "mobileDetails", "accessibility", "diagnostics", "copyDiagnostics", "resetCategory"):
            self.assertIn(value, settings)
        self.assertIn("diagnosticsObject", service)
        self.assertIn("clipboardEntries", service)  # status keeps only a count, not contents
        self.assertNotIn("clipboardHistory", service[service.index("function diagnosticsObject"):service.index("function diagnosticsText")])
        self.assertIn("Accessible.name", button)

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
        self.assertEqual(result["schemaVersion"], 2)
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
            ROOT / "input/force-quit.sh",
            ROOT / "input/companion-info.sh",
            ROOT / "input/audio-devices.sh",
            ROOT / "input/device-monitor.sh",
            ROOT / "input/session-monitor.sh",
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
        for key in ("orientation", "posture"):
            self.assertIn(key, payload)
            self.assertIn("available", payload[key])
            self.assertIn("state", payload[key])
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertIn("touch-info", cli)
        self.assertIn("sensor-info", cli)
        self.assertIn("input-info", cli)

    def test_companion_contract_is_optional_and_version_aware(self) -> None:
        companion = ROOT / "hypr/omanome-hypr"
        source = (companion / "omanome-hypr.cpp").read_text(encoding="utf-8")
        renderer = (companion / "wobbly-effect.cpp").read_text(encoding="utf-8")
        metadata = json.loads((companion / "compatibility.json").read_text(encoding="utf-8"))
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertEqual(metadata["protocolVersion"], 2)
        self.assertEqual(metadata["pluginVersion"], "1.0.0")
        self.assertEqual(metadata["statusIpc"], "hyprctl -j omanome-effects")
        self.assertIn("__hyprland_api_get_hash", source)
        self.assertIn("__hyprland_api_get_client_hash", source)
        self.assertIn("HyprlandAPI::getHyprlandVersion", source)
        self.assertIn("IWindowTransformer", renderer)
        self.assertIn("wobbly config key=value ...", source)
        self.assertIn("configJson()", source)
        self.assertIn("glClearColor(0.F, 0.F, 0.F, 0.F)", renderer)
        self.assertIn("glBlendFuncSeparate", renderer)
        self.assertNotIn("LD_PRELOAD", renderer)
        self.assertNotIn("dlsym", renderer)
        self.assertNotIn("dlopen", renderer)
        self.assertNotIn("mprotect", renderer)
        self.assertIn("companion_doctor_cmd", cli)
        self.assertIn("companion_enable_cmd", cli)
        self.assertIn("companion_recover_cmd", cli)
        self.assertIn("companion_pending_marker", cli)
        self.assertIn("companion_disabled_marker", cli)
        self.assertIn("load.pending", cli)
        self.assertNotIn("sudo pacman", cli)
        self.assertNotIn("LD_PRELOAD", source)

        result = self.run_node(
            "const C=require('./shell/models/Companion.js'); "
            "const good={installed:true,built:true,loaded:true,protocolVersion:2,pluginVersion:'1.0.0'," \
            "runtime:{version:'0.56.2',abi:'same'},build:{version:'0.56.2',abi:'same',pluginBuild:'1.0.0'}," \
            "versionMatch:true,pluginBuildMatch:true,artifactHashMatch:true,compatibility:{pluginVersion:'1.0.0'}," \
            "capabilities:{desktopCube:true}}; " \
            "const bad={...good,runtime:{abi:'new'},build:{abi:'old'}}; " \
            "const crashed={...good,crashMarker:true}; "
            "console.log(JSON.stringify({good:C.normalize(good),bad:C.normalize(bad),crashed:C.normalize(crashed),canLoad:C.canLoad(good),crashedCanLoad:C.canLoad(crashed),cube:C.effectAvailable(good,'desktopCube')}));"
        )
        self.assertTrue(result["good"]["compatible"])
        self.assertFalse(result["bad"]["compatible"])
        self.assertTrue(result["canLoad"])
        self.assertTrue(result["crashed"]["crashMarker"])
        self.assertFalse(result["crashed"]["compatible"])
        self.assertFalse(result["crashedCanLoad"])
        self.assertTrue(result["cube"])

        with tempfile.TemporaryDirectory() as temp:
            env = os.environ.copy()
            env.update({"HOME": temp, "XDG_STATE_HOME": temp + "/state", "XDG_CONFIG_HOME": temp + "/config", "XDG_DATA_HOME": temp + "/data"})
            info = subprocess.run([str(ROOT / "input/companion-info.sh")], capture_output=True, text=True, env=env)
        self.assertEqual(info.returncode, 0, info.stderr)
        payload = json.loads(info.stdout)
        for key in ("crashMarker", "safeMode", "abiMatch", "versionMatch", "pluginBuildMatch", "artifactHashMatch", "crashCount", "loadFailureCount"):
            self.assertIn(key, payload)
            if key.endswith("Count"):
                self.assertIsInstance(payload[key], int)
            else:
                self.assertIsInstance(payload[key], bool)

    def test_effects_animation_and_rules_are_adaptive_without_fake_backends(self) -> None:
        result = self.run_node(
            "const E=require('./shell/models/Effects.js'); const A=require('./shell/models/Animations.js'); "
            "const P=require('./shell/models/Performance.js'); const R=require('./shell/models/AppRules.js'); "
            "const blur=E.effectiveBlur({enabled:true,quality:'quality',highGpuThreshold:0.85,defaults:{},surfaces:{}},'dock',{batterySaver:true,backendAvailable:true}); "
            "const rule=R.decision([{id:'game',appId:'steam',fullscreen:true,disableBlur:true,disableWobbly:true}],{appId:'steam',fullscreen:1},{inputKind:'touch'}); "
            "const motion=A.transition({enabled:true,preset:'Smooth'},180,true); "
            "const performance=P.snapshot({qualityPreset:'balanced',adaptiveQuality:true,highGpuThreshold:0.85},{gpuLoad:0.92}); "
            "const battery=P.snapshot({mode:'balanced',disableOnBattery:true},{batterySaver:true}); "
            "const automatic=P.snapshot({mode:'automatic',adaptiveQuality:true},{powerProfile:'performance'}); "
            "const quality=P.snapshot({mode:'quality'},{}); "
            "const caps=E.capabilityState({desktopCube:false},{desktopCube:true,desktopCubeBackend:'omarchy-desktop-cube'}); "
            "const rules=E.layerRules({enabled:true,quality:'balanced',surfaces:{dock:{enabled:true}}},{backend:'hyprland-layer-rule',layerRulesAvailable:true},{backendAvailable:true}); "
            "console.log(JSON.stringify({blur,rule,motion,performance,battery,automatic,quality,caps,rules}));"
        )
        self.assertEqual(result["blur"]["quality"], "battery-saver")
        self.assertEqual(result["blur"]["passes"], 0)
        self.assertIn("game", result["rule"]["matched"])
        self.assertTrue(result["rule"]["disableBlur"])
        self.assertTrue(result["motion"]["duration"] <= 80)
        self.assertEqual(result["performance"]["quality"], "performance")
        self.assertEqual(result["performance"]["requestedMode"], "balanced")
        self.assertEqual(result["battery"]["mode"], "battery-saver")
        self.assertFalse(result["battery"]["effectsEnabled"])
        self.assertEqual(result["automatic"]["mode"], "quality")
        self.assertEqual(result["quality"]["mode"], "quality")
        self.assertEqual(result["quality"]["previewStreams"], 4)
        self.assertEqual(result["caps"]["desktopCubeBackend"], "omarchy-desktop-cube")
        self.assertTrue(any(item["rule"] == "blur,namespace:omanome-dock" for item in result["rules"]))

        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        switcher = (ROOT / "shell/views/Switcher.qml").read_text(encoding="utf-8")
        self.assertIn("keyword layerrule", service)
        self.assertIn("surfaceBlur", service)
        self.assertIn("ScreencopyView", switcher)
        self.assertIn("hyprland-toplevel-export-v1", switcher)

    def test_effects_info_and_alt_tab_are_capability_gated(self) -> None:
        effects_info = ROOT / "input/effects-info.sh"
        result = subprocess.run([str(effects_info)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        for key in ("hyprlandAvailable", "layerRulesAvailable", "livePreviewAvailable"):
            self.assertIn(key, payload)
            self.assertIsInstance(payload[key], bool)
        self.assertFalse(payload["livePreviewAvailable"])

        result = self.run_node(
            "const A=require('./shell/models/AltTab.js'); "
            "const windows=[{appId:'one',title:'One',workspace:{id:2},monitor:{name:'HDMI-A-1'}},"
            "{appId:'one',title:'One second',workspace:{id:2},monitor:{name:'HDMI-A-1'}},"
            "{appId:'two',title:'Two',workspace:{id:1},monitor:{name:'HDMI-A-1'}}]; "
            "const rows=A.selectable(windows,{style:'coverflow',groupByApp:true,scope:'current-workspace'},"
            "{workspaceId:2,monitorName:'HDMI-A-1'}); "
            "console.log(JSON.stringify({count:rows.length,groupSize:rows[0].count,preview:A.previewState({livePreview:'auto'},windows,{available:false,reason:'probe'}),"
            "visual:A.visual(1,0,3,{style:'coverflow',angle:28}),next:A.moveIndex(2,1,3)}));"
        )
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["groupSize"], 2)
        self.assertFalse(result["preview"]["enabled"])
        self.assertEqual(result["next"], 0)
        self.assertGreater(result["visual"]["rotation"], 0)

        cube = self.run_node(
            "const C=require('./shell/models/Cube.js'); const W=require('./shell/models/Wobbly.js'); "
            "console.log(JSON.stringify({lua:C.lua('workspace','left'),bad:C.lua('workspace','other'),nan:C.lua('select',NaN),"
            "cube:C.state({enabled:true},{desktopCube:true,desktopCubeBackend:'omarchy-desktop-cube'}),"
            "wobbly:W.state({enabled:true},{wobblyWindows:false},{appId:'steam',fullscreen:false})}));"
        )
        self.assertEqual(cube["lua"], 'hl.plugin.desktop_cube.workspace("left")')
        self.assertEqual(cube["bad"], "")
        self.assertEqual(cube["nan"], "")
        self.assertTrue(cube["cube"]["available"])
        self.assertFalse(cube["wobbly"]["enabled"])

        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertIn("effects_cmd", cli)
        self.assertIn("benchmark_cmd", cli)

    def test_force_quit_is_pid_scoped_and_protects_the_session(self) -> None:
        result = self.run_node(
            "const F=require('./shell/models/ForceQuit.js'); "
            "const app=F.target({appId:'firefox',title:'Test window',pid:123,workspace:{id:4}}); "
            "const shell=F.target({appId:'omarchy-shell',title:'Omarchy',pid:456}); "
            "console.log(JSON.stringify({policy:F.normalize({policy:'graceful-term-kill'}),app:{pid:app.pid,selectable:app.selectable,protected:app.protectedByApp},shell:{selectable:shell.selectable,protected:shell.protectedByApp,reason:shell.protectedReason},term:F.requiresTerm('graceful-term'),kill:F.requiresKill('graceful-term-kill'),foreign:typeof F.foreign(app.window)}));"
        )
        self.assertEqual(result["policy"]["policy"], "graceful-term-kill")
        self.assertEqual(result["app"]["pid"], 123)
        self.assertTrue(result["app"]["selectable"])
        self.assertFalse(result["app"]["protected"])
        self.assertFalse(result["shell"]["selectable"])
        self.assertTrue(result["shell"]["protected"])
        self.assertEqual(result["shell"]["reason"], "Omarchy shell")
        self.assertTrue(result["term"])
        self.assertTrue(result["kill"])
        self.assertEqual(result["foreign"], "object")

        helper = ROOT / "input/force-quit.sh"
        protected = subprocess.run([str(helper), "term", "1", "0"], capture_output=True, text=True)
        self.assertEqual(protected.returncode, 3)
        self.assertTrue(json.loads(protected.stdout)["protected"])

        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        self.assertIn("forceQuitTermProcess", service)
        self.assertIn("forceQuitKillProcess", service)
        self.assertIn("function forceQuit(): string", service)
        self.assertNotIn('"hyprctl", "kill"', service)
        self.assertNotIn("hyprctl kill", cli)

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
        self.assertIn("rotationLifecycleAllowed", service)
        self.assertIn("abortRotation", service)
        self.assertIn("rotationMonitorName", service)
        self.assertIn("rollbackConfirmed", service)
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

            mime_sensitive = subprocess.run(
                [str(capture), "application/x-password-manager"], input="secret", text=True, capture_output=True, env=env
            )
            self.assertEqual(mime_sensitive.returncode, 0, mime_sensitive.stderr)
            self.assertEqual(mime_sensitive.stdout, "")

        result = self.run_node(
            "const C=require('./shell/models/Clipboard.js'); const N=require('./shell/models/Notifications.js'); "
            "const history=[{type:'text',text:'keep',pinned:true,tags:['work']},{type:'text',text:'drop',capturedAt:'2020-01-01T00:00:00Z'}]; "
            "const fake={count:3,get:i=>[{app:'Mail',summary:'one',body:'a',timestamp:100},{app:'Mail',summary:'two',body:'b',timestamp:200},{app:'Chat',summary:'three',body:'c',timestamp:150}][i]}; "
            "console.log(JSON.stringify({mime:C.sensitiveMime('text/password'),secret:C.normalize({type:'text',text:'x',mime:'application/x-secret'}),tags:C.normalizeTags('a,b,a'),clear:C.clearUnpinned(history),prune:C.prune(history,{historyLimit:10,retentionDays:30,maxStorageMb:1},Date.parse('2026-09-06T00:00:00Z')).length,excluded:C.excludedApp('org.example.App',['org.example.*']),rows:N.rows({popupModel:fake},{groupByApp:true,timestamps:true,maxHistory:10},300)}));"
        )
        self.assertTrue(result["mime"])
        self.assertIsNone(result["secret"])
        self.assertEqual(result["tags"], ["a", "b"])
        self.assertEqual(len(result["clear"]), 1)
        self.assertEqual(result["prune"], 1)
        self.assertTrue(result["excluded"])
        self.assertEqual(len(result["rows"]), 2)
        self.assertEqual(result["rows"][0]["count"], 2)
        self.assertEqual(result["rows"][0]["indices"], [0, 1])

        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        clipboard_view = (ROOT / "shell/views/Clipboard.qml").read_text(encoding="utf-8")
        notifications_view = (ROOT / "shell/views/Notifications.qml").read_text(encoding="utf-8")
        self.assertIn("copyProcess.secret", service)
        self.assertIn("ClipboardModel.persistable", service)
        self.assertNotIn('["wl-copy", entry.text', service)
        self.assertIn("clearClipboardUnpinned", clipboard_view)
        self.assertIn("editClipboardText", clipboard_view)
        self.assertIn("DragHandler", notifications_view)
        self.assertIn("toggleNotificationMute", notifications_view)

    def test_multitasking_launch_and_drop_paths_are_bounded_and_identity_safe(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        matcher = (ROOT / "shell/models/WindowMatcher.js").read_text(encoding="utf-8")
        dock = (ROOT / "shell/views/Dock.qml").read_text(encoding="utf-8")
        overview = (ROOT / "shell/views/Overview.qml").read_text(encoding="utf-8")
        launcher = (ROOT / "shell/views/Launcher.qml").read_text(encoding="utf-8")
        controls = (ROOT / "shell/views/WindowControls.qml").read_text(encoding="utf-8")
        floating = (ROOT / "shell/models/FloatingWindows.js").read_text(encoding="utf-8")

        self.assertIn('import "models/WindowMatcher.js" as WindowMatcherModel', service)
        self.assertIn("resolveMultitaskingLaunch", service)
        self.assertIn("multitaskingLaunchTimeout", service)
        self.assertIn("root.resolveMultitaskingLaunch()", service)
        self.assertIn("launchAppToZone", service)
        self.assertIn("launchAppToSplit", service)
        self.assertTrue("appId/PID" in matcher or "address/PID/app id" in matcher)
        self.assertNotIn("title", matcher.split("function matchWindow", 1)[1])
        self.assertIn("DropArea", dock)
        self.assertIn("app-slot", dock)
        self.assertIn("DropArea", overview)
        self.assertIn("window-slot", overview)
        self.assertIn("DropArea", launcher)
        self.assertIn("app-slot", launcher)
        self.assertIn("snapZonesForTarget", dock)
        self.assertIn("snapZonesForTarget", launcher)
        self.assertIn("snapWindowToZone", overview)
        self.assertIn('import "models/FloatingWindows.js" as FloatingWindowsModel', service)
        for marker in ("floatingWindowState", "toggleWindowFloating", "setWindowMini", "setWindowPictureInPicture", "applyFloatingPlan"):
            self.assertIn(marker, service)
        for marker in ("GridLayout", "toggleWindowFloating", "setWindowMini", "setWindowPictureInPicture", "floatingWindowState"):
            self.assertIn(marker, controls)
        self.assertIn("address-scoped commands", floating)
        self.assertNotIn("title", floating)
        self.assertIn("pairEntries", launcher)
        self.assertIn("pairIcon", launcher)
        self.assertIn("launchPair", launcher)
        self.assertIn("Accessible.name", launcher)
        self.assertIn("service.launchAppPair", launcher)
        self.assertIn("groupEntries", overview)
        self.assertIn("windowGroupSummaries", overview)
        self.assertIn("service.launchAppPair", overview)

    def test_window_groups_are_persistent_metadata_only_and_service_wired(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        groups = (ROOT / "shell/models/WindowGroups.js").read_text(encoding="utf-8")
        settings = (ROOT / "shell/views/Settings.qml").read_text(encoding="utf-8")
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))

        self.assertIn('import "models/WindowGroups.js" as WindowGroupsModel', service)
        for marker in ("loadWindowGroups", "persistWindowGroups", "reconcileWindowGroups", "createWindowGroup", "saveAppPair", "breakWindowGroup", "windowGroupSummaries", "launchAppPair", "startNextMultitaskingPairLaunch", "finishMultitaskingPairLaunch"):
            self.assertIn(marker, service)
        self.assertIn("WindowGroupsModel.metadataList", service)
        self.assertIn("root.reconcileWindowGroups()", service)
        self.assertIn("multitaskingPairLaunch", service)
        self.assertIn("duplicate-window-choice-required", service)
        self.assertIn("launch-timeout", service)
        self.assertIn("multitasking", defaults)
        self.assertIn("multitasking", schema["properties"])
        self.assertIn("sessionRestore", defaults["multitasking"])
        self.assertEqual(defaults["multitasking"]["sessionRestore"], "ask")
        for section in ("floating", "gestures", "workspaceNavigation", "multiMonitor"):
            self.assertIn(section, defaults["multitasking"])
        for marker in ("Snap Assist", "Split View", "App Pairs", "Window Groups", "Floating Windows", "Gestures", "Workspace Navigation", "Multi-monitor", "Session Restore", "saveAppPairFromSettings", "ComboBox", "windowGroupRestoreSummary"):
            self.assertIn(marker, settings)
        self.assertIn("metadataList", groups)
        self.assertIn("runtime", groups)
        persistent_section = groups.split("function metadata", 1)[1].split("function normalizeList", 1)[0]
        self.assertNotIn("identity", persistent_section)
        self.assertNotIn("address", persistent_section)
        self.assertNotIn("pid", persistent_section)

    def test_native_omarchy_validator_when_available(self) -> None:
        omarchy = shutil.which("omarchy")
        if not omarchy:
            self.skipTest("omarchy is not installed")
        result = subprocess.run(
            [omarchy, "plugin", "validate", str(ROOT)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gesture_coordinator_is_unified_touch_safe_and_event_driven(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        gesture = (ROOT / "shell/models/GestureCoordinator.js").read_text(encoding="utf-8")
        recovery = (ROOT / "shell/models/MonitorRecovery.js").read_text(encoding="utf-8")
        quicksettings = (ROOT / "shell/views/QuickSettings.qml").read_text(encoding="utf-8")
        dock = (ROOT / "shell/views/Dock.qml").read_text(encoding="utf-8")
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))

        self.assertIn('import "models/GestureCoordinator.js" as GestureCoordinatorModel', service)
        for marker in ("gestureContext", "beginGesture", "updateGesture", "endGesture", "cancelGesture", "gestureAvailableOwners", "gestureActionRequested"):
            self.assertIn(marker, service)
        for marker in ("ownerFor", "availableOwners", "begin", "update", "end", "cancel", "touchpad", "fullscreen-suppressed", "drawing-app-suppressed", "game-suppressed"):
            self.assertIn(marker, gesture)
        self.assertNotIn("title", gesture)
        for marker in ("MonitorRecoveryModel", "monitorRecoveryState", "applyMonitorRecoveryPlan", "monitor-recovery"):
            self.assertIn(marker, service)
        for marker in ("normalizeMonitors", "diff", "safeRect", "plan", "MAX_COMMANDS", "window-address-unavailable"):
            self.assertIn(marker, recovery)
        self.assertNotIn("title", recovery)
        self.assertIn("touchGesturesLock", quicksettings)
        self.assertIn("onGestureActionRequested", dock)
        gestures = defaults["multitasking"]["gestures"]
        self.assertIn("touchscreen", gestures)
        self.assertIn("touchpad", gestures)
        self.assertFalse(gestures["touchpad"]["enabled"])
        self.assertEqual(gestures["fullscreenPolicy"], "disable")


if __name__ == "__main__":
    unittest.main()
