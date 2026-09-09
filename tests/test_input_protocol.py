#!/usr/bin/env python3
"""Portable checks for the native input helper's public IPC contract."""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class InputProtocolContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(
            (ROOT / "input/omanome-input/protocol.json").read_text(encoding="utf-8")
        )
        cls.source = (ROOT / "input/omanome-input/src/main.rs").read_text(encoding="utf-8")
        cls.service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        cls.osk = (ROOT / "shell/views/Osk.qml").read_text(encoding="utf-8")
        cls.osk_policy = (ROOT / "shell/models/OskPolicy.js").read_text(encoding="utf-8")
        cls.devices = (ROOT / "shell/models/InputDevices.js").read_text(encoding="utf-8")
        cls.keyboard_devices = (ROOT / "shell/models/KeyboardDevices.js").read_text(encoding="utf-8")
        cls.tablet_mode = (ROOT / "shell/models/TabletMode.js").read_text(encoding="utf-8")
        cls.stylus_input = (ROOT / "shell/models/StylusInput.js").read_text(encoding="utf-8")
        cls.mapping = (ROOT / "shell/models/Mapping.js").read_text(encoding="utf-8")
        cls.lifecycle = (ROOT / "shell/models/Lifecycle.js").read_text(encoding="utf-8")
        cls.rotation = (ROOT / "shell/models/Rotation.js").read_text(encoding="utf-8")

    def test_protocol_is_versioned_and_bounded(self) -> None:
        self.assertEqual(self.contract["protocol"], "omanome-input")
        self.assertEqual(self.contract["version"], 1)
        limits = self.contract["limits"]
        self.assertGreater(limits["maxCommandBytes"], limits["maxTextBytes"])
        self.assertLessEqual(limits["maxPendingCommands"], 256)
        self.assertLessEqual(limits["maxSurroundingTextBytes"], limits["maxCommandBytes"])
        self.assertIn("MAX_COMMAND_BYTES", self.source)
        self.assertIn("MAX_PENDING_COMMANDS", self.source)

    def test_command_and_event_names_have_source_coverage(self) -> None:
        for name in self.contract["commands"]:
            self.assertIn(f'"{name}"', self.source, name)
        for name in self.contract["events"]:
            self.assertIn(f'"{name}"', self.source, name)

    def test_privacy_contract_is_explicit(self) -> None:
        privacy = self.contract["privacy"]
        self.assertFalse(privacy["typedTextEmitted"])
        self.assertFalse(privacy["surroundingTextEmitted"])
        self.assertFalse(privacy["passwordPayloadPersisted"])
        self.assertFalse(privacy["argvPayloadsAllowed"])
        self.assertIn("Never include command payloads", self.source)
        self.assertIn("never logged", self.source)
        self.assertIn("secure_context", self.source)

    def test_fallback_is_not_presented_as_native(self) -> None:
        self.assertEqual(self.contract["fallback"]["unknown"], "unavailable")
        self.assertIn('"native-wayland"', self.source)
        self.assertIn('"unavailable"', self.source)

    def test_shell_uses_one_persistent_native_process(self) -> None:
        self.assertIn("id: inputBackendProcess", self.service)
        self.assertIn("stdinEnabled: true", self.service)
        self.assertIn("root.nativeInputSend", self.service)
        self.assertIn('"omanome-input"', self.service)
        self.assertIn("ProcessPolicy.nextRestart", self.service)
        self.assertIn("root.wtypeAvailable", self.service)

    def test_native_session_and_ack_boundaries_prevent_stale_or_duplicate_input(self) -> None:
        self.assertIn("OMANOME_INPUT_SESSION", self.service)
        self.assertIn("inputBackendSession", self.service)
        self.assertIn("inputPendingRequests", self.service)
        self.assertIn("request.requestId", self.service)
        self.assertIn("acknowledgement was stale", self.service)
        self.assertIn("cancelFallbackInput", self.service)
        self.assertIn("nativeInputReset", self.service)
        self.assertIn("inputDispatchAllowed", self.service)
        self.assertIn("pressed_keys", self.source)
        self.assertIn("reset_keyboard", self.source)
        self.assertIn("invalid-key-state", self.source)
        self.assertIn("requestId", self.source)

    def test_native_reset_is_part_of_the_public_protocol(self) -> None:
        self.assertIn("keyboard.reset", self.contract["commands"])
        self.assertIn('"keyboard.reset"', self.source)
        self.assertIn('"latchedModifiers"', self.source)
        self.assertIn('"lockedModifiers"', self.source)

    def test_auto_show_requires_real_focus_and_non_physical_input(self) -> None:
        self.assertIn("inputTextBackendAvailable", self.service)
        self.assertIn("inputTextFocusActive", self.service)
        self.assertIn("root.hasPhysicalKeyboard", self.service)
        self.assertIn("OskPolicy.desired", self.service)
        self.assertIn('["touch", "stylus"]', self.osk_policy)

    def test_osk_prediction_and_visibility_are_local_and_hysteretic(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const O=require('./shell/models/Osk.js'); "
            "const P=require('./shell/models/OskPolicy.js'); "
            "let source={autoShow:true,textFocus:true,physicalKeyboard:false,detachableKeyboard:false,bluetoothKeyboard:false,lastInput:'touch',mode:'tablet',touchscreen:true}; "
            "let first=P.transition(source,{},1000); let second=P.transition(source,first.state,1110); "
            "console.log(JSON.stringify({suggestions:O.suggestions('th','en',3),correct:O.autocorrect('teh','en'),first:first.pending,second:second.pending,visible:second.state.visible}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertIn("the", payload["suggestions"])
        self.assertEqual(payload["correct"], "the")
        self.assertTrue(payload["first"])
        self.assertTrue(payload["second"])
        self.assertFalse(payload["visible"])
        self.assertIn("secure field", self.osk)

    def test_device_identity_hotplug_and_posture_are_bounded(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const D=require('./shell/models/InputDevices.js'); "
            "const T=require('./shell/models/TabletMode.js'); "
            "let snapshot={keyboards:[{name:'BT keyboard',vendorId:'1',productId:'2',transport:'bluetooth',detachable:true,type:'keyboard'}]," 
            "touch:[{name:'panel',vendorId:'3',productId:'4',type:'touchscreen'}],posture:'laptop',tabletSwitch:{available:true,active:false}}; "
            "let state=D.stateFromSnapshot(snapshot,D.emptyState()); "
            "let event={type:'device.event',action:'remove',subsystem:'input',device:{name:'BT keyboard',vendorId:'1',productId:'2',transport:'bluetooth',detachable:true,type:'keyboard'}}; "
            "let removed=D.applyEvent(state,event); "
            "let signals=D.postureSignals(snapshot,removed,'keyboard'); "
            "let first=T.transition(signals,{mode:'automatic',tabletMode:{enabled:true,posture:{debounceMs:320,minimumDwellMs:900}}},{current:'desktop',candidate:'',candidateSince:0,lastChangedAt:1000},1100); "
            "console.log(JSON.stringify({ids:state.devices.map(x=>x.id),removed:removed.devices.length,keyboard:signals.physicalKeyboard,mode:T.decide(signals,{mode:'automatic',tabletMode:{enabled:true}}).mode, pending:first.pending, lines:D.explain(signals,'hybrid').lines}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(len(payload["ids"]), 2)
        self.assertEqual(payload["removed"], 1)
        self.assertFalse(payload["keyboard"])
        self.assertEqual(payload["mode"], "hybrid")
        self.assertTrue(payload["pending"])
        self.assertTrue(any("posture: laptop" in line for line in payload["lines"]))

    def test_hotplug_monitor_is_event_driven_and_not_text_capable(self) -> None:
        monitor = (ROOT / "input/device-monitor.sh").read_text(encoding="utf-8")
        self.assertIn("udevadm monitor", monitor)
        self.assertIn("--property", monitor)
        self.assertNotIn("wtype", monitor)
        self.assertIn("device.event", monitor)

    def test_power_monitor_is_signal_driven_and_does_not_poll_upower(self) -> None:
        monitor = (ROOT / "input/power-monitor.sh").read_text(encoding="utf-8")
        self.assertIn("gdbus", monitor)
        self.assertIn("org.freedesktop.UPower", monitor)
        self.assertIn("power.event", monitor)
        self.assertNotIn("upower -e", monitor)

    def test_keyboard_classification_uses_capabilities_and_form_factor(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const K=require('./shell/models/KeyboardDevices.js'); "
            "const rows=K.classify({keyboards:["
            "{name:'Built-in keyboard',type:'keyboard',bus:'i2c',vendorId:'1',productId:'2'},"
            "{name:'Keyboard cover',type:'keyboard',detachable:true,transport:'pogo-pin',vendorId:'3',productId:'4',serial:'PRIVATE-COVER'},"
            "{name:'Dock keyboard',type:'keyboard',dock:true,transport:'usb-c-dock',vendorId:'5',productId:'6'},"
            "{name:'Wireless keyboard',type:'keyboard',transport:'bluetooth',address:'AA:BB:CC:DD:EE:FF',capabilities:['keyboard','KEY_A']},"
            "{name:'Volume buttons',type:'consumer-control',capabilities:{keyboard:true,volume:true}},"
            "{name:'Game controller',type:'gamepad',capabilities:{keyboard:true}},"
            "{name:'Number pad',type:'keyboard',numpadOnly:true,capabilities:{keyboard:true}},"
            "{name:'Keyboard'}]}); "
            "console.log(JSON.stringify({rows,summary:K.summary(rows)}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(len(payload["rows"]), 4)
        self.assertEqual([row["formFactorRelation"] for row in payload["rows"]], ["built-in", "detachable", "dock", "external"])
        self.assertEqual([row["transport"] for row in payload["rows"]], ["i2c", "pogo-pin", "usb-c-dock", "bluetooth"])
        self.assertTrue(all("PRIVATE-COVER" not in row["id"] for row in payload["rows"]))
        self.assertTrue(all("AA:BB:CC:DD:EE:FF" not in row["id"] for row in payload["rows"]))
        self.assertTrue(all(row["name"] == "Keyboard" for row in payload["summary"]))
        self.assertFalse(any(row["name"] == "Keyboard" for row in payload["rows"]))
        self.assertIn("KeyboardDevicesModel.classify", self.service)
        self.assertIn("capabilities", self.keyboard_devices)
        self.assertIn("numpad-only input", self.keyboard_devices)
        self.assertIn("device names are useful", self.keyboard_devices.lower())

    def test_native_stylus_state_is_bounded_and_provider_is_honest(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const S=require('./shell/models/StylusInput.js'); const M=require('./shell/models/Mapping.js'); "
            "let state=S.emptyState(); "
            "for (const e of [{event:'tablet-added',tabletCount:1},{event:'tool-added',toolCount:1},{event:'proximity-in',proximity:true},{event:'tip-down',contact:true},{event:'motion',x:12,y:24,contact:true,proximity:true},{event:'pressure',pressure:32768,contact:true},{event:'tilt',tiltX:10,tiltY:-8,contact:true},{event:'tip-up',contact:false},{event:'proximity-out',proximity:false}]) state=S.applyEvent(state,{type:'tablet.event',...e},1000); "
            "let palm=S.palmTransition({}, {stylusProximity:true,stylusContact:true,touchCount:1},1000,{mode:'balanced'}); "
            "let provider=S.providerState({enabled:true},state); let mapping=M.plan([{id:'tablet-a',role:'stylus',output:'DISCONNECTED'}],[{name:'DP-1'},{name:'HDMI-A-1'}],{},'DP-1'); "
            "let tx=M.transaction({transform:0},1,mapping,['DP-1']); let committed=M.commit(M.apply(tx,true)); let rolled=M.rollback(M.apply(tx,false,'hyprctl failed')); "
            "console.log(JSON.stringify({points:state.totalPoints,pressure:state.capabilities.pressure,proximity:state.proximity,provider:provider.recognition,palm:palm.active,output:mapping[0].output,reason:mapping[0].reason,commit:committed.phase,rollback:rolled.phase}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertGreater(payload["points"], 0)
        self.assertTrue(payload["pressure"])
        self.assertFalse(payload["proximity"])
        self.assertEqual(payload["provider"], "unavailable")
        self.assertTrue(payload["palm"])
        self.assertEqual(payload["output"], "DP-1")
        self.assertEqual(payload["reason"], "configured-output-disconnected")
        self.assertEqual(payload["commit"], "committed")
        self.assertEqual(payload["rollback"], "rolled-back")
        self.assertLessEqual(self.stylus_input.count("MAX_TOTAL_POINTS"), 6)
        self.assertIn("rollback-required", self.mapping)

    def test_stylus_ordering_disconnect_and_partial_hotplug_are_safe(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const S=require('./shell/models/StylusInput.js'); const D=require('./shell/models/InputDevices.js'); "
            "let state=S.emptyState(); "
            "for (const e of [{event:'tablet-added',tabletCount:1,sequence:1,session:'a'}," 
            "{event:'tool-added',toolCount:1,sequence:2,session:'a'}," 
            "{event:'proximity-in',proximity:true,sequence:3,session:'a'}," 
            "{event:'tip-down',contact:true,sequence:4,session:'a'}," 
            "{event:'motion',x:1,y:2,contact:true,proximity:true,sequence:5,session:'a'}," 
            "{event:'tip-up',contact:false,sequence:6,session:'a'}," 
            "{event:'proximity-out',proximity:false,sequence:7,session:'a'}]) state=S.applyEvent(state,{type:'tablet.event',...e},1000); "
            "let duplicate=S.applyEvent(state,{type:'tablet.event',event:'tip-up',sequence:8,session:'a'},1001); "
            "let stale=S.applyEvent(state,{type:'tablet.event',event:'motion',contact:true,proximity:true,sequence:6,session:'a'},1002); "
            "let toolRemoved=S.applyEvent(state,{type:'tablet.event',event:'tool-removed',toolCount:0,sequence:9,session:'a'},1003); "
            "let removed=S.applyEvent(toolRemoved,{type:'tablet.event',event:'tablet-removed',tabletCount:0,sequence:10,session:'a'},1004); "
            "let restarted=S.applyEvent(removed,{type:'tablet.event',event:'tablet-added',tabletCount:1,sequence:1,session:'b'},1005); "
            "let snapshot=D.stateFromSnapshot({devices:[{name:'Pen',type:'tablet-tool',vendorId:'1',productId:'2',serial:'PRIVATE-SERIAL',path:'usb-1-2'}]},D.emptyState()); "
            "let partial=D.applyEvent(snapshot,{type:'device.event',action:'remove',subsystem:'input',device:{path:'usb-1-2',type:'tablet-tool'}}); "
            "console.log(JSON.stringify({duplicate:duplicate.revision===state.revision,stale:stale.revision===state.revision,removed:removed.available===false&&removed.proximity===false&&removed.contact===false,restarted:restarted.eventSequence===1&&restarted.session==='b',deviceCount:partial.devices.length,privateId:snapshot.devices[0].id.indexOf('PRIVATE-SERIAL')<0}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["duplicate"])
        self.assertTrue(payload["stale"])
        self.assertTrue(payload["removed"])
        self.assertTrue(payload["restarted"])
        self.assertEqual(payload["deviceCount"], 0)
        self.assertTrue(payload["privateId"])
        self.assertIn("eventSequence", self.stylus_input)
        self.assertIn("tablet_sequence", (ROOT / "input/omanome-input/src/main.rs").read_text(encoding="utf-8"))
        self.assertEqual(self.contract["tablet"]["hardwareSerials"], "redacted")

    def test_suspend_resume_and_sensor_debounce_are_event_driven(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const L=require('./shell/models/Lifecycle.js'); const R=require('./shell/models/Rotation.js'); "
            "let state=L.emptyState(); let sleep=L.transition(state,{event:'suspend'},1000); let wake=L.transition(sleep.state,{event:'resume'},2000); "
            "let first=R.observe(R.emptyState(),'right-up',1000,{stableMs:550,minimumDwellMs:1000}); let second=R.observe(first.state,'right-up',1300,{stableMs:550,minimumDwellMs:1000}); let third=R.observe(second.state,'right-up',2100,{stableMs:550,minimumDwellMs:1000}); "
            "let retry=L.reconnect({attempts:4},0,{maxAttempts:5,initialDelayMs:1000,maxDelayMs:30000}); "
            "console.log(JSON.stringify({sleep:sleep.state.phase,wake:wake.state.phase,first:first.pending,second:second.pending,third:third.value,retry:retry.retry,blocked:retry.blocked,delay:retry.delayMs}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["sleep"], "suspended")
        self.assertEqual(payload["wake"], "active")
        self.assertTrue(payload["first"])
        self.assertTrue(payload["second"])
        self.assertEqual(payload["third"], "right-up")
        self.assertFalse(payload["retry"])
        self.assertTrue(payload["blocked"])
        self.assertLessEqual(payload["delay"], 30000)
        self.assertIn("dbus-monitor", (ROOT / "input/session-monitor.sh").read_text(encoding="utf-8"))
        self.assertIn("PrepareForSleep", (ROOT / "input/session-monitor.sh").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
