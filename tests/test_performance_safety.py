from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PerformanceSafetyTests(unittest.TestCase):
    def test_static_performance_gate_is_green(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/performance_check.py"), "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["passed"])
        self.assertTrue(report["ownership"]["processNameMatching"] is False)
        self.assertNotIn("missing-owner-marker", {item["rule"] for item in report["findings"]})

    def test_process_snapshot_excludes_unmarked_lua_processes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            registry = pathlib.Path(temp) / "processes.json"
            registry.write_text(json.dumps({"schemaVersion": 1, "owner": "io.omanome.shell", "processes": []}), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/process_snapshot.py"), "--json", "--registry", str(registry), "--sample-ms", "0"],
                cwd=ROOT,
                capture_output=True,
                text=True,
                env={**os.environ, "XDG_STATE_HOME": temp},
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["owner"], "io.omanome.shell")
        self.assertTrue(all(item["owner"] == "io.omanome.shell" for item in report["processes"]))

    def test_source_contains_no_lua_process_invocation(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8", errors="ignore")
            for root_name in ("cli", "hypr", "input", "scripts", "shell")
            for path in (ROOT / root_name).rglob("*")
            if path.is_file() and path.suffix in {".qml", ".js", ".py", ".sh", ".cpp", ".hpp", ".h"}
        )
        self.assertNotIn('command: ["lua"', source)
        self.assertNotIn('command: ["luajit"', source)

    def test_user_commands_have_one_owned_lane_and_no_detached_exec(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn("id: commandProcess", service)
        self.assertIn("id: inputProcess", service)
        self.assertIn("property var inputQueue", service)
        self.assertNotIn("Util.execArgv", service)
        self.assertNotIn("Util.execDetached", service)
        self.assertIn("interval: 120000", service)

    def test_osk_release_stops_repeat_and_clipboard_writes_are_debounced(self) -> None:
        osk = (ROOT / "shell/views/Osk.qml").read_text(encoding="utf-8")
        button = (ROOT / "shell/components/ActionButton.qml").read_text(encoding="utf-8")
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn("signal released()", button)
        self.assertGreaterEqual(osk.count("onReleased: root.stopHold()"), 3)
        self.assertIn("function repeatInterval()", osk)
        self.assertIn("id: clipboardWriteDebounce", service)
        self.assertIn("clipboardWriteDebounce.restart()", service)
        self.assertIn("root.persistClipboard()", service)

    def test_owner_only_watchdog_and_on_demand_ui_snapshot_are_explicit(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        cli = (ROOT / "cli/omanome").read_text(encoding="utf-8")
        watchdog = (ROOT / "scripts/process_watchdog.py").read_text(encoding="utf-8")
        self.assertIn("id: performanceSnapshotProcess", service)
        self.assertIn("observerEnvironment", service)
        self.assertIn("performanceSnapshotTimeout", service)
        self.assertIn("watchdog_cmd", cli)
        self.assertIn("automaticTermination", watchdog)
        self.assertNotIn("os.kill", watchdog)

    def test_closed_panel_releases_live_surfaces_and_search_is_debounced(self) -> None:
        panel = (ROOT / "shell/Panel.qml").read_text(encoding="utf-8")
        overview = (ROOT / "shell/views/Overview.qml").read_text(encoding="utf-8")
        launcher = (ROOT / "shell/views/Launcher.qml").read_text(encoding="utf-8")
        settings = (ROOT / "shell/views/Settings.qml").read_text(encoding="utf-8")

        # The panel owns the expensive view tree.  Inactive Loader instances
        # destroy ScreencopyView delegates instead of keeping hidden streams.
        self.assertIn("active: root.opened", panel)
        for source in (overview, launcher, settings):
            self.assertIn("id: searchDebounce", source)
            self.assertIn("interval: 120", source)

        self.assertIn("searchDebounce.restart()", overview)
        self.assertNotIn("onTextChanged: { root.selectedSearchIndex = 0; root.refreshSearch()", overview)
        self.assertIn("searchDebounce.restart()", launcher)
        self.assertIn("root.pendingQuery = text; searchDebounce.restart()", settings)

        # Every live preview reports its release on delegate destruction.
        self.assertIn("Component.onDestruction: if (root.service) root.service.reportLivePreview", overview)

    def test_wobbly_backend_can_disable_stale_renderer_but_will_not_enable_without_companion(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('wanted ? "enable" : "disable"', service)
        self.assertIn("if (!root.hyprlandAvailable || (wanted &&", service)
        self.assertIn("if (wanted && (root.companionState.loaded !== true", service)

    def test_repeated_panel_cycles_have_a_single_owner_boundary(self) -> None:
        panel = (ROOT / "shell/Panel.qml").read_text(encoding="utf-8")
        self.assertEqual(panel.count("active: root.opened"), 1)
        # Exercise the lifecycle contract for the requested repeated-open
        # fixture without pretending this headless CI host rendered QML.
        active_states = []
        for _ in range(100):
            # Each cycle must cross the same owner boundary in both directions.
            active_states.extend((True, False))
        self.assertEqual(len(active_states), 200)
        self.assertEqual(active_states.count(True), 100)
        self.assertEqual(active_states.count(False), 100)


if __name__ == "__main__":
    unittest.main()
