from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DeviceProfileTests(unittest.TestCase):
    def run_node(self, expression: str) -> object:
        node = shutil.which("node")
        if not node:
            self.skipTest("node is not installed")
        result = subprocess.run([node, "-e", expression], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_profiles_are_whitelisted_and_do_not_persist_ephemeral_or_raw_ids(self) -> None:
        result = self.run_node(
            "const P=require('./shell/models/DeviceProfiles.js'); "
            "const id='device:stylus:0123456789abcdef'; "
            "const profile=P.normalizeProfile({id,category:'stylus',name:'Desk pen',unknown:'drop',stylus:{pressureCurve:'firm',pressureMin:-1,pressureMax:4,buttonTest:true,calibrationId:'event7'}}); "
            "const raw=P.normalizeProfile({id:'/dev/input/event7',category:'stylus'}); "
            "console.log(JSON.stringify({profile,raw,text:JSON.stringify(profile)}));"
        )
        self.assertIsNotNone(result["profile"])
        self.assertIsNone(result["raw"])
        self.assertEqual(result["profile"]["stylus"]["pressureCurve"], "firm")
        self.assertEqual(result["profile"]["stylus"]["pressureMin"], 0)
        self.assertEqual(result["profile"]["stylus"]["pressureMax"], 1)
        self.assertFalse(result["profile"]["stylus"]["buttonTest"])
        self.assertNotIn("unknown", result["text"])
        self.assertNotIn("event7", result["text"])

    def test_direct_profile_wins_over_generic_rule_and_default_is_safe(self) -> None:
        result = self.run_node(
            "const P=require('./shell/models/DeviceProfiles.js'); "
            "const stylus='device:stylus:1111111111111111'; const keyboard='device:keyboard:2222222222222222'; "
            "let store=P.emptyStore(); "
            "store=P.setProfile(store,{id:stylus,category:'stylus',name:'Pen',stylus:{pressureCurve:'soft'}}).store; "
            "store=P.setProfile(store,{id:keyboard,category:'keyboard',keyboard:{layout:'ru',oskPolicy:'hide'}}).store; "
            "const rule=P.setRule(store,{match:{category:'stylus',transport:'usb'},profileId:keyboard}); store=rule.store; "
            "console.log(JSON.stringify({direct:P.effective({id:stylus,category:'stylus',transport:'usb'},store),rule:P.effective({id:'device:stylus:3333333333333333',category:'stylus',transport:'usb'},store),fallback:P.effective({id:'device:mouse:4444444444444444',category:'mouse'},store),ruleOk:rule.ok}));"
        )
        self.assertTrue(result["ruleOk"])
        self.assertEqual(result["direct"]["source"], "device")
        self.assertEqual(result["direct"]["profile"]["stylus"]["pressureCurve"], "soft")
        self.assertEqual(result["rule"]["source"], "rule")
        self.assertEqual(result["rule"]["profile"]["keyboard"]["oskPolicy"], "hide")
        self.assertEqual(result["fallback"]["source"], "default")
        self.assertEqual(result["fallback"]["profile"]["category"], "mouse")

    def test_profile_lifecycle_keeps_id_and_removes_rules_on_forget(self) -> None:
        result = self.run_node(
            "const P=require('./shell/models/DeviceProfiles.js'); const id='display:abcdefabcdefabcd'; "
            "let store=P.emptyStore(); store=P.setProfile(store,{id,category:'display',name:'Studio'}).store; "
            "const renamed=P.rename(store,id,'Work display'); store=renamed.store; "
            "const rule=P.setRule(store,{category:'display',profileId:id}); store=rule.store; "
            "const forgotten=P.forget(store,id); const reset=P.reset(store,id); "
            "console.log(JSON.stringify({renamed:renamed.ok,name:store.profiles[id].name,rules:store.rules.length,forgotten:forgotten.store,reset:reset.store}));"
        )
        self.assertTrue(result["renamed"])
        self.assertEqual(result["name"], "Work display")
        self.assertEqual(result["rules"], 1)
        self.assertEqual(result["forgotten"]["profiles"], {})
        self.assertEqual(result["forgotten"]["rules"], [])
        self.assertEqual(result["reset"]["profiles"], {})

    def test_config_defaults_and_migration_keep_device_profiles_separate_from_adaptive(self) -> None:
        result = self.run_node(
            "const C=require('./shell/models/Config.js'); const fresh=C.defaults(); "
            "const migrated=C.migrateDetailed({schemaVersion:2,adaptive:{profile:'tablet'},general:{profile:'Tablet'}}); "
            "console.log(JSON.stringify({fresh:fresh.deviceProfiles,adaptive:migrated.config.adaptive.profile,profiles:migrated.config.deviceProfiles,applied:migrated.applied}));"
        )
        self.assertEqual(result["fresh"]["schemaVersion"], 2)
        self.assertTrue(result["fresh"]["enabled"])
        self.assertEqual(result["adaptive"], "tablet")
        self.assertEqual(result["profiles"]["profiles"], {})
        self.assertIn("device-profiles-2.0-defaults", result["applied"])
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        self.assertIn("deviceProfiles", defaults)
        self.assertEqual(schema["properties"]["deviceProfiles"]["properties"]["schemaVersion"]["const"], 2)

    def test_service_keeps_profile_store_separate_and_normalizes_config_updates(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        self.assertIn('"models/DeviceProfiles.js" as DeviceProfilesModel', service)
        self.assertIn("property var deviceProfileStore: DeviceProfilesModel.emptyStore()", service)
        self.assertIn("DeviceProfilesModel.normalizeStore", service)
        self.assertIn("DeviceProfilesModel.list(root.deviceGraph, root.deviceProfileStore)", service)
        self.assertIn("deviceProfiles: DeviceProfilesModel.summary(root.deviceProfileStore)", service)


if __name__ == "__main__":
    unittest.main()
