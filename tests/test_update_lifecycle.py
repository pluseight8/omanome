from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = ROOT / "cli" / "omanome"


class UpdateLifecycleTests(unittest.TestCase):
    def make_fixture(self, root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
        config_home = root / "config"
        state_home = root / "state"
        cache_home = root / "cache"
        plugin = config_home / "omarchy" / "plugins" / "io.omanome.shell"
        plugin.mkdir(parents=True)
        (plugin / ".git").mkdir()
        (plugin / "manifest.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "id": "io.omanome.shell",
                    "name": "Omanome",
                    "version": "0.6.0",
                    "kinds": ["service", "bar-widget", "panel"],
                    "entryPoints": {},
                }
            ),
            encoding="utf-8",
        )
        (config_home / "omanome").mkdir(parents=True)
        (config_home / "omanome" / "config.json").write_text(
            (ROOT / "config" / "defaults.json").read_text(encoding="utf-8"), encoding="utf-8"
        )
        fake_bin = root / "bin"
        fake_bin.mkdir()
        (fake_bin / "git").write_text(
            textwrap.dedent(
                """
                #!/usr/bin/env bash
                if [[ "$1" == "-C" && "$3" == "remote" ]]; then printf '%s\\n' 'https://github.com/pluseight8/omanome.git'; exit 0; fi
                if [[ "$1" == "-C" && "$3" == "rev-parse" ]]; then printf '%s\\n' 'oldcommit'; exit 0; fi
                if [[ "$1" != "-C" ]]; then printf '%s refs/heads/main\\n' 'newcommit'; exit 0; fi
                exit 1
                """
            ),
            encoding="utf-8",
        )
        (fake_bin / "omarchy").write_text(
            textwrap.dedent(
                """
                #!/usr/bin/env bash
                if [[ "$1" != "plugin" ]]; then exit 1; fi
                if [[ "$2" == "validate" ]]; then
                  [[ "${OMANOME_SIMULATE_HEALTH_FAILURE:-0}" != 1 ]]
                  exit $?
                fi
                if [[ "$2" == "update" ]]; then
                  plugin="${XDG_CONFIG_HOME}/omarchy/plugins/io.omanome.shell/manifest.json"
                  sed -i 's/"version": "0.6.0"/"version": "0.7.0"/' "$plugin"
                  exit 0
                fi
                exit 0
                """
            ),
            encoding="utf-8",
        )
        for path in (fake_bin / "git", fake_bin / "omarchy"):
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(config_home),
                "XDG_STATE_HOME": str(state_home),
                "XDG_CACHE_HOME": str(cache_home),
                "PATH": f"{fake_bin}:{env['PATH']}",
            }
        )
        return plugin, env

    def test_health_failure_restores_snapshot_and_keeps_journal_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            plugin, env = self.make_fixture(pathlib.Path(temporary))
            env["OMANOME_SIMULATE_HEALTH_FAILURE"] = "1"
            result = subprocess.run([str(CLI), "update"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 70, result.stderr)
            manifest = json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["version"], "0.6.0")
            history = list((pathlib.Path(temporary) / "state" / "omanome" / "transactions" / "history").glob("*.json"))
            self.assertEqual(len(history), 1)
            self.assertEqual(json.loads(history[0].read_text(encoding="utf-8"))["phase"], "rolled-back")
            self.assertFalse((pathlib.Path(temporary) / "state" / "omanome" / "transactions" / "current.json").exists())

    def test_update_commits_after_health_check(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            plugin, env = self.make_fixture(pathlib.Path(temporary))
            result = subprocess.run([str(CLI), "update", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)["updated"])
            manifest = json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["version"], "0.7.0")
            history = list((pathlib.Path(temporary) / "state" / "omanome" / "transactions" / "history").glob("*.json"))
            self.assertEqual(len(history), 1)
            self.assertEqual(json.loads(history[0].read_text(encoding="utf-8"))["phase"], "committed")


if __name__ == "__main__":
    unittest.main()
