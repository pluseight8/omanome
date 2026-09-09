from __future__ import annotations

import copy
import json
import pathlib
import shutil
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

    def test_1_2_to_1_3_additive_migration_preserves_hardware_and_user_intent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "omanome-1.2.json"
            output = root / "omanome-1.3.json"
            legacy = copy.deepcopy(DEFAULTS)
            legacy.pop("deviceProfiles")
            legacy.pop("hardwareSetupProfiles")
            legacy["adaptive"]["profile"] = "tablet"
            legacy["multitasking"]["layoutPersistence"]["maxRecent"] = 3
            legacy["input"]["nativeBackend"] = "native"
            legacy["stylus"]["pressureCurve"] = "soft"
            legacy["performance"]["mode"] = "performance"
            legacy["accessibility"]["textScale"] = 1.35
            source.write_text(json.dumps(legacy), encoding="utf-8")

            result = self.run_tool("migrate", str(source), "--output", str(output), "--json")

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            migrated = json.loads(output.read_text(encoding="utf-8"))
            migration = report["migration"]
            self.assertEqual(migration["releaseFrom"], "1.2.0")
            self.assertEqual(migration["releaseTo"], "1.3.0")
            self.assertIn("device-intelligence-1.3-defaults", migration["applied"])
            self.assertEqual(migrated["adaptive"]["profile"], "tablet")
            self.assertEqual(migrated["multitasking"]["layoutPersistence"]["maxRecent"], 3)
            self.assertEqual(migrated["input"]["nativeBackend"], "native")
            self.assertEqual(migrated["stylus"]["pressureCurve"], "soft")
            self.assertEqual(migrated["performance"]["mode"], "performance")
            self.assertEqual(migrated["accessibility"]["textScale"], 1.35)
            self.assertEqual(migrated["deviceProfiles"]["schemaVersion"], 2)
            self.assertEqual(migrated["hardwareSetupProfiles"]["schemaVersion"], 1)

    def test_future_nested_device_schema_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            source = root / "future.json"
            output = root / "output.json"
            original = {"schemaVersion": 2, "deviceProfiles": {"schemaVersion": 99, "profiles": {"future": True}}}
            source.write_text(json.dumps(original), encoding="utf-8")

            result = self.run_tool("migrate", str(source), "--output", str(output), "--json")

            self.assertEqual(result.returncode, 78)
            self.assertEqual(json.loads(result.stdout)["reason"], "future-device-profile-schema")
            self.assertFalse(output.exists())
            self.assertEqual(json.loads(source.read_text(encoding="utf-8")), original)

    def test_qml_migration_reports_release_and_rejects_future_nested_schema(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run(
            [node, "-e", "const C=require('./shell/models/Config.js'); console.log(JSON.stringify({ok:C.migrateDetailed({schemaVersion:2,adaptive:{profile:'tablet'}}),future:C.migrateDetailed({schemaVersion:2,deviceProfiles:{schemaVersion:99}})}));"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["ok"]["releaseFrom"], "1.2.0")
        self.assertEqual(payload["ok"]["releaseTo"], "1.3.0")
        self.assertEqual(payload["future"]["reason"], "future-device-profile-schema")


if __name__ == "__main__":
    unittest.main()
