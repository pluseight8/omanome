#!/usr/bin/env python3
"""Portable checks for the native input helper's public IPC contract."""

from __future__ import annotations

import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class InputProtocolContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(
            (ROOT / "input/omanome-input/protocol.json").read_text(encoding="utf-8")
        )
        cls.source = (ROOT / "input/omanome-input/src/main.rs").read_text(encoding="utf-8")

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


if __name__ == "__main__":
    unittest.main()
