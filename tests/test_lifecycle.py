from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class LifecycleTests(unittest.TestCase):
    def test_lifecycle_transitions_are_idempotent_and_reconnect_is_bounded(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        expression = (
            "const L=require('./shell/models/Lifecycle.js'); "
            "let state=L.emptyState(); "
            "const suspend=L.transition(state,{type:'session.event',event:'suspend'},100); state=suspend.state; "
            "const duplicate=L.transition(state,{type:'session.event',event:'suspend'},200); "
            "const resume=L.transition(state,{type:'session.event',event:'resume'},300); "
            "const disconnect=L.transition(resume.state,{type:'session.event',event:'disconnect'},400); "
            "const reconnect=L.transition(disconnect.state,{type:'session.event',event:'reconnect'},500); "
            "const ignored=L.transition(reconnect.state,{type:'session.event',event:'unknown'},600); "
            "let attempts={}; const retries=[]; "
            "for(let i=0;i<4;i++){ attempts=L.reconnect(attempts, i, {maxAttempts:3,initialDelayMs:100,maxDelayMs:250}); retries.push(attempts); } "
            "console.log(JSON.stringify({suspend,duplicate,resume,disconnect,reconnect,ignored,retries}));"
        )
        result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["suspend"]["changed"])
        self.assertEqual(payload["suspend"]["state"]["phase"], "suspended")
        self.assertFalse(payload["duplicate"]["changed"])
        self.assertEqual(payload["duplicate"]["state"]["generation"], 1)
        self.assertEqual(payload["resume"]["state"]["generation"], 2)
        self.assertEqual(payload["disconnect"]["state"]["phase"], "reconnecting")
        self.assertEqual(payload["reconnect"]["state"]["phase"], "active")
        self.assertEqual(payload["reconnect"]["state"]["reconnect"]["attempts"], 0)
        self.assertFalse(payload["ignored"]["changed"])
        self.assertEqual([item["retry"] for item in payload["retries"]], [True, True, False, False])
        self.assertEqual([item["delayMs"] for item in payload["retries"]], [100, 200, 250, 250])

    def test_service_has_explicit_teardown_and_stale_registry_boundary(self) -> None:
        service = (ROOT / "shell" / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("property bool shuttingDown: false", service)
        self.assertIn("function shutdown()", service)
        self.assertIn("Component.onDestruction: root.shutdown()", service)
        self.assertIn("if (root.shuttingDown) return false", service)
        self.assertIn("registryShellPid", service)
        self.assertIn("sameShell", service)
        self.assertIn("root.ownedProcesses = []", service)
        self.assertIn("root.pendingCommands = ({})", service)
        self.assertIn("function resetTransientState(reason)", service)
        self.assertIn('root.releaseLivePreviews("config-reset")', service)
        self.assertIn('root.configLoadStatus = "ok"', service)
        self.assertIn("root.loadLayoutPersistence()", service)
        self.assertIn("root.enableEnhancements()", service)
        self.assertIn('String(root.splitViewState.phase || "")', service)

    def test_transient_reset_stops_replay_timers_and_cancels_active_calibration(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        start = service.index("function resetTransientState")
        end = service.index("\n  function modeTransitionSummary", start)
        body = service[start:end]
        for marker in (
            "deviceRefreshDebounce", "keyboardTransitionTimer", "dockedModeTimer",
            "clipboardRestart", "inputBackendRestart", "oskPolicyTimer",
            "calibrationTransactionTimer", "multitaskingLaunchTimeout",
        ):
            self.assertIn(marker, body)
        self.assertIn("root.rollbackCalibrationTransaction(why)", body)
        self.assertIn('root.cancelCalibration("touchscreen", why)', body)
        self.assertIn('root.cancelCalibration("stylus", why)', body)
        self.assertIn("CalibrationWizardModel.cancel", body)

    def test_session_suspend_releases_previews_before_recovery(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        start = service.index("function updateSessionEvent")
        end = service.index("\n  function updateMonitors", start)
        body = service[start:end]
        self.assertIn('root.releaseLivePreviews("session-suspended")', body)
        self.assertIn('root.resetTransientState("session-suspended")', body)
        self.assertIn('root.stopNativeInputBackend("suspended")', body)


if __name__ == "__main__":
    unittest.main()
