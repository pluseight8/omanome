from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class LayoutEngineTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_landscape_snap_zones_cover_required_layout_families(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const ids=L.zones({name:'HDMI-A-1',width:1920,height:1080,scale:1},{gap:16}).map(x=>x.id); "
            "console.log(JSON.stringify(ids));"
        )
        for name in (
            "half-left", "half-right", "third-left", "third-center", "third-right",
            "two-thirds-left", "two-thirds-right", "quarter-top-left", "quarter-top-right",
            "quarter-bottom-left", "quarter-bottom-right", "maximized"
        ):
            self.assertIn(name, result)

    def test_portrait_uses_top_bottom_layouts_instead_of_left_right(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "console.log(JSON.stringify(L.zones({name:'tablet',width:1080,height:1920,scale:1},{}).map(x=>x.id)));"
        )
        self.assertIn("half-top", result)
        self.assertIn("half-bottom", result)
        self.assertIn("third-top", result)
        self.assertIn("two-thirds-bottom", result)
        self.assertNotIn("half-left", result)
        self.assertNotIn("half-right", result)

    def test_reserved_bar_dock_and_gaps_are_respected(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const m={name:'internal',x:100,y:40,width:1920,height:1080,reserved:{top:48,bottom:92}}; "
            "const pair=L.splitPair(m,'50/50',{gap:20},['a','b']); "
            "console.log(JSON.stringify({usable:pair.usable,slots:pair.slots}));"
        )
        self.assertEqual(result["usable"]["y"], 88)
        self.assertEqual(result["usable"]["height"], 940)
        self.assertEqual(result["slots"][0]["rect"]["x"], 100)
        self.assertEqual(result["slots"][1]["rect"]["x"], result["slots"][0]["rect"]["x"] + result["slots"][0]["rect"]["width"] + 20)
        self.assertEqual(result["slots"][0]["rect"]["height"], result["slots"][1]["rect"]["height"])

    def test_scale_keeps_logical_geometry_and_physical_input_can_be_normalized(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const logical=L.normalizeMonitor({width:1600,height:1000,scale:1.5},{}); "
            "const physical=L.normalizeMonitor({physicalWidth:2400,physicalHeight:1500,scale:1.5},{}); "
            "console.log(JSON.stringify({logical,physical}));"
        )
        self.assertEqual(result["logical"]["width"], 1600)
        self.assertEqual(result["physical"]["width"], 1600)
        self.assertEqual(result["logical"]["usable"], result["physical"]["usable"])

    def test_minimum_geometry_is_best_effort_and_never_leaves_monitor(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const small=L.fitMinimum({x:0,y:0,width:100,height:100},{x:0,y:0,width:300,height:200},{width:180,height:140}); "
            "const impossible=L.fitMinimum({x:0,y:0,width:50,height:50},{x:0,y:0,width:100,height:80},{width:180,height:140}); "
            "console.log(JSON.stringify({small,impossible}));"
        )
        self.assertTrue(result["small"]["satisfied"])
        self.assertFalse(result["small"]["bestEffort"])
        self.assertTrue(result["impossible"]["bestEffort"])
        self.assertEqual(result["impossible"]["rect"], {"x": 0, "y": 0, "width": 100, "height": 80})

    def test_touch_and_stylus_activation_are_bounded_and_different(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const zone=L.areaForZone({width:1920,height:1080},'half-left',{}); "
            "const touch=L.activationRect(zone,{width:1920,height:1080},'touch',{}); "
            "const stylus=L.activationRect(zone,{width:1920,height:1080},'stylus',{}); "
            "console.log(JSON.stringify({zone,touch,stylus}));"
        )
        self.assertTrue(result["touch"]["accidentalProtection"])
        self.assertGreater(result["touch"]["dwellMs"], result["stylus"]["dwellMs"])
        self.assertGreater(result["touch"]["movementThreshold"], 0)
        self.assertGreater(result["stylus"]["movementThreshold"], 0)
        self.assertLessEqual(result["touch"]["rect"]["x"], 0)
        self.assertGreaterEqual(result["touch"]["rect"]["width"], result["zone"]["slots"][0]["rect"]["width"])

    def test_portrait_split_axis_is_horizontal_and_ratios_are_preserved(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const pair=L.splitPair({width:1080,height:1920,scale:2},'33/67',{gap:12},['one','two']); "
            "console.log(JSON.stringify(pair));"
        )
        self.assertEqual(result["orientation"], "portrait")
        self.assertEqual(result["axis"], "horizontal")
        self.assertAlmostEqual(result["ratio"], 1 / 3)
        self.assertEqual(result["slots"][0]["windowId"], "one")
        self.assertEqual(result["slots"][1]["windowId"], "two")
        self.assertGreater(result["slots"][1]["rect"]["y"], result["slots"][0]["rect"]["y"])

    def test_custom_layouts_are_bounded_and_signature_is_stable(self) -> None:
        result = self.run_node(
            "const L=require('./shell/models/LayoutEngine.js'); "
            "const options={customLayouts:[{id:'focus-stack',slots:[{id:'a',x:0,y:0,width:0.6,height:1},{id:'b',x:0.6,y:0,width:0.4,height:1}]}]}; "
            "const layout=L.layoutForZone({name:'DP-1',width:2560,height:1600},'focus-stack',options,['a','b']); "
            "const invalid={customLayouts:[{id:'bad',slots:[{x:0,y:0,width:1.2,height:1}]}]}; "
            "console.log(JSON.stringify({layout,signature:L.signature(layout),bad:L.layoutForZone({width:100,height:100},'bad',invalid)}));"
        )
        self.assertEqual(result["layout"]["type"], "custom")
        self.assertEqual([slot["windowId"] for slot in result["layout"]["slots"]], ["a", "b"])
        self.assertTrue(result["signature"])
        self.assertIsNone(result["bad"])

    def test_snap_drag_preview_is_geometry_only_and_commits_once(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SnapAssist.js'); "
            "const monitors=[{name:'tablet',x:0,y:0,width:1080,height:1920,scale:2}]; "
            "let state=S.beginDrag({address:'0xabc',appId:'org.example.App',pid:42},'touch',{x:24,y:960},{}); "
            "state=S.updateDrag(state,{x:50,y:960},monitors,{gap:12,now:1000}); "
            "const pending=state.phase; "
            "state=S.updateDrag(state,{x:50,y:960},monitors,{gap:12,now:1300}); "
            "const ready=state.phase; const selected=S.selectZone(state,'half-bottom',monitors[0],{gap:12,now:1400}); "
            "const committed=S.commit(selected); "
            "console.log(JSON.stringify({pending,ready,preview:selected.preview,committed}));"
        )
        self.assertEqual(result["pending"], "previewing")
        self.assertEqual(result["ready"], "ready")
        self.assertEqual(result["preview"]["axis"], "horizontal")
        self.assertEqual(result["committed"]["action"]["zoneId"], "half-bottom")
        self.assertEqual(result["committed"]["action"]["layout"]["slots"][0]["windowId"], "address:0xabc")
        self.assertTrue(result["committed"]["state"]["committed"])

    def test_touch_accidental_protection_and_stylus_proximity_rule(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SnapAssist.js'); const m=[{name:'main',width:1920,height:1080}]; "
            "let touch=S.beginDrag('address:touch','touch',{x:10,y:10},{}); "
            "touch=S.updateDrag(touch,{x:20,y:20},m,{now:1000}); "
            "let pen=S.beginDrag({address:'pen',appId:'ink'},'stylus',{x:10,y:10},{proximity:true}); "
            "pen=S.updateDrag(pen,{x:900,y:20},m,{proximity:true,contact:false,now:1000}); "
            "console.log(JSON.stringify({touch:{phase:touch.phase,reason:touch.reason},pen:{active:pen.active,phase:pen.phase,reason:pen.reason}}));"
        )
        self.assertEqual(result["touch"]["phase"], "waiting-for-movement")
        self.assertEqual(result["pen"]["phase"], "blocked")
        self.assertEqual(result["pen"]["reason"], "stylus-proximity-is-not-a-drag")


if __name__ == "__main__":
    unittest.main()
