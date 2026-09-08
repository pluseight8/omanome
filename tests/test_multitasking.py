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

    def test_split_divider_is_touch_sized_and_updates_both_slots(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SplitView.js'); "
            "let state=S.createState({name:'wide',x:0,y:0,width:1920,height:1080},['a','b'],{gap:20,ratio:'50/50'}); "
            "const handle=S.dividerGeometry(state.pair,{dividerHandleSize:56}); "
            "state=S.beginDividerDrag(state,{x:handle.center,y:540},{now:100}); "
            "state=S.updateDividerDrag(state,{x:1400,y:540},{now:140}); "
            "const committed=S.commit(state,{ok:true}); "
            "console.log(JSON.stringify({axis:handle.axis,handle:handle.rect,ratio:committed.pair.ratio,first:committed.pair.slots[0].rect,second:committed.pair.slots[1].rect,phase:committed.state.phase}));"
        )
        self.assertEqual(result["axis"], "vertical")
        self.assertGreaterEqual(result["handle"]["width"], 48)
        self.assertGreater(result["ratio"], 0.6)
        self.assertGreater(result["second"]["x"], result["first"]["x"] + result["first"]["width"])
        self.assertEqual(result["phase"], "committed")

    def test_portrait_divider_rotates_to_horizontal_and_preserves_logical_ratio(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SplitView.js'); "
            "let state=S.createState({name:'tablet',width:1080,height:1920},['one','two'],{ratio:'33/67',gap:12}); "
            "const portrait=S.dividerGeometry(state.pair,{}); "
            "const rotated=S.rotate(state,{name:'tablet',width:1920,height:1080},{gap:12}); "
            "console.log(JSON.stringify({portraitAxis:portrait.axis,portraitRatio:state.ratio,rotatedAxis:rotated.pair.axis,rotatedRatio:rotated.ratio,ids:rotated.pair.slots.map(x=>x.windowId)}));"
        )
        self.assertEqual(result["portraitAxis"], "horizontal")
        self.assertAlmostEqual(result["portraitRatio"], 1 / 3)
        self.assertEqual(result["rotatedAxis"], "vertical")
        self.assertAlmostEqual(result["rotatedRatio"], 1 / 3)
        self.assertEqual(result["ids"], ["one", "two"])

    def test_split_transaction_rolls_back_when_second_window_apply_fails(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SplitView.js'); "
            "let state=S.createState({name:'main',width:1600,height:1000},['a','b'],{ratio:'50/50'}); "
            "const baseline=state.pair.slots.map(x=>x.rect); "
            "state=S.beginDividerDrag(state,{x:S.dividerGeometry(state.pair,{}).center,y:500},{}); "
            "state=S.updateDividerDrag(state,{x:1200,y:500},{}); "
            "const failed=S.commit(state,{ok:false,reason:'second-window-failed'}); "
            "console.log(JSON.stringify({ok:failed.ok,rolledBack:failed.rolledBack,reason:failed.reason,same:JSON.stringify(failed.pair.slots.map(x=>x.rect))===JSON.stringify(baseline),phase:failed.state.phase}));"
        )
        self.assertFalse(result["ok"])
        self.assertTrue(result["rolledBack"])
        self.assertEqual(result["reason"], "second-window-failed")
        self.assertTrue(result["same"])
        self.assertEqual(result["phase"], "rolled-back")

    def test_initial_split_apply_uses_the_same_transaction_boundary(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SplitView.js'); "
            "let state=S.createState({name:'main',width:1600,height:1000},['a','b'],{ratio:'50/50'}); "
            "state=S.beginApply(state,{}); const committed=S.commit(state,{ok:true}); "
            "console.log(JSON.stringify({phase:state.phase,status:state.transaction.status,ok:committed.ok,final:committed.state.phase,ids:committed.pair.slots.map(x=>x.windowId)}));"
        )
        self.assertEqual(result["phase"], "applying")
        self.assertEqual(result["status"], "active")
        self.assertTrue(result["ok"])
        self.assertEqual(result["final"], "committed")
        self.assertEqual(result["ids"], ["a", "b"])

    def test_divider_autohide_is_event_driven_and_input_proximity_reveals_it(self) -> None:
        result = self.run_node(
            "const S=require('./shell/models/SplitView.js'); "
            "let state=S.createState({name:'main',width:1600,height:1000},['a','b'],{dividerAutoHideMs:1000}); "
            "state=S.notifyDividerInteraction(state,'touch',100); state=S.setDividerProximity(state,false,100); "
            "const hidden=S.dividerVisibility(state,1200,{}); "
            "const shown=S.dividerVisibility(S.notifyDividerInteraction(hidden,'stylus',1300),1300,{}); "
            "console.log(JSON.stringify({hidden:hidden.divider,shown:shown.divider}));"
        )
        self.assertFalse(result["hidden"]["visible"])
        self.assertLess(result["hidden"]["opacity"], 0.2)
        self.assertTrue(result["shown"]["visible"])
        self.assertEqual(result["shown"]["lastInputKind"], "stylus")

    def test_launch_matching_excludes_existing_windows_and_does_not_use_title(self) -> None:
        result = self.run_node(
            "const M=require('./shell/models/WindowMatcher.js'); "
            "const existing=[{address:'0x1',pid:41,appId:'org.browser.App',title:'Old'}]; "
            "let request=M.begin('org.browser.App',existing,1000,{timeoutMs:999999}); "
            "const titleOnly=M.matchWindow(request,[{title:'New tab',appId:'org.browser.App'}],1100); "
            "const newWindow=M.matchWindow(request,[{address:'0x2',pid:42,appId:'org.browser.App',title:'New tab',launchTimestamp:1050}],1100); "
            "const oldWindow=M.matchWindow(request,existing,1100); "
            "console.log(JSON.stringify({timeout:request.timeoutMs,titleOnly,newWindow,oldWindow}));"
        )
        self.assertEqual(result["timeout"], 15000)
        self.assertEqual(result["titleOnly"]["status"], "pending")
        self.assertTrue(result["newWindow"]["ok"])
        self.assertEqual(result["newWindow"]["windowId"], "address:0x2")
        self.assertEqual(result["oldWindow"]["status"], "pending")

    def test_launch_matching_prefers_pid_and_is_bounded_by_deadline(self) -> None:
        result = self.run_node(
            "const M=require('./shell/models/WindowMatcher.js'); "
            "let request=M.begin('org.editor.App',[],1000,{timeoutMs:5000,expectedPid:77}); "
            "const rows=[{address:'0xa',pid:78,appId:'org.editor.App',launchTimestamp:1100},{address:'0xb',pid:77,appId:'org.editor.App',launchTimestamp:1100}]; "
            "const chosen=M.resolve(request,rows,1200); const expired=M.resolve(request,rows,7000); "
            "console.log(JSON.stringify({chosen,expired}));"
        )
        self.assertTrue(result["chosen"]["result"]["ok"])
        self.assertEqual(result["chosen"]["result"]["windowId"], "address:0xb")
        self.assertEqual(result["expired"]["result"]["status"], "timeout")
        self.assertEqual(result["expired"]["request"]["reason"], "launch-timeout")

    def test_window_group_snapshot_keeps_app_layout_and_drops_runtime_identity(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/WindowGroups.js'); "
            "const created=G.createGroup('app-pair',[{address:'0x1',pid:11,appId:'org.browser.App',title:'Private tab',workspace:2,monitorName:'tablet'},{address:'0x2',pid:12,appId:'org.chat.App',title:'Secret chat',workspace:2,monitorName:'tablet'}],{now:1234,ratio:'40/60',monitorPolicy:'original'},1234); "
            "const raw=JSON.stringify(created.metadata); console.log(JSON.stringify({ok:created.ok,apps:created.metadata.apps,ratio:created.metadata.layout.ratio,hasAddress:raw.indexOf('0x1')>=0,hasPid:raw.indexOf('11')>=0,hasTitle:raw.indexOf('Private')>=0,roundTrip:G.restore(G.serialize([created.group])).groups}));"
        )
        self.assertTrue(result["ok"])
        self.assertEqual(result["apps"], ["org.browser.App", "org.chat.App"])
        self.assertEqual(result["ratio"], "40/60")
        self.assertFalse(result["hasAddress"])
        self.assertFalse(result["hasPid"])
        self.assertFalse(result["hasTitle"])
        self.assertEqual(result["roundTrip"][0]["apps"], result["apps"])
        self.assertNotIn("runtime", result["roundTrip"][0])

    def test_window_group_reconcile_requires_choice_for_duplicate_app_windows(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/WindowGroups.js'); "
            "const pair=G.createGroup('app-pair',[],{apps:['org.browser.App','org.chat.App'],id:'pair-1'},100); "
            "const duplicate=G.reconcileGroup(pair.group,[{address:'0xa',pid:20,appId:'org.browser.App'},{address:'0xb',pid:21,appId:'org.browser.App'},{address:'0xc',pid:22,appId:'org.chat.App'}],200,{}); "
            "const unique=G.reconcileGroup(pair.group,[{address:'0xa',pid:20,appId:'org.browser.App'},{address:'0xc',pid:22,appId:'org.chat.App'}],200,{}); "
            "console.log(JSON.stringify({created:pair.ok,duplicate:duplicate.status,ambiguous:duplicate.ambiguous,unique:unique.status,bound:unique.bound.map(x=>x.identity)}));"
        )
        self.assertTrue(result["created"])
        self.assertEqual(result["duplicate"], "ambiguous")
        self.assertEqual(result["ambiguous"][0]["appId"], "org.browser.App")
        self.assertEqual(result["unique"], "active")
        self.assertEqual(result["bound"], ["address:0xa", "address:0xc"])

    def test_split_group_breaks_on_closed_member_and_move_plan_is_bounded(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/WindowGroups.js'); "
            "const pair=G.createGroup('split-pair',[{address:'0x1',pid:31,appId:'org.editor.App'},{address:'0x2',pid:32,appId:'org.files.App'}],{id:'split-1',closePolicy:'expand'},300); "
            "const state=G.reconcileGroup(pair.group,[{address:'0x1',pid:31,appId:'org.editor.App'}],400,{}); "
            "const plan=G.movePlan(pair.group,'workspace-3','HDMI-A-1'); const detached=G.detachMember(pair.group,'address:0x2','window-closed'); "
            "console.log(JSON.stringify({status:state.status,event:state.event,plan,broken:detached.broken,remaining:detached.remaining.map(x=>x.identity)}));"
        )
        self.assertEqual(result["status"], "broken")
        self.assertEqual(result["event"]["reason"], "member-closed")
        self.assertEqual(result["event"]["closePolicy"], "expand")
        self.assertEqual(result["plan"]["memberIds"], ["address:0x1", "address:0x2"])
        self.assertEqual(result["plan"]["workspaceId"], "workspace-3")
        self.assertTrue(result["broken"])
        self.assertEqual(result["remaining"], ["address:0x1"])

    def test_session_restore_policy_never_auto_launches_for_off_or_ask(self) -> None:
        result = self.run_node(
            "const G=require('./shell/models/WindowGroups.js'); "
            "const pair=G.createGroup('app-pair',[],{apps:['org.one.App','org.two.App'],id:'pair-restore'},500); "
            "const off=G.restorePlan([pair.group],[], 'off', 600, {}); const ask=G.restorePlan([pair.group],[], 'ask', 600, {}); const automatic=G.restorePlan([pair.group],[], 'automatic', 600, {}); "
            "console.log(JSON.stringify({off:off.decision,ask:ask.decision,automatic:automatic.decision,offPlan:off.plans[0],askPlan:ask.plans[0],autoPlan:automatic.plans[0]}));"
        )
        self.assertFalse(result["off"]["allowed"])
        self.assertFalse(result["off"]["autoLaunch"])
        self.assertEqual(result["offPlan"]["status"], "skipped")
        self.assertTrue(result["ask"]["requiresConfirmation"])
        self.assertFalse(result["ask"]["autoLaunch"])
        self.assertEqual(result["askPlan"]["status"], "awaiting-confirmation")
        self.assertTrue(result["automatic"]["allowed"])
        self.assertTrue(result["automatic"]["autoLaunch"])
        self.assertEqual(result["autoPlan"]["status"], "ready")

    def test_floating_plans_are_address_scoped_and_geometry_stays_on_monitor(self) -> None:
        result = self.run_node(
            "const F=require('./shell/models/FloatingWindows.js'); "
            "const monitor={name:'tablet',x:0,y:0,width:1080,height:1920,usable:{x:0,y:48,width:1080,height:1780}}; "
            "const mini=F.mini({address:'0xabc',pid:77,appId:'org.video.App',title:'Private'},monitor,{gap:16}); "
            "const pip=F.pip({address:'0xabc',pid:77,appId:'org.video.App'},monitor,{corner:'top-left',pipSize:{width:420,height:300}}); "
            "const invalid=F.mini({pid:77,appId:'org.video.App'},monitor,{}); "
            "console.log(JSON.stringify({mini,pip,invalid}));"
        )
        self.assertTrue(result["mini"]["ok"])
        self.assertTrue(all("address:0xabc" in command for command in result["mini"]["commands"]))
        self.assertGreaterEqual(result["mini"]["target"]["x"], 0)
        self.assertGreaterEqual(result["mini"]["target"]["y"], 48)
        self.assertLessEqual(result["mini"]["target"]["x"] + result["mini"]["target"]["width"], 1080)
        self.assertIn("pin address:0xabc", result["pip"]["commands"])
        self.assertEqual(result["invalid"]["reason"], "window-address-required")

    def test_floating_persistent_position_uses_app_metadata_not_runtime_identity(self) -> None:
        result = self.run_node(
            "const F=require('./shell/models/FloatingWindows.js'); "
            "const saved=F.persistablePosition({address:'0xdead',pid:99,appId:'org.editor.App',title:'Sensitive'}, {name:'HDMI-A-1',x:100,y:40,width:1920,height:1080},{x:1100,y:140,width:640,height:480}); "
            "console.log(JSON.stringify(saved));"
        )
        self.assertEqual(result["appId"], "org.editor.App")
        self.assertEqual(result["monitor"], "HDMI-A-1")
        self.assertNotIn("address", result)
        self.assertNotIn("pid", result)
        self.assertNotIn("title", result)
        self.assertGreaterEqual(result["x"], 0)
        self.assertLessEqual(result["x"], 1)


if __name__ == "__main__":
    unittest.main()
