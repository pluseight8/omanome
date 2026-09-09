from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class CalibrationWizardTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_mapping_wizard_requires_input_then_display_and_identifies_by_touch(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const W=require('./shell/models/CalibrationWizard.js'); "
            "const graph=G.fromSnapshot({monitors:[{name:'External',external:true,geometry:{x:0,y:0,width:1920,height:1080}},{name:'External',external:true,geometry:{x:1920,y:0,width:1920,height:1080}}],devices:[{id:'touch',type:'touchscreen',capabilities:{touchscreen:true}}]}); "
            "let state=W.beginMapping(graph); const input=W.inputs(graph)[0]; const outputs=W.outputs(graph); "
            "const ambiguous=W.selectOutputByName(W.selectInput(state,input.id),'External'); "
            "state=W.selectOutput(ambiguous,outputs[0].id); const wrong=W.identifyOutput(state,outputs[1].id,'touch-to-identify'); "
            "state=W.selectOutput(wrong,outputs[0].id); const identified=W.identifyOutput(state,outputs[0].id,'touch'); const complete=W.confirm(identified); "
            "console.log(JSON.stringify({initial:W.beginMapping(graph),ambiguous,wrong,identified,complete}));"
        )
        self.assertEqual(result["initial"]["phase"], "select-input")
        self.assertEqual(result["ambiguous"]["phase"], "ambiguous")
        self.assertTrue(result["ambiguous"]["ambiguous"])
        self.assertEqual(result["ambiguous"]["error"], "identical-display-names")
        self.assertEqual(result["wrong"]["error"], "identified-different-display")
        self.assertEqual(result["wrong"]["candidate"]["confidence"], "unknown")
        self.assertEqual(result["identified"]["phase"], "confirm")
        self.assertEqual(result["identified"]["identifiedBy"], "touch")
        self.assertEqual(result["complete"]["phase"], "complete")
        self.assertEqual(result["complete"]["candidate"]["confidence"], "confirmed")

    def test_calibration_center_lists_only_relevant_graph_nodes_and_keeps_public_ids_opaque(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const W=require('./shell/models/CalibrationWizard.js'); "
            "const graph=G.fromSnapshot({monitors:[{name:'Panel',builtin:true}],devices:["
            "{id:'touch',type:'touchscreen',capabilities:{touchscreen:true}},"
            "{id:'pen',type:'tablet-tool',capabilities:{pressure:true,tiltX:true}},"
            "{id:'kbd',type:'keyboard',capabilities:{keyboard:true}}]}); "
            "console.log(JSON.stringify({rows:W.calibrationRows(graph,{profiles:{}}),center:W.centerRows(graph,{profiles:{}}),text:JSON.stringify(W.centerRows(graph,{profiles:{}}))}));"
        )
        self.assertEqual({row["category"] for row in result["rows"]}, {"touchscreen", "stylus"})
        self.assertEqual({row["category"] for row in result["center"]}, {"touchscreen", "stylus", "keyboard", "display"})
        self.assertTrue(all(row["advanced"] for row in result["center"]))
        self.assertNotIn("/dev/", result["text"])
        self.assertNotIn("event", result["text"])

    def test_mapping_wizard_fails_closed_when_inventory_is_missing(self) -> None:
        result = self.run_node(
            "const W=require('./shell/models/CalibrationWizard.js'); "
            "console.log(JSON.stringify({none:W.beginMapping({nodes:[],outputs:[]}),displayOnly:W.beginMapping({nodes:[],outputs:[{id:'display:0123456789abcdef',name:'Panel'}]})}));"
        )
        self.assertEqual(result["none"]["phase"], "unavailable")
        self.assertEqual(result["none"]["error"], "no-mappable-input-devices")
        self.assertEqual(result["displayOnly"]["phase"], "unavailable")
        self.assertEqual(result["displayOnly"]["error"], "no-mappable-input-devices")


if __name__ == "__main__":
    unittest.main()
