from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DeviceGraphTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_graph_is_generic_and_redacts_ephemeral_or_sensitive_identity(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); "
            "const graph=G.fromSnapshot({monitors:[{name:'eDP-1',builtin:true,x:0,y:0,width:1920,height:1080,scale:1.25}],"
            "devices:["
            "{id:'touch-1',name:'Touchscreen',type:'touchscreen',vendorId:'1234',productId:'5678',serial:'SERIAL-SECRET',address:'aa:bb:cc:dd:ee:ff',path:'/devices/platform/touch/input/input4/event7',capabilities:{touchscreen:true},output:'eDP-1'},"
            "{id:'pen-1',type:'tablet-tool',capabilities:['pressure','tilt-x','proximity']},"
            "{id:'unknown-1',type:'mystery-box'}]}); "
            "console.log(JSON.stringify({graph,text:JSON.stringify(graph)}));"
        )
        graph = result["graph"]
        self.assertEqual(graph["schemaVersion"], 1)
        self.assertEqual({row["category"] for row in graph["nodes"]}, {"display", "touchscreen", "stylus"})
        self.assertEqual(graph["outputs"][0]["geometry"]["width"], 1920)
        self.assertEqual(graph["outputs"][0]["scale"], 1.25)
        self.assertTrue(any(row["mappedOutput"] for row in graph["nodes"] if row["category"] == "touchscreen"))
        self.assertNotIn("SERIAL-SECRET", result["text"])
        self.assertNotIn("aa:bb:cc:dd:ee:ff", result["text"])
        self.assertNotIn("event7", result["text"])
        self.assertNotIn("/devices/platform", result["text"])

    def test_identity_survives_event_node_renumbering_without_exposing_raw_id(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); "
            "const base={type:'touchscreen',vendorId:'1',productId:'2',path:'/sys/devices/pci0000:00/usb1/input/input9/event4',seat:'seat0',capabilities:{touchscreen:true}}; "
            "const replug={type:'touchscreen',vendorId:'1',productId:'2',path:'/sys/devices/pci0000:00/usb1/input/input9/event8',seat:'seat0',capabilities:{touchscreen:true}}; "
            "const serial={type:'touchscreen',vendorId:'1',productId:'2',serial:'stable-touch',path:'/sys/devices/other/event2',seat:'seat0',capabilities:{touchscreen:true}}; "
            "console.log(JSON.stringify({first:G.stableId(base),second:G.stableId(replug),serial:G.stableId(serial)}));"
        )
        self.assertEqual(result["first"], result["second"])
        self.assertTrue(result["first"].startswith("device:touchscreen:"))
        self.assertNotIn("event", result["first"])
        self.assertNotIn("stable-touch", result["serial"])

    def test_explicit_relationship_keeps_unknown_confidence_honest(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); "
            "const graph=G.fromSnapshot({devices:["
            "{id:'touch-1',type:'touchscreen',capabilities:{touchscreen:true}},"
            "{id:'dock-1',type:'dock',transport:'usb-c'}],"
            "relationships:[{from:'touch-1',to:'dock-1',type:'attached-to',confidence:'unknown'}]}); "
            "console.log(JSON.stringify(graph));"
        )
        self.assertEqual(len(result["relationships"]), 1)
        relation = result["relationships"][0]
        self.assertEqual(relation["type"], "attached-to")
        self.assertEqual(relation["confidence"], "unknown")
        touch = next(row for row in result["nodes"] if row["category"] == "touchscreen")
        dock = next(row for row in result["nodes"] if row["category"] == "dock")
        self.assertEqual(touch["parent"], dock["id"])
        self.assertEqual(touch["relation"], "attached-to")

    def test_nested_inventories_deduplicate_outputs_and_preserve_public_summary(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); "
            "const graph=G.fromSnapshot({monitors:[{name:'HDMI-A-1',external:true,width:2560,height:1440}],"
            "outputs:[{name:'HDMI-A-1',external:true,width:2560,height:1440}],"
            "devices:{keyboards:[{id:'kbd',type:'keyboard',transport:'pogo-pin',detachable:true}],"
            "touchpads:[{id:'pad',type:'touchpad'}],sensors:[{id:'sensor',type:'accelerometer'}]}}); "
            "console.log(JSON.stringify({graph,summary:G.summary(graph)}));"
        )
        graph = result["graph"]
        categories = {row["category"] for row in graph["nodes"]}
        self.assertEqual(categories, {"display", "keyboard", "touchpad", "sensor"})
        self.assertEqual(len(graph["outputs"]), 1)
        self.assertEqual(graph["outputs"][0]["role"], "external")
        self.assertEqual(result["summary"]["nodeCount"], 4)
        self.assertEqual(result["summary"]["outputCount"], 1)
        self.assertEqual(result["summary"]["categories"]["keyboard"], 1)

    def test_service_exposes_graph_summary_without_replacing_existing_input_state(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('"models/DeviceGraph.js" as DeviceGraphModel', service)
        self.assertIn("property var deviceGraph: DeviceGraphModel.emptyState()", service)
        self.assertIn("DeviceGraphModel.fromSnapshot", service)
        self.assertIn("DeviceGraphModel.applyEvent", service)
        self.assertIn("deviceGraph: DeviceGraphModel.summary(root.deviceGraph)", service)


if __name__ == "__main__":
    unittest.main()
