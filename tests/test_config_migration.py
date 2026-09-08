from __future__ import annotations

import copy
import json
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG_TOOL = ROOT / "scripts" / "config_tool.py"
DEFAULTS = json.loads((ROOT / "config" / "defaults.json").read_text(encoding="utf-8"))


class ConfigMigrationTests(unittest.TestCase):
    def run_tool(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CONFIG_TOOL), *arguments],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def legacy_1_1_config(self) -> dict[str, object]:
        value = copy.deepcopy(DEFAULTS)
        value.pop("controlCenter", None)
        value.pop("adaptive", None)
        value["general"]["profile"] = "Tablet"
        value["multitasking"]["snapAssist"]["dwellMs"] = 333
        value["input"]["nativeBackend"] = "native"
        value["performance"]["mode"] = "performance"
        value["accessibility"]["textScale"] = 1.25
        value["stylus"]["pressureCurve"] = "soft"
        value["dock"]["position"] = "left"
        value["overview"]["workspaceMode"] = "fixed"
        return value

    def test_1_1_to_1_2_migration_preserves_existing_feature_intent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "omanome-1.1.json"
            output = root / "omanome-1.2.json"
            source.write_text(json.dumps(self.legacy_1_1_config()), encoding="utf-8")

            result = self.run_tool("migrate", str(source), "--output", str(output), "--json")

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            migrated = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["schemaVersion"], 2)
            self.assertEqual(report["migration"]["from"], 2)
            self.assertIn("adaptive-1.2-defaults", report["migration"]["applied"])
            self.assertIn("controlCenter", migrated)
            self.assertIn("adaptive", migrated)
            self.assertEqual(migrated["adaptive"]["profile"], "tablet")
            self.assertEqual(migrated["multitasking"]["snapAssist"]["dwellMs"], 333)
            self.assertEqual(migrated["input"]["nativeBackend"], "native")
            self.assertEqual(migrated["performance"]["mode"], "performance")
            self.assertEqual(migrated["accessibility"]["textScale"], 1.25)
            self.assertEqual(migrated["stylus"]["pressureCurve"], "soft")
            self.assertEqual(migrated["dock"]["position"], "left")
            self.assertEqual(migrated["overview"]["workspaceMode"], "fixed")
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_repository_validator_requires_new_adaptive_sections(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "validate.py")],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("schemaVersion 2", result.stdout)


if __name__ == "__main__":
    unittest.main()
