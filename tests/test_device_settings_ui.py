from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DeviceSettingsUiTests(unittest.TestCase):
    def test_panel_exposes_device_center_without_a_second_shell(self) -> None:
        panel = (ROOT / "shell/Panel.qml").read_text(encoding="utf-8")
        self.assertIn('devices: "DeviceSettings.qml"', panel)
        self.assertIn('key: "devices"', panel)
        self.assertNotIn("Quickshell.execDetached", panel)

    def test_device_center_covers_inventory_setup_calibration_and_diagnostics(self) -> None:
        view = (ROOT / "shell/views/DeviceSettings.qml").read_text(encoding="utf-8")
        for key in ["displays", "touch", "stylus", "keyboards", "setups", "calibration", "diagnostics"]:
            self.assertIn('key: "' + key + '"', view)
        for marker in ["deviceSettingsRows", "hardwareSetupChoices", "deviceCalibrationRows", "calibrationWizardState", "Apply", "Cancel", "Unavailable", "Confirmed", "Probable", "Unknown"]:
            self.assertIn(marker, view)
        self.assertNotIn("hyprctl", view)
        self.assertNotIn("Process", view)
        self.assertNotIn("/dev/input/event", view)

    def test_service_keeps_ui_actions_inside_validated_models(self) -> None:
        service = (ROOT / "shell/Service.qml").read_text(encoding="utf-8")
        for marker in [
            '"models/Calibration.js" as CalibrationModel',
            '"models/CalibrationWizard.js" as CalibrationWizardModel',
            "property var calibrationWizardState",
            "function beginDeviceMapping",
            "function applyDeviceMapping",
            "function beginTouchCalibration",
            "function beginStylusCalibration",
            "function cancelCalibration",
            "function renameDeviceProfile",
            "function resetDeviceProfile",
            "function forgetDeviceProfile",
            "CalibrationWizardModel.beginMapping",
            "DeviceProfilesModel.setProfile",
        ]:
            self.assertIn(marker, service)

    def test_stylus_cancel_api_is_explicit_and_profile_forget_is_not_system_removal(self) -> None:
        calibration = (ROOT / "shell/models/Calibration.js").read_text(encoding="utf-8")
        profiles = (ROOT / "shell/models/DeviceProfiles.js").read_text(encoding="utf-8")
        self.assertIn("function cancelStylusCalibration", calibration)
        self.assertIn("cancelStylusCalibration: cancelStylusCalibration", calibration)
        self.assertIn("function forget(store, id)", profiles)
        self.assertIn("delete result.profiles[safe]", profiles)


if __name__ == "__main__":
    unittest.main()
