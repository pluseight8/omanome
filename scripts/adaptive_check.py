#!/usr/bin/env python3
"""Run the portable Omanome 1.2 adaptive-mode safety gate.

The gate checks source-level ownership and event-driven boundaries, then reads
an explicit fixture only to render the manual matrix.  Fixture declarations
are never promoted to hardware Pass results.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

from hardware_test import ADAPTIVE_SCENARIOS, fixture_result


ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "hardware-adaptive.json"


def source(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def check(name: str, passed: bool, details: str) -> dict[str, str]:
    return {"name": name, "result": "Pass" if passed else "Fail", "details": details}


def contract_checks() -> list[dict[str, str]]:
    service = source(ROOT / "shell" / "Service.qml")
    input_devices = source(ROOT / "shell" / "models" / "InputDevices.js")
    keyboard_devices = source(ROOT / "shell" / "models" / "KeyboardDevices.js")
    keyboard_transitions = source(ROOT / "shell" / "models" / "KeyboardTransitions.js")
    mode_transition = source(ROOT / "shell" / "models" / "ModeTransitionCoordinator.js")
    feature_state = source(ROOT / "shell" / "models" / "FeatureState.js")
    adaptive_mode = source(ROOT / "shell" / "models" / "AdaptiveMode.js")
    adaptive_settings = source(ROOT / "shell" / "models" / "AdaptiveSettings.js")
    docked_mode = source(ROOT / "shell" / "models" / "DockedMode.js")
    monitor = source(ROOT / "input" / "device-monitor.sh")
    manifest = json.loads(source(ROOT / "manifest.json"))
    defaults = json.loads(source(ROOT / "config" / "defaults.json"))
    schema = json.loads(source(ROOT / "config" / "schema.json"))
    checks: list[dict[str, str]] = []

    required_models = {
        "InputDevices.js": ("stableId", "capabilities", "postureSignals"),
        "KeyboardDevices.js": ("classify", "capabilityBag", "normalKeyboard"),
        "KeyboardTransitions.js": ("observe", "debounceMs", "stabilityMs", "stableSignals"),
        "ModeTransitionCoordinator.js": ("begin", "tick", "cancel", "reversing"),
        "AdaptiveMode.js": ("effective", "preview", "accessibilityTarget"),
        "DockedMode.js": ("inventory", "observe", "externalMonitor"),
    }
    model_sources = {
        "InputDevices.js": input_devices,
        "KeyboardDevices.js": keyboard_devices,
        "KeyboardTransitions.js": keyboard_transitions,
        "ModeTransitionCoordinator.js": mode_transition,
        "AdaptiveMode.js": adaptive_mode,
        "DockedMode.js": docked_mode,
    }
    missing_models = [
        f"{name}: {', '.join(marker for marker in markers if marker not in model_sources[name])}"
        for name, markers in required_models.items()
        if not (ROOT / "shell" / "models" / name).is_file()
        or any(marker not in model_sources[name] for marker in markers)
    ]
    checks.append(check(
        "device-model",
        not missing_models,
        "capability-based device, keyboard, transition, adaptive, and docked models are present"
        if not missing_models else "; ".join(missing_models),
    ))

    transition_markers = (
        'KeyboardTransitionsModel.observe',
        'ModeTransitionModel.begin',
        'ModeTransitionModel.tick',
        'keyboardTransitionTimer',
        'modeTransitionTimer',
        'root.modeTransitionReason()',
    )
    transition_safe = all(marker in service for marker in transition_markers) and all(
        marker in keyboard_transitions for marker in ("debounceMs", "stabilityMs", "stableSignals")
    ) and all(marker in mode_transition for marker in ("reversing", "interrupted", "function cancel"))
    checks.append(check(
        "transitions",
        transition_safe,
        "keyboard stability and local mode choreography share one reversible coordinator"
        if transition_safe else "transition debounce/reversal wiring is incomplete",
    ))

    feature_markers = (
        '"models/FeatureState.js" as FeatureStateModel',
        'FeatureStateModel.summary',
        'FeatureStateModel.canToggle',
        'masterEnabled',
        'suspended',
        'enhancementsActive',
    )
    feature_safe = all(marker in service for marker in feature_markers) and all(
        marker in feature_state for marker in ("safetyReason", "profileOverrides", "function summary", "function canToggle")
    )
    checks.append(check(
        "feature-registry",
        feature_safe,
        "master, suspend, profile, capability, and safety precedence flow through one registry"
        if feature_safe else "feature registry safety precedence is incomplete",
    ))

    kinds = manifest.get("kinds", [])
    entries = manifest.get("entryPoints", {})
    replacement_markers = ("gnome-shell" + " --" + "replace", "mutter", "second Quickshell", '"bar"')
    bar_safe = (
        "bar-widget" in kinds
        and "bar" not in kinds
        and isinstance(entries, dict)
        and bool(entries.get("barWidget"))
        and all(marker.lower() not in service.lower() for marker in replacement_markers[:2])
        and '"bar"' not in json.dumps(kinds)
    )
    checks.append(check(
        "bar-widget-coexistence",
        bar_safe,
        "the standard Omarchy bar is extended through one bar-widget entry point"
        if bar_safe else "bar replacement or a bar-widget entry point was detected incorrectly",
    ))

    hotplug_safe = (
        monitor.count("udevadm monitor") == 1
        and "--property" in monitor
        and "device.event" in monitor
        and "setInterval" not in monitor
        and "Process {" not in monitor
        and "deviceRefreshDebounce" in service
        and "if (!devicesProcess.running)" in service
        and "deviceMonitorProcess.running" in service
        and "deviceRefreshDebounce.restart()" in service
    )
    checks.append(check(
        "hotplug-process-boundary",
        hotplug_safe,
        "one event stream feeds a debounced snapshot refresh; no per-event process or polling loop"
        if hotplug_safe else "hotplug monitor lacks its single-stream/debounce boundary",
    ))

    release_markers = (
        "function releaseOmanomeInput",
        "root.cancelFallbackInput()",
        "root.stopNativeInputBackend",
        "function disableEnhancements",
        "root.releaseOmanomeInput(reason)",
    )
    release_safe = all(marker in service for marker in release_markers)
    checks.append(check(
        "master-input-release",
        release_safe,
        "master-off/suspend teardown resets the native input boundary before disabling enhancements"
        if release_safe else "master-off input release boundary is incomplete",
    ))

    adaptive_config = defaults.get("adaptive")
    schema_adaptive = schema.get("properties", {}).get("adaptive")
    profile_safe = (
        isinstance(adaptive_config, dict)
        and isinstance(schema_adaptive, dict)
        and adaptive_config.get("automaticTransitions") is True
        and isinstance(adaptive_config.get("profiles"), dict)
        and isinstance(adaptive_config.get("dockedMode"), dict)
        and all(marker in service for marker in ("AdaptiveSettingsModel", "AdaptiveModeModel.preview", "adaptivePreviewState"))
        and "temporary profile preview" in adaptive_settings
        and "externalMonitor" in docked_mode
    )
    checks.append(check(
        "adaptive-profile-boundary",
        profile_safe,
        "profiles, Docked mode, accessibility-aware preview, and automatic transitions are runtime-scoped"
        if profile_safe else "adaptive profile/preview configuration boundary is incomplete",
    ))

    device_event_start = service.find("function updateDeviceEvent")
    device_event_end = service.find("\n  function startDeviceMonitor", device_event_start)
    device_event_body = service[device_event_start:device_event_end if device_event_end >= 0 else None]
    no_config_write = "setConfig(" not in device_event_body and "configFile" not in device_event_body
    checks.append(check(
        "hotplug-no-config-write",
        no_config_write and "deviceRefreshDebounce.restart()" in device_event_body,
        "device events update runtime state only and defer one debounced device snapshot"
        if no_config_write and "deviceRefreshDebounce.restart()" in device_event_body else "device event path writes configuration or lost its debounce",
    ))
    return checks


def fixture_report(path: pathlib.Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    fixture = json.loads(source(path))
    if not isinstance(fixture, dict):
        raise ValueError("adaptive fixture root must be an object")
    if fixture.get("schemaVersion") != 1 or fixture.get("kind") != "omanome-adaptive-fixture":
        raise ValueError("unsupported adaptive fixture schema")
    declaration = fixture.get("adaptive")
    scenarios = declaration.get("scenarios") if isinstance(declaration, dict) else None
    if not isinstance(scenarios, dict):
        raise ValueError("adaptive fixture must declare scenarios")
    expected = {name for name, _ in ADAPTIVE_SCENARIOS}
    if set(scenarios) != expected:
        raise ValueError("adaptive fixture scenario catalog does not match the 1.2 matrix")
    capabilities = fixture_result(fixture)
    rows = capabilities.get("adaptive", {})
    for name in expected:
        row = rows.get(name)
        if not isinstance(row, dict) or row.get("source") != "fixture" or row.get("result") not in {"Untested", "Unavailable"}:
            raise ValueError(f"fixture scenario has an invalid non-certifying result: {name}")
    return fixture, rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=pathlib.Path, default=FIXTURE)
    parser.add_argument("--json", action="store_true", help="emit the machine-readable report")
    args = parser.parse_args(argv)
    try:
        _, rows = fixture_report(args.fixture)
        checks = contract_checks()
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(json.dumps({"schemaVersion": 1, "ok": False, "error": str(exc)}, ensure_ascii=False, sort_keys=True))
        return 1

    passed = all(item["result"] == "Pass" for item in checks)
    scenarios = {
        name: {
            "result": rows[name]["result"],
            "source": rows[name]["source"],
            "reason": rows[name]["reason"],
        }
        for name, _ in ADAPTIVE_SCENARIOS
    }
    report = {
        "schemaVersion": 1,
        "ok": passed,
        "mode": "portable",
        "portableSafety": {"result": "Pass" if passed else "Fail", "checks": checks},
        "hardware": {
            "mode": "fixture",
            "evidence": "fixture",
            "realHardwareValidated": False,
            "scenarios": scenarios,
        },
        "note": "Portable adaptive contracts passed; fixture evidence is not physical hardware certification. Physical tests remain not hardware tested until manually confirmed.",
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
