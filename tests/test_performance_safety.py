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


if __name__ == "__main__":
    unittest.main()
