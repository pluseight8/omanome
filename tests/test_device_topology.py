from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DeviceTopologyTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_hotplug_burst_is_bounded_and_coalesced_without_raw_identity(self) -> None:
        result = self.run_node(
            "const T=require('./shell/models/DeviceTopology.js'); "
            "let state=T.emptyState(); "
            "const device={type:'touchscreen',path:'/devices/pci0000:00/usb1/1-2/input/input42/event7',serial:'PRIVATE-SERIAL',capabilities:{touchscreen:true}}; "
            "state=T.noteEvent(state,{type:'device.event',action:'add',subsystem:'input',device},1000,{capabilityDebounceMs:180}); "
            "state=T.noteEvent(state,{type:'device.event',action:'change',subsystem:'input',device:{...device,capabilities:{touchscreen:true,pressure:true}}},1050,{capabilityDebounceMs:180}); "
            "console.log(JSON.stringify({state,summary:T.summary(state),publicText:JSON.stringify(T.summary(state))}));"
        )
        self.assertEqual(result["summary"]["eventCount"], 2)
        self.assertEqual(result["summary"]["coalescedEvents"], 1)
        self.assertTrue(result["summary"]["pendingRefresh"])
        self.assertEqual(result["summary"]["lastEvent"]["source"], "udev")
        self.assertGreater(result["summary"]["refreshDueAt"], 1050)
        self.assertNotIn("PRIVATE-SERIAL", result["publicText"])
        self.assertNotIn("event7", result["publicText"])
        self.assertNotIn("/devices/", result["publicText"])

    def test_display_and_invalid_events_fail_closed_but_request_one_refresh(self) -> None:
        result = self.run_node(
            "const T=require('./shell/models/DeviceTopology.js'); "
            "let display=T.normalizeEvent({type:'device.event',action:'change',subsystem:'drm',device:{name:'DP-1'}},2000); "
            "let state=T.noteEvent(T.emptyState(),{type:'device.event',action:'change',subsystem:'drm'},2000,{displayDebounceMs:260}); "
            "let invalid=T.noteEvent(state,{type:'totally.unknown'},2100); "
            "console.log(JSON.stringify({display,state,invalid,ready:T.shouldRefresh(state,2260),tooSoon:T.shouldRefresh(state,2259)}));"
        )
        self.assertEqual(result["display"]["source"], "compositor")
        self.assertTrue(result["display"]["display"])
        self.assertEqual(result["state"]["pendingReason"], "display-topology-event")
        self.assertTrue(result["state"]["pendingRefresh"])
        self.assertEqual(result["invalid"]["droppedEvents"], 1)
        self.assertFalse(result["tooSoon"])
        self.assertTrue(result["ready"])

    def test_reconcile_reports_capability_and_connection_changes_with_opaque_ids(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/DeviceGraph.js'); const T=require('./shell/models/DeviceTopology.js'); "
            "const before=G.fromSnapshot({devices:[{type:'stylus',vendorId:'1',productId:'2',path:'usb-1-2',serial:'PRIVATE',capabilities:{stylus:true,pressure:true}}]}); "
            "const after=G.fromSnapshot({devices:[{type:'stylus',vendorId:'1',productId:'2',path:'usb-1-2',serial:'PRIVATE',connected:false,capabilities:{stylus:true,tiltX:true}}]}); "
            "let state=T.noteEvent(T.emptyState(),{type:'capability.change',source:'libinput',action:'update',device:{type:'stylus',capabilities:{stylus:true,tiltX:true}}},3000); "
            "state=T.reconcile(state,before,after,3400,'capability-refresh'); "
            "console.log(JSON.stringify({delta:T.capabilityDelta(before,after),summary:T.summary(state),text:JSON.stringify(state)}));"
        )
        self.assertTrue(result["delta"]["changed"])
        self.assertEqual(len(result["delta"]["changes"]), 1)
        change = result["delta"]["changes"][0]
        self.assertIn("tilt-x", change["added"])
        self.assertIn("pressure", change["removed"])
        self.assertFalse(change["connectedAfter"])
        self.assertEqual(result["summary"]["phase"], "stable")
        self.assertEqual(result["summary"]["capabilityRevision"], 1)
        self.assertNotIn("PRIVATE", result["text"])
        self.assertNotIn("usb-1-2", result["text"])

    def test_suspend_resume_pauses_events_and_schedules_recovery_refresh(self) -> None:
        result = self.run_node(
            "const T=require('./shell/models/DeviceTopology.js'); "
            "let state=T.lifecycle(T.emptyState(),{type:'session.event',event:'suspend'},4000); "
            "let paused=T.noteEvent(state,{type:'device.event',action:'remove',subsystem:'input',device:{type:'keyboard'}},4100); "
            "let resumed=T.lifecycle(paused,{type:'session.event',event:'resume'},5000,{debounceMs:220}); "
            "console.log(JSON.stringify({state,paused,resumed,summary:T.summary(resumed)}));"
        )
        self.assertEqual(result["state"]["phase"], "paused")
        self.assertTrue(result["state"]["paused"])
        self.assertEqual(result["paused"]["phase"], "paused")
        self.assertTrue(result["paused"]["stale"])
        self.assertEqual(result["resumed"]["phase"], "resuming")
        self.assertFalse(result["resumed"]["paused"])
        self.assertTrue(result["resumed"]["pendingRefresh"])
        self.assertEqual(result["resumed"]["pendingReason"], "resume-topology-refresh")

    def test_service_wires_runtime_topology_aggregation_to_snapshot_and_events(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('"models/DeviceTopology.js" as DeviceTopologyModel', service)
        self.assertIn("property var deviceTopologyState", service)
        self.assertIn("DeviceTopologyModel.reconcile", service)
        self.assertIn("DeviceTopologyModel.noteEvent", service)
        self.assertIn("DeviceTopologyModel.lifecycle", service)
        self.assertIn("deviceTopology: DeviceTopologyModel.summary", service)
        self.assertIn("deviceRefreshDebounce.restart()", service)


if __name__ == "__main__":
    unittest.main()
