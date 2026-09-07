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


if __name__ == "__main__":
    unittest.main()
