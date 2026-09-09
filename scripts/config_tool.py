#!/usr/bin/env python3
"""Safe, dependency-free Omanome configuration operations.

The graphical service and the CLI deliberately share the same migration
contract.  This helper is used for validation/import/export/diff operations;
it never replaces a future-schema file with defaults and all writes are
atomic, mode 0600, and refused when the destination is a symlink.
"""

from __future__ import annotations

import argparse
import copy
import difflib
import json
import math
import os
import pathlib
import re
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULTS_PATH = ROOT / "config" / "defaults.json"
CURRENT_SCHEMA_VERSION = 2
CURRENT_RELEASE = "1.3.0"
MIGRATION_SOURCE_RELEASE = "1.2.0"
DEVICE_PROFILE_SCHEMA_VERSION = 2
HARDWARE_SETUP_SCHEMA_VERSION = 1
GRAPH_ID_RE = re.compile(r"(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})")
CALIBRATION_KINDS = {"touchscreen", "stylus"}
SETUP_IDS = ("auto", "tablet", "desk", "portable", "travel", "presentation", "drawing", "custom")
EX_USAGE = 2
EX_CONFIG = 78
EX_NOINPUT = 66
EX_CANTCREAT = 73
LKG_SUFFIX = ".lkg"
CORRUPT_SUFFIX = ".corrupt"


class ConfigError(Exception):
    def __init__(self, reason: str, message: str | None = None) -> None:
        self.reason = reason
        super().__init__(message or reason)


def load_defaults() -> dict[str, Any]:
    try:
        value = json.loads(DEFAULTS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:  # pragma: no cover - repository failure
        raise ConfigError("defaults-unavailable", str(exc)) from exc
    if not isinstance(value, dict):
        raise ConfigError("defaults-invalid", "config/defaults.json must contain an object")
    return value


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(result.get(key), dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def migration_zero_to_one(source: dict[str, Any], applied: list[str]) -> None:
    if isinstance(source.get("tablet"), dict) and "tabletMode" not in source:
        source["tabletMode"] = copy.deepcopy(source["tablet"])
    if isinstance(source.get("osk"), dict) and "keyboard" not in source:
        source["keyboard"] = copy.deepcopy(source["osk"])
    if "onboarding" not in source:
        source["onboarding"] = {
            "completed": True,
            "skipped": True,
            "version": 1,
            "privacyAcknowledged": False,
        }
    source["schemaVersion"] = 1
    applied.append("0->1")


def migration_one_to_two(source: dict[str, Any], applied: list[str]) -> None:
    source.setdefault(
        "onboarding",
        {"completed": True, "skipped": True, "version": 1, "privacyAcknowledged": False},
    )
    updates = source.setdefault("updates", {})
    if not isinstance(updates, dict):
        updates = source["updates"] = {}
    updates.setdefault("channel", "stable")
    updates.setdefault("automaticInstall", False)
    updates.setdefault("notify", True)
    updates.setdefault("rollbackRetention", 3)
    updates.setdefault("checkTimeoutSeconds", 8)
    updates.setdefault("healthTimeoutSeconds", 5)

    recovery = source.setdefault("recovery", {})
    if not isinstance(recovery, dict):
        recovery = source["recovery"] = {}
    recovery.setdefault("autoRollback", True)
    recovery.setdefault("safeModeOnCrash", True)
    recovery.setdefault("maxCrashAttempts", 2)
    recovery.setdefault("preserveFailedUpdates", True)

    diagnostics = source.setdefault("diagnostics", {})
    if not isinstance(diagnostics, dict):
        diagnostics = source["diagnostics"] = {}
    diagnostics.setdefault("logLevel", "info")
    diagnostics.setdefault("supportBundleRetention", 3)
    diagnostics.setdefault("redactPaths", True)
    diagnostics.setdefault("includeSystemCommands", True)
    source["schemaVersion"] = CURRENT_SCHEMA_VERSION
    applied.append("1->2")


def migration_multitasking_1_1(source: dict[str, Any], applied: list[str]) -> None:
    defaults = load_defaults().get("multitasking", {})
    multitasking = source.setdefault("multitasking", {})
    if not isinstance(multitasking, dict):
        multitasking = source["multitasking"] = {}
    changed = False
    for section in ("tabletSwitcher", "layoutPersistence", "shortcuts"):
        if not isinstance(multitasking.get(section), dict):
            multitasking[section] = copy.deepcopy(defaults.get(section, {}))
            changed = True
    for section in ("tabletSwitcher", "layoutPersistence", "shortcuts"):
        target = multitasking[section]
        for key, value in defaults.get(section, {}).items():
            if key not in target:
                target[key] = copy.deepcopy(value)
                changed = True
    if changed and "multitasking-1.1-defaults" not in applied:
        applied.append("multitasking-1.1-defaults")


def fill_missing(target: dict[str, Any], template: dict[str, Any]) -> bool:
    changed = False
    for key, value in template.items():
        if key not in target:
            target[key] = copy.deepcopy(value)
            changed = True
        elif isinstance(target.get(key), dict) and isinstance(value, dict):
            if fill_missing(target[key], value):
                changed = True
    return changed


def legacy_adaptive_profile(source: dict[str, Any]) -> str:
    general = source.get("general")
    raw = general.get("profile", "") if isinstance(general, dict) else ""
    profile = str(raw).lower().replace("_", "-").replace(" ", "-")
    if profile in {"", "automatic", "default"}:
        return "auto"
    if profile in {"desktop", "tablet", "hybrid", "presentation", "gaming", "custom"}:
        return profile
    if profile in {"stylus", "gnome-like"}:
        return "hybrid"
    return "auto"


def migration_adaptive_1_2(source: dict[str, Any], applied: list[str]) -> None:
    defaults = load_defaults()
    changed = False
    had_adaptive = isinstance(source.get("adaptive"), dict)
    had_control_center = isinstance(source.get("controlCenter"), dict)

    if not had_control_center:
        source["controlCenter"] = copy.deepcopy(defaults.get("controlCenter", {}))
        changed = True
    elif fill_missing(source["controlCenter"], defaults.get("controlCenter", {})):
        changed = True

    if not had_adaptive:
        source["adaptive"] = copy.deepcopy(defaults.get("adaptive", {}))
        source["adaptive"]["profile"] = legacy_adaptive_profile(source)
        changed = True
    elif fill_missing(source["adaptive"], defaults.get("adaptive", {})):
        changed = True

    control_center = source["controlCenter"]
    widget = control_center.get("widget")
    if not isinstance(widget, dict):
        control_center["widget"] = copy.deepcopy(defaults["controlCenter"]["widget"])
        changed = True
    elif widget.get("position") not in {"left", "center", "right"}:
        widget["position"] = "right"
        changed = True

    if not isinstance(control_center.get("compactToggles"), list):
        control_center["compactToggles"] = copy.deepcopy(defaults["controlCenter"]["compactToggles"])
        changed = True
    if not isinstance(control_center.get("visibleModules"), list):
        control_center["visibleModules"] = copy.deepcopy(defaults["controlCenter"]["visibleModules"])
        changed = True
    if not isinstance(control_center.get("moduleOrder"), list):
        control_center["moduleOrder"] = copy.deepcopy(defaults["controlCenter"]["moduleOrder"])
        changed = True
    if not isinstance(source["adaptive"].get("deviceRules"), list):
        source["adaptive"]["deviceRules"] = []
        changed = True

    if changed and "adaptive-1.2-defaults" not in applied:
        applied.append("adaptive-1.2-defaults")


def migration_device_profiles_2_0(source: dict[str, Any], applied: list[str]) -> None:
    template = load_defaults().get("deviceProfiles", {})
    value = source.get("deviceProfiles")
    changed = False
    if not isinstance(value, dict):
        source["deviceProfiles"] = copy.deepcopy(template)
        changed = True
    else:
        if "schemaVersion" not in value or int(value.get("schemaVersion", 0)) < DEVICE_PROFILE_SCHEMA_VERSION:
            value["schemaVersion"] = DEVICE_PROFILE_SCHEMA_VERSION
            changed = True
        if not isinstance(value.get("profiles"), dict):
            value["profiles"] = {}
            changed = True
        if not isinstance(value.get("rules"), list):
            value["rules"] = []
            changed = True
        calibrations = value.get("calibrations")
        if not isinstance(calibrations, dict):
            value["calibrations"] = copy.deepcopy(template.get("calibrations", {"schemaVersion": 1, "entries": {}, "revision": 0}))
            changed = True
        else:
            if "schemaVersion" not in calibrations:
                calibrations["schemaVersion"] = 1
                changed = True
            if not isinstance(calibrations.get("entries"), dict):
                calibrations["entries"] = {}
                changed = True
            if not isinstance(calibrations.get("revision"), int) or calibrations.get("revision", 0) < 0:
                calibrations["revision"] = 0
                changed = True
        if not isinstance(value.get("revision"), int) or value.get("revision", 0) < 0:
            value["revision"] = 0
            changed = True
    if changed and "device-profiles-2.0-defaults" not in applied:
        applied.append("device-profiles-2.0-defaults")


def migration_hardware_setup_profiles_1_0(source: dict[str, Any], applied: list[str]) -> None:
    template = load_defaults().get("hardwareSetupProfiles", {})
    value = source.get("hardwareSetupProfiles")
    changed = False
    if not isinstance(value, dict):
        source["hardwareSetupProfiles"] = copy.deepcopy(template)
        changed = True
    else:
        if "schemaVersion" not in value:
            value["schemaVersion"] = HARDWARE_SETUP_SCHEMA_VERSION
            changed = True
        if not isinstance(value.get("profiles"), dict):
            value["profiles"] = {}
            changed = True
        if value.get("selected", "auto") not in {"auto", "tablet", "desk", "portable", "travel", "presentation", "drawing", "custom"}:
            value["selected"] = "auto"
            changed = True
        display_policy = value.get("displayPolicy")
        if not isinstance(display_policy, dict):
            value["displayPolicy"] = copy.deepcopy(template.get("displayPolicy", {}))
            changed = True
        else:
            if "schemaVersion" not in display_policy:
                display_policy["schemaVersion"] = HARDWARE_SETUP_SCHEMA_VERSION
                changed = True
            if not isinstance(display_policy.get("roles"), dict):
                display_policy["roles"] = {}
                changed = True
        match_policy = value.get("matchPolicy")
        if not isinstance(match_policy, dict):
            value["matchPolicy"] = copy.deepcopy(template.get("matchPolicy", {"schemaVersion": 1, "mode": "ask", "autoApply": False, "promptOnce": True}))
            changed = True
        else:
            if "schemaVersion" not in match_policy:
                match_policy["schemaVersion"] = 1
                changed = True
            if "mode" not in match_policy:
                match_policy["mode"] = "ask"
                changed = True
            if "autoApply" not in match_policy:
                match_policy["autoApply"] = False
                changed = True
            if "promptOnce" not in match_policy:
                match_policy["promptOnce"] = True
                changed = True
        if not isinstance(value.get("matches"), list):
            value["matches"] = []
            changed = True
        if not isinstance(value.get("revision"), int) or value.get("revision", 0) < 0:
            value["revision"] = 0
            changed = True
    if changed and "hardware-setup-profiles-1.0-defaults" not in applied:
        applied.append("hardware-setup-profiles-1.0-defaults")


def migration_calibration_1_3(source: dict[str, Any], applied: list[str]) -> None:
    template = load_defaults().get("calibration", {})
    value = source.get("calibration")
    changed = False
    if not isinstance(value, dict):
        source["calibration"] = copy.deepcopy(template)
        changed = True
    else:
        timeout = value.get("confirmationTimeoutMs", template.get("confirmationTimeoutMs", 8000))
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
            value["confirmationTimeoutMs"] = template.get("confirmationTimeoutMs", 8000)
            changed = True
        else:
            bounded = max(1000, min(15000, int(timeout)))
            if bounded != timeout:
                value["confirmationTimeoutMs"] = bounded
                changed = True
        for key, default in (("autoRollback", True), ("preserveLastKnownGood", True), ("safeModeIgnoreCustom", True)):
            if key not in value:
                value[key] = default
                changed = True
    if changed and "calibration-1.3-defaults" not in applied:
        applied.append("calibration-1.3-defaults")


def nested_future_schema(source: dict[str, Any]) -> tuple[str, int] | None:
    device_profiles = source.get("deviceProfiles")
    if isinstance(device_profiles, dict):
        value = device_profiles.get("schemaVersion", 0)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
            raise ConfigError("invalid-device-profile-schema", "deviceProfiles.schemaVersion must be an integer")
        if int(value) > DEVICE_PROFILE_SCHEMA_VERSION:
            return "future-device-profile-schema", int(value)

    setup_profiles = source.get("hardwareSetupProfiles")
    if isinstance(setup_profiles, dict):
        value = setup_profiles.get("schemaVersion", 0)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
            raise ConfigError("invalid-hardware-setup-schema", "hardwareSetupProfiles.schemaVersion must be an integer")
        if int(value) > HARDWARE_SETUP_SCHEMA_VERSION:
            return "future-hardware-setup-schema", int(value)
        display_policy = setup_profiles.get("displayPolicy")
        if isinstance(display_policy, dict):
            value = display_policy.get("schemaVersion", 0)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
                raise ConfigError("invalid-display-policy-schema", "displayPolicy.schemaVersion must be an integer")
            if int(value) > HARDWARE_SETUP_SCHEMA_VERSION:
                return "future-display-policy-schema", int(value)
    if isinstance(device_profiles, dict):
        calibrations = device_profiles.get("calibrations")
        if isinstance(calibrations, dict):
            value = calibrations.get("schemaVersion", 0)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
                raise ConfigError("invalid-calibration-schema", "deviceProfiles.calibrations.schemaVersion must be an integer")
            if int(value) > 1:
                return "future-calibration-schema", int(value)
    return None


def release_migration(applied: list[str]) -> None:
    if ("device-profiles-2.0-defaults" in applied or "hardware-setup-profiles-1.0-defaults" in applied) and "device-intelligence-1.3-defaults" not in applied:
        applied.append("device-intelligence-1.3-defaults")


def migrate(value: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    if not isinstance(value, dict):
        raise ConfigError("invalid-root", "configuration root must be a JSON object")
    source = copy.deepcopy(value)
    raw_version = source.get("schemaVersion", 0)
    if isinstance(raw_version, bool) or not isinstance(raw_version, (int, float)):
        raise ConfigError("invalid-schema-version", "schemaVersion must be an integer")
    version = int(raw_version)
    if version != raw_version or version < 0:
        raise ConfigError("invalid-schema-version", "schemaVersion must be a non-negative integer")
    if version > CURRENT_SCHEMA_VERSION:
        raise ConfigError("future-schema", f"schemaVersion {version} is newer than supported {CURRENT_SCHEMA_VERSION}")
    future = nested_future_schema(source)
    if future is not None:
        raise ConfigError(future[0], f"nested schema {future[1]} is newer than supported")
    applied: list[str] = []
    if version < 1:
        migration_zero_to_one(source, applied)
    if int(source.get("schemaVersion", 0)) < 2:
        migration_one_to_two(source, applied)
    migration_multitasking_1_1(source, applied)
    migration_adaptive_1_2(source, applied)
    migration_device_profiles_2_0(source, applied)
    migration_hardware_setup_profiles_1_0(source, applied)
    migration_calibration_1_3(source, applied)
    release_migration(applied)
    normalized = deep_merge(load_defaults(), source)
    normalized["schemaVersion"] = CURRENT_SCHEMA_VERSION
    return normalized, {
        "from": version,
        "to": CURRENT_SCHEMA_VERSION,
        "releaseFrom": "legacy" if version < 2 else MIGRATION_SOURCE_RELEASE,
        "releaseTo": CURRENT_RELEASE,
        "applied": applied,
        "migrated": bool(applied),
    }


def validate(value: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(value, dict):
        return ["root must be an object"]
    if value.get("schemaVersion") != CURRENT_SCHEMA_VERSION:
        errors.append(f"schemaVersion must be {CURRENT_SCHEMA_VERSION}")
    defaults = load_defaults()
    for key in defaults:
        if key == "schemaVersion":
            continue
        if key not in value:
            errors.append(f"missing section: {key}")
        elif not isinstance(value[key], dict):
            errors.append(f"section must be an object: {key}")
    updates = value.get("updates")
    if isinstance(updates, dict) and updates.get("channel", "stable") not in {"stable", "beta", "main", "nightly"}:
        errors.append("updates.channel must be stable, beta, main, or nightly")
    recovery = value.get("recovery")
    if isinstance(recovery, dict) and not isinstance(recovery.get("maxCrashAttempts", 2), int):
        errors.append("recovery.maxCrashAttempts must be an integer")
    calibration = value.get("calibration")
    if isinstance(calibration, dict):
        timeout = calibration.get("confirmationTimeoutMs", 8000)
        if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1000 <= timeout <= 15000:
            errors.append("calibration.confirmationTimeoutMs must be an integer between 1000 and 15000")
    return errors


def read_json(path: str) -> Any:
    if path == "-":
        raw = sys.stdin.read()
        display = "stdin"
    else:
        source = pathlib.Path(path)
        display = str(source)
        if not source.is_file():
            raise ConfigError("missing-input", f"configuration file not found: {source}")
        try:
            raw = source.read_text(encoding="utf-8")
        except OSError as exc:
            raise ConfigError("read-failed", f"cannot read {source}: {exc}") from exc
    try:
        return json.loads(raw), display
    except json.JSONDecodeError as exc:
        raise ConfigError("invalid-json", f"invalid JSON in {display}: {exc}") from exc


def read_and_migrate(path: str) -> tuple[dict[str, Any], dict[str, Any], str]:
    raw, display = read_json(path)
    normalized, report = migrate(raw)
    errors = validate(normalized)
    if errors:
        raise ConfigError("invalid-config", "; ".join(errors))
    return normalized, report, display


def safe_graph_id(value: Any) -> str:
    candidate = value if isinstance(value, str) else ""
    if not GRAPH_ID_RE.fullmatch(candidate):
        raise ConfigError("invalid-graph-id", "device id must be a sanitized Device Graph id")
    return candidate


def finite_number(value: Any, fallback: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        return fallback
    return float(value)


def nonnegative_int(value: Any, fallback: int = 0) -> int:
    if isinstance(value, bool):
        return fallback
    try:
        result = int(value)
    except (TypeError, ValueError, OverflowError):
        return fallback
    return max(0, result)


def safe_mapping(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    output = value.get("outputId", value.get("output_id", ""))
    if not isinstance(output, str) or not GRAPH_ID_RE.fullmatch(output) or not output.startswith("display:"):
        return None
    scale = value.get("scale") if isinstance(value.get("scale"), dict) else {}
    offset = value.get("offset") if isinstance(value.get("offset"), dict) else {}
    scale_x = finite_number(scale.get("x", value.get("scaleX", 1)), 1)
    scale_y = finite_number(scale.get("y", value.get("scaleY", 1)), 1)
    offset_x = finite_number(offset.get("x", value.get("offsetX", 0)), 0)
    offset_y = finite_number(offset.get("y", value.get("offsetY", 0)), 0)
    rotation_value = value.get("rotation", 0)
    if isinstance(rotation_value, bool) or not isinstance(rotation_value, (int, float)) or not math.isfinite(float(rotation_value)) or int(rotation_value) != rotation_value:
        return None
    rotation = int(rotation_value)
    if rotation not in {0, 90, 180, 270} or not 0.5 <= scale_x <= 2 or not 0.5 <= scale_y <= 2 or abs(offset_x) > 0.5 or abs(offset_y) > 0.5:
        return None
    axis = value.get("axis") if isinstance(value.get("axis"), dict) else {}
    return {
        "outputId": output,
        "offset": {"x": offset_x, "y": offset_y},
        "scale": {"x": scale_x, "y": scale_y},
        "rotation": rotation,
        "axis": {
            "swapped": axis.get("swapped") is True,
            "invertX": axis.get("invertX") is True,
            "invertY": axis.get("invertY") is True,
        },
    }


def load_mutable_config(path_text: str) -> tuple[pathlib.Path, dict[str, Any], dict[str, Any]]:
    path = pathlib.Path(path_text)
    if path.is_symlink() or has_symlink_component(path.parent):
        raise ConfigError("symlink-refused", f"refusing to modify configuration through symlink: {path}")
    normalized, report, _ = read_and_migrate(str(path))
    return path, normalized, report


def write_mutable_config(path: pathlib.Path, value: dict[str, Any]) -> str | None:
    previous = backup(str(path))
    content = json_text(value)
    atomic_write(str(path), content)
    atomic_write(str(lkg_path(path)), content)
    return previous


def device_profile_section(config: dict[str, Any]) -> dict[str, Any]:
    section = config.get("deviceProfiles")
    if not isinstance(section, dict):
        section = config["deviceProfiles"] = copy.deepcopy(load_defaults().get("deviceProfiles", {}))
    profiles = section.get("profiles")
    if not isinstance(profiles, dict):
        profiles = section["profiles"] = {}
    calibrations = section.get("calibrations")
    if not isinstance(calibrations, dict):
        calibrations = section["calibrations"] = {"schemaVersion": 1, "entries": {}, "revision": 0}
    entries = calibrations.get("entries")
    if not isinstance(entries, dict):
        entries = calibrations["entries"] = {}
    return section


def command_device_reset(args: argparse.Namespace) -> int:
    device_id = safe_graph_id(args.device_id)
    path, config, report = load_mutable_config(args.path)
    section = device_profile_section(config)
    profiles = section["profiles"]
    calibrations = section["calibrations"]
    entries = calibrations["entries"]
    profile_removed = device_id in profiles
    calibration_ids = [
        str(entry_id)
        for entry_id, entry in entries.items()
        if isinstance(entry, dict) and entry.get("deviceId") == device_id
    ]
    if not profile_removed and not calibration_ids:
        raise ConfigError("profile-not-found", f"no Omanome device profile exists for {device_id}")
    if profile_removed:
        del profiles[device_id]
    for entry_id in calibration_ids:
        del entries[entry_id]
    section["revision"] = nonnegative_int(section.get("revision", 0)) + 1
    calibrations["revision"] = nonnegative_int(calibrations.get("revision", 0)) + 1
    previous = write_mutable_config(path, config)
    output_result(
        {
            "ok": True,
            "action": "reset",
            "deviceId": device_id,
            "profileRemoved": profile_removed,
            "calibrationsRemoved": len(calibration_ids),
            "backup": previous,
            "reloadRequired": True,
            "migration": report,
        },
        args.json,
    )
    return 0


def command_device_rollback(args: argparse.Namespace) -> int:
    device_id = safe_graph_id(args.device_id)
    path, config, report = load_mutable_config(args.path)
    section = device_profile_section(config)
    profiles = section["profiles"]
    calibrations = section["calibrations"]
    entries = calibrations["entries"]
    profile = profiles.get(device_id)
    if not isinstance(profile, dict):
        raise ConfigError("profile-not-found", f"no Omanome device profile exists for {device_id}")
    restored: list[dict[str, Any]] = []
    next_revision = nonnegative_int(calibrations.get("revision", 0))
    for entry_id, entry in entries.items():
        if not isinstance(entry, dict) or entry.get("deviceId") != device_id:
            continue
        kind = entry.get("kind")
        if kind not in CALIBRATION_KINDS:
            continue
        mapping = safe_mapping(entry.get("lastKnownGood"))
        if mapping is None:
            continue
        entry["mapping"] = mapping
        entry["outputId"] = mapping["outputId"]
        entry["lastKnownGood"] = None
        entry["lastKnownGoodAt"] = 0
        entry["status"] = "confirmed"
        next_revision += 1
        entry["revision"] = next_revision
        profile_section = profile.setdefault("touch" if kind == "touchscreen" else "stylus", {})
        profile_section["mappingOutput"] = mapping["outputId"]
        profile_section["calibrationId"] = str(entry_id)
        restored.append({"id": str(entry_id), "kind": kind, "outputId": mapping["outputId"], "rotation": mapping["rotation"]})
    if not restored:
        raise ConfigError("no-last-known-good", f"no safe last-known-good calibration exists for {device_id}")
    calibrations["revision"] = next_revision
    section["revision"] = nonnegative_int(section.get("revision", 0)) + 1
    previous = write_mutable_config(path, config)
    output_result(
        {
            "ok": True,
            "action": "rollback",
            "deviceId": device_id,
            "restored": restored,
            "backup": previous,
            "reloadRequired": True,
            "migration": report,
        },
        args.json,
    )
    return 0


SETUP_PRESETS: tuple[dict[str, str], ...] = (
    {"id": "auto", "label": "Automatic", "preferredAdaptiveProfile": "auto"},
    {"id": "tablet", "label": "Tablet", "preferredAdaptiveProfile": "tablet"},
    {"id": "desk", "label": "Desk", "preferredAdaptiveProfile": "desktop"},
    {"id": "portable", "label": "Portable", "preferredAdaptiveProfile": "hybrid"},
    {"id": "travel", "label": "Travel", "preferredAdaptiveProfile": "hybrid"},
    {"id": "presentation", "label": "Presentation", "preferredAdaptiveProfile": "presentation"},
    {"id": "drawing", "label": "Drawing", "preferredAdaptiveProfile": "drawing"},
    {"id": "custom", "label": "Custom", "preferredAdaptiveProfile": "auto"},
)


def setup_config(path_text: str) -> tuple[pathlib.Path, dict[str, Any], dict[str, Any]]:
    path = pathlib.Path(path_text)
    if path.is_file():
        return load_mutable_config(path_text)
    if path.exists() or path.is_symlink() or has_symlink_component(path.parent):
        raise ConfigError("invalid-config-path", f"configuration path is not a regular file: {path}")
    defaults = load_defaults()
    report = {"from": CURRENT_SCHEMA_VERSION, "to": CURRENT_SCHEMA_VERSION, "releaseFrom": CURRENT_RELEASE, "releaseTo": CURRENT_RELEASE, "applied": [], "migrated": False}
    return path, defaults, report


def normalized_setup_rows(config: dict[str, Any]) -> list[dict[str, Any]]:
    section = config.get("hardwareSetupProfiles") if isinstance(config.get("hardwareSetupProfiles"), dict) else {}
    profiles = section.get("profiles") if isinstance(section.get("profiles"), dict) else {}
    rows = [dict(item, source="built-in") for item in SETUP_PRESETS]
    for setup_id, value in profiles.items():
        if setup_id not in SETUP_IDS or not isinstance(value, dict):
            continue
        base = next((item for item in rows if item["id"] == setup_id), {"id": setup_id, "label": setup_id, "preferredAdaptiveProfile": "auto"})
        rows = [item for item in rows if item["id"] != setup_id]
        rows.append({
            "id": setup_id,
            "label": str(value.get("label", value.get("name", base["label"])))[:64],
            "preferredAdaptiveProfile": str(value.get("preferredAdaptiveProfile", base["preferredAdaptiveProfile"])),
            "source": "user",
        })
    return rows


def command_hardware_setup_list(args: argparse.Namespace) -> int:
    _, config, _ = setup_config(args.path)
    rows = normalized_setup_rows(config)
    payload = {"schemaVersion": 1, "source": "config", "setups": rows, "privacy": {"rawHardwareIdentifiersEmitted": False}}
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        for row in rows:
            print(f"{row['id']}: {row['label']} ({row['preferredAdaptiveProfile']})")
    return 0


def command_hardware_setup_status(args: argparse.Namespace) -> int:
    _, config, _ = setup_config(args.path)
    section = config.get("hardwareSetupProfiles") if isinstance(config.get("hardwareSetupProfiles"), dict) else {}
    selected = section.get("selected", "auto")
    if selected not in SETUP_IDS:
        selected = "auto"
    row = next((item for item in normalized_setup_rows(config) if item["id"] == selected), next(item for item in SETUP_PRESETS if item["id"] == "auto"))
    policy = section.get("matchPolicy") if isinstance(section.get("matchPolicy"), dict) else {}
    payload = {
        "schemaVersion": 1,
        "source": "config",
        "selected": selected,
        "setup": row,
        "matchPolicy": {
            "mode": str(policy.get("mode", "ask")),
            "autoApply": policy.get("autoApply") is True,
            "promptOnce": policy.get("promptOnce") is not False,
        },
        "runtime": "service-required",
        "privacy": {"rawHardwareIdentifiersEmitted": False},
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        print(f"Selected: {row['label']}")
        print(f"Adaptive profile: {row['preferredAdaptiveProfile']}")
        print(f"Match policy: {payload['matchPolicy']['mode']}")
        print("Runtime topology: service required")
    return 0


def command_hardware_setup_apply(args: argparse.Namespace) -> int:
    if args.setup_id not in SETUP_IDS:
        raise ConfigError("invalid-setup-profile", f"unknown hardware setup: {args.setup_id}")
    path, config, report = setup_config(args.path)
    section = config.setdefault("hardwareSetupProfiles", {})
    if not isinstance(section, dict):
        section = config["hardwareSetupProfiles"] = copy.deepcopy(load_defaults()["hardwareSetupProfiles"])
    previous_selected = section.get("selected", "auto")
    section["selected"] = args.setup_id
    section["revision"] = nonnegative_int(section.get("revision", 0)) + 1
    previous = write_mutable_config(path, config)
    output_result(
        {
            "ok": True,
            "action": "apply",
            "selected": args.setup_id,
            "previous": previous_selected,
            "backup": previous,
            "reloadRequired": True,
            "migration": report,
        },
        args.json,
    )
    return 0


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


def has_symlink_component(path: pathlib.Path) -> bool:
    """Return true when an existing component of an absolute path is a link."""

    if not path.is_absolute():
        return False
    cursor = pathlib.Path(path.anchor)
    for component in path.parts[1:]:
        cursor /= component
        if cursor.is_symlink():
            return True
    return False


def sibling_path(path: pathlib.Path, suffix: str) -> pathlib.Path:
    return path.with_name(path.name + suffix)


def atomic_write(path_text: str, content: str) -> None:
    path = pathlib.Path(path_text)
    if (path.exists() and path.is_symlink()) or has_symlink_component(path.parent):
        raise ConfigError("symlink-refused", f"refusing to replace symlink: {path}")
    temporary: pathlib.Path | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, prefix=".omanome-config-", delete=False) as handle:
            temporary = pathlib.Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except OSError as exc:
        try:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise ConfigError("write-failed", f"cannot atomically write {path}: {exc}") from exc


def backup(path_text: str) -> str | None:
    path = pathlib.Path(path_text)
    if not path.is_file():
        return None
    if path.is_symlink():
        raise ConfigError("symlink-refused", f"refusing to back up symlink: {path}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}")
    counter = 1
    while destination.exists() or destination.is_symlink():
        destination = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, destination)
    os.chmod(destination, 0o600)
    return str(destination)


def private_copy(source: pathlib.Path, destination: pathlib.Path) -> None:
    """Copy a damaged config without following or replacing a link."""

    if source.is_symlink() or destination.is_symlink() or has_symlink_component(destination.parent):
        raise ConfigError("symlink-refused", f"refusing to preserve config through symlink: {destination}")
    try:
        with source.open("rb") as source_handle, destination.open("xb") as destination_handle:
            shutil.copyfileobj(source_handle, destination_handle)
            destination_handle.flush()
            os.fsync(destination_handle.fileno())
        os.chmod(destination, 0o600)
    except FileExistsError:
        raise ConfigError("write-failed", f"refusing to overwrite preserved config: {destination}")
    except OSError as exc:
        try:
            destination.unlink(missing_ok=True)
        except OSError:
            pass
        raise ConfigError("write-failed", f"cannot preserve damaged config: {exc}") from exc


def lkg_path(path: pathlib.Path) -> pathlib.Path:
    return sibling_path(path, LKG_SUFFIX)


def preserve_corrupt(path: pathlib.Path) -> pathlib.Path | None:
    if not path.exists():
        return None
    if path.is_symlink() or not path.is_file():
        raise ConfigError("symlink-refused", f"refusing to preserve non-regular config: {path}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    destination = sibling_path(path, f"{CORRUPT_SUFFIX}.{stamp}")
    counter = 1
    while destination.exists() or destination.is_symlink():
        destination = sibling_path(path, f"{CORRUPT_SUFFIX}.{stamp}.{counter}")
        counter += 1
    private_copy(path, destination)
    return destination


def valid_candidate(path: pathlib.Path) -> tuple[dict[str, Any], dict[str, Any]] | None:
    if path.is_symlink() or not path.is_file():
        return None
    try:
        normalized, report, _ = read_and_migrate(str(path))
    except ConfigError as exc:
        # A future-schema LKG is not safe to overwrite with old defaults.
        if exc.reason == "future-schema":
            return None
        return None
    return normalized, report


def command_recover(args: argparse.Namespace) -> int:
    path = pathlib.Path(args.path)
    if path.is_symlink() or has_symlink_component(path.parent):
        raise ConfigError("symlink-refused", f"refusing to recover config through symlink: {path}")

    # A future-schema file is intentionally left byte-for-byte untouched. The
    # running older release must not destroy data it cannot understand.
    if path.is_file():
        try:
            normalized, report, display = read_and_migrate(str(path))
        except ConfigError as exc:
            if exc.reason == "future-schema":
                raise
        else:
            atomic_write(str(lkg_path(path)), json_text(normalized))
            output_result(
                {
                    "ok": True,
                    "path": display,
                    "recovered": False,
                    "source": "current",
                    "schemaVersion": normalized["schemaVersion"],
                    "migration": report,
                },
                args.json,
            )
            return 0

    preserved = preserve_corrupt(path)
    source = "defaults"
    normalized = load_defaults()
    report: dict[str, Any] = {
        "from": CURRENT_SCHEMA_VERSION,
        "to": CURRENT_SCHEMA_VERSION,
        "releaseFrom": CURRENT_RELEASE,
        "releaseTo": CURRENT_RELEASE,
        "applied": [],
        "migrated": False,
    }
    candidates: list[pathlib.Path] = [lkg_path(path)]
    candidates.extend(sorted(path.parent.glob(f"{path.name}.bak.*"), reverse=True))
    for candidate in candidates:
        valid = valid_candidate(candidate)
        if valid is None:
            continue
        normalized, report = valid
        source = str(candidate)
        break

    atomic_write(str(path), json_text(normalized))
    atomic_write(str(lkg_path(path)), json_text(normalized))
    payload = {
        "ok": True,
        "path": str(path),
        "recovered": True,
        "source": source,
        "schemaVersion": normalized["schemaVersion"],
        "migration": report,
        "preservedCorrupt": str(preserved) if preserved else None,
    }
    output_result(payload, args.json)
    return 0


def output_result(payload: dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        if payload.get("ok") is True:
            print("ok")
            for key in ("path", "schemaVersion", "migration", "backup", "changed"):
                if key in payload:
                    print(f"{key}: {payload[key]}")
        else:
            print(f"error: {payload.get('reason', 'unknown')}: {payload.get('message', '')}", file=sys.stderr)


def command_validate(args: argparse.Namespace) -> int:
    normalized, report, display = read_and_migrate(args.path)
    payload = {"ok": True, "path": display, "schemaVersion": normalized["schemaVersion"], "migration": report, "errors": []}
    output_result(payload, args.json)
    return 0


def command_export(args: argparse.Namespace) -> int:
    if args.path:
        normalized, report, display = read_and_migrate(args.path)
    else:
        normalized, report, display = load_defaults(), {"from": CURRENT_SCHEMA_VERSION, "to": CURRENT_SCHEMA_VERSION, "releaseFrom": CURRENT_RELEASE, "releaseTo": CURRENT_RELEASE, "applied": [], "migrated": False}, "defaults"
    if args.output:
        atomic_write(args.output, json_text(normalized))
        payload = {"ok": True, "path": args.output, "schemaVersion": normalized["schemaVersion"], "migration": report}
        output_result(payload, args.json)
    else:
        print(json_text(normalized), end="")
    return 0


def command_migrate(args: argparse.Namespace) -> int:
    normalized, report, display = read_and_migrate(args.path)
    atomic_write(args.output, json_text(normalized))
    output_result({"ok": True, "path": args.output, "schemaVersion": normalized["schemaVersion"], "migration": report}, args.json)
    return 0


def command_import(args: argparse.Namespace) -> int:
    normalized, report, display = read_and_migrate(args.source)
    previous = backup(args.target)
    atomic_write(args.target, json_text(normalized))
    atomic_write(str(lkg_path(pathlib.Path(args.target))), json_text(normalized))
    output_result({"ok": True, "path": args.target, "schemaVersion": normalized["schemaVersion"], "migration": report, "backup": previous}, args.json)
    return 0


def command_diff(args: argparse.Namespace) -> int:
    candidate, report, display = read_and_migrate(args.path)
    if args.against:
        baseline, _, baseline_display = read_and_migrate(args.against)
    else:
        baseline, baseline_display = load_defaults(), "defaults"
    before = json_text(baseline).splitlines(keepends=True)
    after = json_text(candidate).splitlines(keepends=True)
    diff = "".join(difflib.unified_diff(before, after, fromfile=baseline_display, tofile=display))
    if args.json:
        output_result({"ok": True, "changed": baseline != candidate, "from": baseline_display, "to": display, "diff": diff, "migration": report}, True)
    else:
        print(diff, end="")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("path")
    validate_parser.add_argument("--json", action="store_true")
    validate_parser.set_defaults(function=command_validate)
    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("path", nargs="?")
    export_parser.add_argument("--output")
    export_parser.add_argument("--json", action="store_true")
    export_parser.set_defaults(function=command_export)
    migrate_parser = subparsers.add_parser("migrate")
    migrate_parser.add_argument("path")
    migrate_parser.add_argument("--output", required=True)
    migrate_parser.add_argument("--json", action="store_true")
    migrate_parser.set_defaults(function=command_migrate)
    recover_parser = subparsers.add_parser("recover")
    recover_parser.add_argument("path")
    recover_parser.add_argument("--json", action="store_true")
    recover_parser.set_defaults(function=command_recover)
    import_parser = subparsers.add_parser("import")
    import_parser.add_argument("source")
    import_parser.add_argument("target")
    import_parser.add_argument("--json", action="store_true")
    import_parser.set_defaults(function=command_import)
    diff_parser = subparsers.add_parser("diff")
    diff_parser.add_argument("path")
    diff_parser.add_argument("--against")
    diff_parser.add_argument("--json", action="store_true")
    diff_parser.set_defaults(function=command_diff)
    device_parser = subparsers.add_parser("device")
    device_parser.add_argument("operation", choices=("reset", "rollback"))
    device_parser.add_argument("path")
    device_parser.add_argument("device_id")
    device_parser.add_argument("--json", action="store_true")
    device_parser.set_defaults(function=lambda args: command_device_reset(args) if args.operation == "reset" else command_device_rollback(args))
    setup_parser = subparsers.add_parser("hardware-setup")
    setup_parser.add_argument("operation", choices=("list", "status", "apply"))
    setup_parser.add_argument("path")
    setup_parser.add_argument("setup_id", nargs="?")
    setup_parser.add_argument("--json", action="store_true")
    setup_parser.set_defaults(function=lambda args: command_hardware_setup_list(args) if args.operation == "list" else command_hardware_setup_status(args) if args.operation == "status" else command_hardware_setup_apply(args))
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        args = parser.parse_args(arguments)
        return int(args.function(args))
    except ConfigError as exc:
        payload = {"ok": False, "reason": exc.reason, "message": str(exc)}
        if "--json" in arguments:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        else:
            print(f"omanome-config: {exc.reason}: {exc}", file=sys.stderr)
        return EX_NOINPUT if exc.reason == "missing-input" else EX_CONFIG
    except OSError as exc:
        print(f"omanome-config: {exc}", file=sys.stderr)
        return EX_CANTCREAT


if __name__ == "__main__":
    sys.exit(main())
