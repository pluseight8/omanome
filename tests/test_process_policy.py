from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ProcessPolicyTests(unittest.TestCase):
    def test_backoff_is_bounded_and_crash_loop_is_blocked(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const P=require('./shell/models/ProcessPolicy.js'); "
            "const spec={initialDelayMs:1000,maxDelayMs:4000,maxConsecutiveFailures:3,stableAfterMs:30000}; "
            "console.log(JSON.stringify({delays:[0,1,2,3].map(n=>P.backoffDelay(n,spec)), "
            "restart:P.nextRestart({consecutiveFailures:3,startedAt:0},100,spec), "
            "stable:P.nextRestart({consecutiveFailures:3,startedAt:70000},100000,spec)}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["delays"], [1000, 2000, 4000, 4000])
        self.assertFalse(payload["restart"]["restart"])
        self.assertEqual(payload["restart"]["reason"], "crash-loop-limit")
        self.assertTrue(payload["stable"]["restart"])

    def test_coalescing_and_redaction_are_explicit(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const P=require('./shell/models/ProcessPolicy.js'); "
            "console.log(JSON.stringify({volume:P.coalesceKey(['wpctl','set-volume','@DEFAULT_AUDIO_SINK@','70%']), "
            "launch:P.coalesceKey(['uwsm-app','--','gtk-launch','foo.desktop']), "
            "wifi:P.redactedCommand(['nmcli','device','wifi','connect','ssid','password','secret']), "
            "input:P.redactedCommand(['wtype','--','private text'])}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["volume"], "volume:@DEFAULT_AUDIO_SINK@")
        self.assertEqual(payload["launch"], "")
        self.assertEqual(payload["wifi"][-1], "<redacted>")
        self.assertEqual(payload["input"][-1], "<input>")


if __name__ == "__main__":
    unittest.main()
