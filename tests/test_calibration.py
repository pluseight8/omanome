from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class CalibrationTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_five_real_touch_targets_produce_a_safe_identity_mapping(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Calibration.js'); "
            "const id='device:touchscreen:0123456789abcdef'; const output='display:fedcba9876543210'; "
            "let state=C.beginTouch(id,output,{touchscreen:true,absolute:true},{outputGeometry:{width:1920,height:1080}}); "
            "C.TOUCH_TARGETS().forEach(target=>{state=C.recordTouchSample(state,{targetId:target.id,x:target.x,y:target.y,real:true,source:'native'}).state}); "
            "console.log(JSON.stringify(state));"
        )
        self.assertEqual(result["phase"], "analyzed")
        self.assertEqual(result["result"]["status"], "ready")
        self.assertTrue(result["result"]["safe"])
        self.assertEqual(result["result"]["rotation"], 0)
        self.assertEqual(result["result"]["scale"], {"x": 1, "y": 1})
        self.assertEqual(result["result"]["offset"], {"x": 0, "y": 0})

    def test_touch_rejects_fake_samples_and_suggests_remapping_for_wrong_output(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Calibration.js'); "
            "const id='device:touchscreen:0123456789abcdef'; const output='display:fedcba9876543210'; const other='display:1111111111111111'; "
            "let state=C.beginTouch(id,output,{touchscreen:true,absolute:true}); "
            "const first=C.recordTouchSample(state,{targetId:'top-left',x:0.15,y:0.15,real:false,source:'fixture'}); "
            "state=first.state; state=C.recordTouchSample(state,{targetId:'top-left',x:0.15,y:0.15,real:true,source:'native'}).state; "
            "C.TOUCH_TARGETS().forEach((target,index)=>{if(index===0)return; state=C.recordTouchSample(state,{targetId:target.id,x:0.5,y:0.5,outputId:index===1?other:output,real:true,source:'native'}).state}); "
            "console.log(JSON.stringify({first,phase:state.phase,result:state.result}));"
        )
        self.assertFalse(result["first"]["accepted"])
        self.assertEqual(result["first"]["reason"], "real-sample-required")
        self.assertEqual(result["result"]["status"], "needs-remap")
        self.assertFalse(result["result"]["safe"])
        self.assertEqual(result["result"]["suggestion"], "wrong-monitor-mapping")
        self.assertIsNone(result["result"]["matrix"])

    def test_stylus_analysis_reports_only_supported_real_fields_and_default_linear_curve(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Calibration.js'); const id='device:stylus:0123456789abcdef'; "
            "let state=C.beginStylus(id,{stylus:true,pressure:true,tiltX:true,tiltY:true,proximity:true,eraser:true,buttons:true}); "
            "const fake=C.recordStylusSample(state,{x:0.1,pressure:0.8,real:true,source:'fixture'}); state=fake.state; "
            "[0.2,0.8,1.4].forEach((pressure,index)=>{state=C.recordStylusSample(state,{x:index/2,y:index/2,pressure,tiltX:2,tiltY:-2,proximity:true,eraser:index===2,buttons:2,real:true,source:'native'}).state}); "
            "console.log(JSON.stringify({fake,analysis:state.analysis,sample:state.samples[2],curve:C.curvePoints('linear'),soft:C.curvePoints('soft')}));"
        )
        self.assertFalse(result["fake"]["accepted"])
        self.assertEqual(result["fake"]["reason"], "real-sample-required")
        self.assertEqual(result["analysis"]["sampleCount"], 3)
        self.assertTrue(result["analysis"]["observed"]["pressure"])
        self.assertTrue(result["analysis"]["observed"]["tiltX"])
        self.assertEqual(result["analysis"]["pressure"]["curve"], "soft")
        self.assertEqual(result["sample"]["pressure"], 1)
        self.assertEqual(result["sample"]["tiltX"], 1)
        self.assertEqual(result["sample"]["tiltY"], -1)
        self.assertEqual(result["curve"], [{"x": 0, "y": 0}, {"x": 1, "y": 1}])
        self.assertEqual(result["soft"][0], {"x": 0, "y": 0})

    def test_transaction_commits_only_after_confirmation_and_rolls_back_safely(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Calibration.js'); const id='device:touchscreen:0123456789abcdef'; const out='display:fedcba9876543210'; "
            "const requested={outputId:out,offset:{x:0.02,y:-0.01},scale:{x:1.1,y:0.9},rotation:0}; "
            "let tx=C.prepareTransaction('touchscreen',id,null,requested,1000,{countdownMs:4000}); "
            "const prepared=tx; tx=C.applyTransaction(tx,true,1200); const waiting=tx; const ticking=C.tickTransaction(tx,5000); "
            "let committed=C.confirmTransaction(waiting,true,1400); const disconnected=C.disconnectTransaction(waiting); "
            "const unsafe=C.prepareTransaction('touchscreen',id,null,{outputId:'/dev/input/event7',scale:{x:9,y:1}},1000,{}); "
            "console.log(JSON.stringify({prepared,waiting,ticking,committed,disconnected,unsafe}));"
        )
        self.assertEqual(result["prepared"]["phase"], "prepared")
        self.assertTrue(result["prepared"]["rollbackAvailable"])
        self.assertEqual(result["waiting"]["phase"], "awaiting-confirmation")
        self.assertEqual(result["ticking"]["phase"], "rolled-back")
        self.assertEqual(result["ticking"]["error"], "confirmation-timeout")
        self.assertEqual(result["committed"]["phase"], "committed")
        self.assertFalse(result["committed"]["rollbackAvailable"])
        self.assertEqual(result["disconnected"]["phase"], "rolled-back")
        self.assertEqual(result["disconnected"]["error"], "device-disconnected")
        self.assertEqual(result["unsafe"]["phase"], "rejected")


if __name__ == "__main__":
    unittest.main()
