from __future__ import annotations

import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = ROOT / "cli" / "omanome"


class UpdateLifecycleTests(unittest.TestCase):
    def make_fixture(
        self,
        root: pathlib.Path,
        *,
        installed: bool = True,
        configured: bool = True,
    ) -> tuple[pathlib.Path, pathlib.Path]:
        config_home = root / "config"
        state_home = root / "state"
        cache_home = root / "cache"
        plugin = config_home / "omarchy" / "plugins" / "io.omanome.shell"
        if installed:
            plugin.mkdir(parents=True)
            (plugin / ".git").mkdir()
            (plugin / "manifest.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "id": "io.omanome.shell",
                        "name": "Omanome",
                        "version": "0.9.0",
                        "kinds": ["service", "bar-widget", "panel"],
                        "entryPoints": {},
                    }
                ),
                encoding="utf-8",
            )
        if configured:
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
                if [[ "$1" != "-C" ]]; then
                  printf '%s\\n' "$*" >>"${OMANOME_GIT_ARGS_LOG}"
                  printf '%s %s\\n' 'newcommit' "${2:-refs/heads/main}"
                  exit 0
                fi
                exit 1
                """
            ),
            encoding="utf-8",
        )
        (fake_bin / "curl").write_text(
            textwrap.dedent(
                """
                #!/usr/bin/env bash
                url="${@: -1}"
                case "$url" in
                  */repos/pluseight8/omanome/releases/latest) printf '%s\\n' '{"tag_name":"v1.2.0","draft":false,"prerelease":false}' ;;
                  */omanome/v1.2.0/manifest.json) printf '%s\\n' '{"version":"1.2.0"}' ;;
                  *) exit 1 ;;
                esac
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
                if [[ "$2" == "add" ]]; then
                  plugin="${XDG_CONFIG_HOME}/omarchy/plugins/io.omanome.shell"
                  mkdir -p "$plugin/.git"
                  printf '%s\n' '{"schemaVersion": 1, "id": "io.omanome.shell", "name": "Omanome", "version": "0.9.0", "kinds": ["service", "bar-widget", "panel"], "entryPoints": {}}' >"$plugin/manifest.json"
                  exit 0
                fi
                if [[ "$2" == "update" ]]; then
                  plugin="${XDG_CONFIG_HOME}/omarchy/plugins/io.omanome.shell/manifest.json"
                  sed -i 's/"version": "0.9.0"/"version": "1.2.0"/' "$plugin"
                  exit 0
                fi
                if [[ "$2" == "remove" ]]; then
                  rm -rf -- "${XDG_CONFIG_HOME}/omarchy/plugins/io.omanome.shell"
                  exit 0
                fi
                exit 0
                """
            ),
            encoding="utf-8",
        )
        (fake_bin / "omarchy-shell").write_text(
            textwrap.dedent(
                """
                #!/usr/bin/env bash
                printf '%s\n' "$*" >>"${OMANOME_SHELL_LOG}"
                exit 0
                """
            ),
            encoding="utf-8",
        )
        for path in (fake_bin / "git", fake_bin / "curl", fake_bin / "omarchy", fake_bin / "omarchy-shell"):
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(config_home),
                "XDG_STATE_HOME": str(state_home),
                "XDG_CACHE_HOME": str(cache_home),
                "OMANOME_GIT_ARGS_LOG": str(root / "git-args.log"),
                "OMANOME_SHELL_LOG": str(root / "shell.log"),
                "PATH": f"{fake_bin}:{env['PATH']}",
            }
        )
        return plugin, env

    def run_cli(self, env: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(CLI), *arguments], env=env, capture_output=True, text=True)

    def test_health_failure_restores_snapshot_and_keeps_journal_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            plugin, env = self.make_fixture(pathlib.Path(temporary))
            env["OMANOME_SIMULATE_HEALTH_FAILURE"] = "1"
            result = subprocess.run([str(CLI), "update"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 70, result.stderr)
            manifest = json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["version"], "0.9.0")
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
            self.assertEqual(manifest["version"], "1.2.0")
            history = list((pathlib.Path(temporary) / "state" / "omanome" / "transactions" / "history").glob("*.json"))
            self.assertEqual(len(history), 1)
            self.assertEqual(json.loads(history[0].read_text(encoding="utf-8"))["phase"], "committed")

    def test_stable_channel_uses_release_tag_not_main(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            _, env = self.make_fixture(root)
            result = subprocess.run([str(CLI), "update", "--check", "--json"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["channel"], "stable")
            self.assertEqual(payload["latestVersion"], "1.2.0")
            args_log = (root / "git-args.log").read_text(encoding="utf-8")
            self.assertIn("refs/tags/v1.2.0^{}", args_log)
            self.assertNotIn("refs/heads/main", args_log)

    def test_rollback_restores_pre_migration_1_1_config_without_adaptive_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            plugin, env = self.make_fixture(root)
            config_path = root / "config" / "omanome" / "config.json"
            legacy = {
                "schemaVersion": 2,
                "general": {"profile": "Tablet"},
                "multitasking": {"snapAssist": {"dwellMs": 333}},
                "input": {"nativeBackend": "native"},
                "performance": {"mode": "performance"},
                "accessibility": {"textScale": 1.25},
                "stylus": {"pressureCurve": "soft"},
                "dock": {"position": "left"},
                "overview": {"workspaceMode": "fixed"},
            }
            original = json.dumps(legacy, separators=(",", ":")) + "\n"
            config_path.write_text(original, encoding="utf-8")

            updated = self.run_cli(env, "update", "--json")
            self.assertEqual(updated.returncode, 0, updated.stderr)
            migrated = json.loads(config_path.read_text(encoding="utf-8"))
            self.assertIn("controlCenter", migrated)
            self.assertIn("adaptive", migrated)
            self.assertEqual(migrated["adaptive"]["profile"], "tablet")
            self.assertEqual(migrated["dock"]["position"], "left")
            self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["version"], "1.2.0")

            rollback = self.run_cli(env, "rollback", "--json")
            self.assertEqual(rollback.returncode, 0, rollback.stderr)
            self.assertEqual(config_path.read_text(encoding="utf-8"), original)
            restored = json.loads(config_path.read_text(encoding="utf-8"))
            self.assertNotIn("controlCenter", restored)
            self.assertNotIn("adaptive", restored)
            self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["version"], "0.9.0")

    def test_portable_install_update_reload_suspend_resume_rollback_uninstall(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            plugin, env = self.make_fixture(root, installed=False, configured=False)
            config = root / "first-run-config.json"
            config.write_text(
                json.dumps(
                    {
                        "schemaVersion": 2,
                        "general": {"mode": "tablet"},
                        "onboarding": {"completed": True, "privacyAcknowledged": True},
                        "updates": {"channel": "stable", "automaticInstall": False},
                    }
                ),
                encoding="utf-8",
            )

            setup = self.run_cli(env, "setup")
            self.assertEqual(setup.returncode, 0, setup.stderr)
            exported = self.run_cli(env, "export-config")
            self.assertEqual(exported.returncode, 0, exported.stderr)
            self.assertTrue((root / "config" / "omanome" / "config.json").is_file())

            imported = self.run_cli(env, "import-config", str(config))
            self.assertEqual(imported.returncode, 0, imported.stderr)
            imported_config = json.loads((root / "config" / "omanome" / "config.json").read_text(encoding="utf-8"))
            self.assertEqual(imported_config["general"]["mode"], "tablet")
            self.assertTrue(imported_config["onboarding"]["privacyAcknowledged"])

            installed = self.run_cli(env, "install")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertTrue(plugin.is_dir())
            self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["version"], "0.9.0")

            reloaded = self.run_cli(env, "reload")
            self.assertEqual(reloaded.returncode, 0, reloaded.stderr)
            shell_events = (root / "shell.log").read_text(encoding="utf-8").splitlines()
            self.assertTrue(any("rescanPlugins" in event for event in shell_events))

            lifecycle_expression = (
                "const L=require('./shell/models/Lifecycle.js'); "
                "let state=L.emptyState(); "
                "const suspend=L.transition(state,{event:'suspend'},100); "
                "const resume=L.transition(suspend.state,{event:'resume'},200); "
                "console.log(JSON.stringify({suspend,resume}));"
            )
            lifecycle = subprocess.run(
                [node, "-e", lifecycle_expression], cwd=ROOT, capture_output=True, text=True
            )
            self.assertEqual(lifecycle.returncode, 0, lifecycle.stderr)
            lifecycle_payload = json.loads(lifecycle.stdout)
            self.assertEqual(lifecycle_payload["suspend"]["state"]["phase"], "suspended")
            self.assertEqual(lifecycle_payload["resume"]["state"]["phase"], "active")
            self.assertEqual(lifecycle_payload["resume"]["state"]["generation"], 2)

            first_update = self.run_cli(env, "update", "--json")
            self.assertEqual(first_update.returncode, 0, first_update.stderr)
            self.assertTrue(json.loads(first_update.stdout)["updated"])
            self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["version"], "1.2.0")
            self.assertTrue(list((root / "state" / "omanome" / "rollback").iterdir()))

            rollback = self.run_cli(env, "rollback")
            self.assertEqual(rollback.returncode, 0, rollback.stderr)
            self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["version"], "0.9.0")

            second_update = self.run_cli(env, "update", "--json")
            self.assertEqual(second_update.returncode, 0, second_update.stderr)
            self.assertTrue(json.loads(second_update.stdout)["updated"])
            self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["version"], "1.2.0")

            uninstall_plan = self.run_cli(env, "uninstall", "--dry-run", "--json")
            self.assertEqual(uninstall_plan.returncode, 0, uninstall_plan.stderr)
            plan = json.loads(uninstall_plan.stdout)
            self.assertIn({"action": "stop-owned-processes", "owner": "io.omanome.shell"}, plan["actions"])

            uninstalled = self.run_cli(env, "uninstall", "--yes", "--json")
            self.assertEqual(uninstalled.returncode, 0, uninstalled.stderr)
            uninstall_payload = json.loads(uninstalled.stdout)
            self.assertTrue(uninstall_payload["removed"])
            self.assertFalse(uninstall_payload["purgeSettings"])
            self.assertFalse(plugin.exists())
            self.assertFalse((root / "state" / "omanome").exists())
            self.assertFalse((root / "cache" / "omanome").exists())
            self.assertTrue((root / "config" / "omanome" / "config.json").is_file())


if __name__ == "__main__":
    unittest.main()
