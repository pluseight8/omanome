from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PrivacyAndPerformanceTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_privacy_boundary_redacts_sensitive_values_and_bounds_collections(self) -> None:
        payload = self.run_node(
            "const P=require('./shell/models/Privacy.js'); "
            "const value={serial:'SERIAL-SECRET',address:'AA:BB:CC:DD:EE:FF',path:'/dev/input/event9',"
            "name:'Private serial label',deviceId:'device:keyboard:0123456789abcdef',"
            "legacyId:'keyboard:vendor-123/product-456',typedText:'private',safe:'capability-only',"
            "items:Array.from({length:140},(_,i)=>i)}; "
            "console.log(JSON.stringify(P.boundary(value)));"
        )
        self.assertEqual(payload["serial"], "<redacted>")
        self.assertEqual(payload["address"], "<redacted>")
        self.assertEqual(payload["path"], "<redacted>")
        self.assertEqual(payload["name"], "<redacted>")
        self.assertEqual(payload["deviceId"], "device:keyboard:0123456789abcdef")
        self.assertEqual(payload["legacyId"], "<redacted>")
        self.assertEqual(payload["typedText"], "<redacted>")
        self.assertEqual(payload["safe"], "capability-only")
        self.assertEqual(len(payload["items"]), 129)
        self.assertTrue(payload["privacy"]["collectionsBounded"])

    def test_performance_budget_distinguishes_unknown_from_over_budget(self) -> None:
        payload = self.run_node(
            "const B=require('./shell/models/PerformanceBudget.js'); "
            "console.log(JSON.stringify({empty:B.emptyState(),over:B.snapshot({graphNodes:257,stylusSamples:257}),summary:B.summary(B.snapshot({inputQueue:65}))}));"
        )
        self.assertTrue(payload["empty"]["bounded"])
        self.assertTrue(all(row["result"] == "Pass" for row in payload["empty"]["checks"]))
        self.assertFalse(payload["over"]["bounded"])
        self.assertEqual(set(payload["over"]["overBudget"]), {"graphNodes", "stylusSamples"})
        self.assertFalse(payload["summary"]["bounded"])
        self.assertEqual(payload["summary"]["metrics"]["inputQueue"]["observed"], 65)

    def test_graph_and_input_state_have_hard_collection_bounds(self) -> None:
        payload = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const I=require('./shell/models/InputDevices.js'); "
            "const devices=Array.from({length:400},(_,i)=>({id:'keyboard-'+i,type:'keyboard',capabilities:{keyboard:true}})); "
            "const monitors=Array.from({length:60},(_,i)=>({id:'display-'+i,name:'Display '+i,width:100,height:100})); "
            "const graph=G.fromSnapshot({devices,monitors}); const state=I.normalizeSnapshot({devices,monitors}); "
            "console.log(JSON.stringify({graph:{nodes:graph.nodes.length,outputs:graph.outputs.length,bounds:G.BOUNDS},input:{devices:state.devices.length,monitors:state.monitors.length,bounds:{devices:I.MAX_DEVICES,monitors:I.MAX_MONITORS}}}));"
        )
        self.assertLessEqual(payload["graph"]["nodes"], payload["graph"]["bounds"]["nodes"])
        self.assertLessEqual(payload["graph"]["outputs"], payload["graph"]["bounds"]["outputs"])
        self.assertEqual(payload["input"]["devices"], payload["input"]["bounds"]["devices"])
        self.assertEqual(payload["input"]["monitors"], payload["input"]["bounds"]["monitors"])

    def test_owner_snapshot_redacts_paths_and_inline_command_values(self) -> None:
        from scripts import process_snapshot

        command = process_snapshot._redact_command(
            ["/home/private/bin/omanome-input", "--", "typed text", "/sys/devices/private", "AA:BB:CC:DD:EE:FF"]
        )
        self.assertEqual(command[0], "omanome-input")
        self.assertEqual(command[2], "<input>")
        self.assertEqual(command[3], "<input>")
        self.assertEqual(command[4], "<input>")
        self.assertNotIn("/home/private", json.dumps(command))


if __name__ == "__main__":
    unittest.main()
