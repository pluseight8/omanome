#!/usr/bin/env python3
"""Run the portable Omanome 1.1 multitasking safety gate.

This gate exercises repository contracts and a non-certifying fixture.  It
does not synthesize pointer, touchscreen, stylus, or compositor results.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

from hardware_test import MULTITASKING_SCENARIOS, fixture_result


ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "hardware-multitasking.json"
REQUIRED_MODELS = (
    "LayoutEngine.js",
    "SnapAssist.js",
    "SplitView.js",
    "WindowGroups.js",
    "GestureCoordinator.js",
    "MonitorRecovery.js",
    "WorkspaceSwitcher.js",
)


def source(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def function_body(text: str, name: str) -> str:
    marker = f"function {name}"
    start = text.find(marker)
    if start < 0:
        return ""
    end = text.find("\n  function ", start + len(marker))
    return text[start:] if end < 0 else text[start:end]


def contract_checks() -> list[dict[str, str]]:
    service = source(ROOT / "shell" / "Service.qml")
    overlay = source(ROOT / "shell" / "views" / "WorkspaceSwitcher.qml")
    switcher = source(ROOT / "shell" / "views" / "Switcher.qml")
    panel = source(ROOT / "shell" / "Panel.qml")
    defaults = json.loads(source(ROOT / "config" / "defaults.json"))
    schema = json.loads(source(ROOT / "config" / "schema.json"))
    checks: list[dict[str, str]] = []

    missing_models = [name for name in REQUIRED_MODELS if not (ROOT / "shell" / "models" / name).is_file()]
    checks.append({
        "name": "layout-models-present",
        "result": "Pass" if not missing_models else "Fail",
        "details": "all bounded multitasking models are present" if not missing_models else ", ".join(missing_models),
    })

    service_markers = (
        "SnapAssistModel",
        "SplitViewModel",
        "WindowGroupsModel",
        "GestureCoordinatorModel",
        "MonitorRecoveryModel",
        "workspaceSwitcherFocus",
        "executeMultitaskingShortcut",
    )
    missing_service = [marker for marker in service_markers if marker not in service]
    checks.append({
        "name": "service-coordinator-wiring",
        "result": "Pass" if not missing_service else "Fail",
        "details": "snap, split, groups, gestures, recovery, and workspace paths are wired" if not missing_service else ", ".join(missing_service),
    })

    motion_body = function_body(service, "updateWorkspaceSwitcherSwipe")
    motion_safe = bool(motion_body) and all(token not in motion_body for token in ("hyprctl", "dispatch(", "Process {"))
    overlay_safe = all(token not in overlay for token in ("setInterval", "hyprctl", "Process {"))
    switcher_safe = "setInterval" not in switcher
    checks.append({
        "name": "drag-motion-no-subprocess",
        "result": "Pass" if motion_safe and overlay_safe and switcher_safe else "Fail",
        "details": "motion updates remain model-only; compositor dispatch is commit-only" if motion_safe and overlay_safe and switcher_safe else "drag path contains an IPC/process/polling marker",
    })

    preview_safe = all(marker in overlay for marker in ("ScreencopyView", "previewAvailable", "captureSource", "metadataFallback"))
    checks.append({
        "name": "preview-capability-boundary",
        "result": "Pass" if preview_safe else "Fail",
        "details": "live previews are optional compositor streams with metadata fallback" if preview_safe else "workspace preview boundary is incomplete",
    })

    multitasking = defaults.get("multitasking", {})
    schema_multitasking = schema.get("properties", {}).get("multitasking")
    config_safe = isinstance(multitasking, dict) and isinstance(schema_multitasking, dict) and all(
        key in multitasking for key in ("tabletSwitcher", "layoutPersistence", "shortcuts", "sessionRestore")
    )
    checks.append({
        "name": "config-schema-1-1",
        "result": "Pass" if config_safe else "Fail",
        "details": "1.1 tablet switcher, persistence, shortcuts, and restore defaults validate" if config_safe else "multitasking defaults/schema are incomplete",
    })

    transient_safe = "transientOverlay" in panel and '"workspace-overlay"' in panel
    checks.append({
        "name": "transient-overlay-lifecycle",
        "result": "Pass" if transient_safe else "Fail",
        "details": "workspace switcher is an owned transient panel view" if transient_safe else "workspace overlay lifecycle marker is missing",
    })
    return checks


def fixture_report(path: pathlib.Path) -> tuple[dict[str, Any], list[dict[str, str]]]:
    fixture = json.loads(source(path))
    if not isinstance(fixture, dict):
        raise ValueError("multitasking fixture root must be an object")
    if fixture.get("schemaVersion") != 1 or fixture.get("kind") != "omanome-multitasking-fixture":
        raise ValueError("unsupported multitasking fixture schema")
    declaration = fixture.get("multitasking")
    scenarios = declaration.get("scenarios") if isinstance(declaration, dict) else None
    if not isinstance(scenarios, dict):
        raise ValueError("multitasking fixture must declare scenarios")
    expected = {name for name, _ in MULTITASKING_SCENARIOS}
    if set(scenarios) != expected:
        raise ValueError("multitasking fixture scenario catalog does not match the guided matrix")
    capabilities = fixture_result(fixture)
    rows = capabilities.get("multitasking", {})
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
        for name, _ in MULTITASKING_SCENARIOS
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
        "note": "Portable contracts passed; fixture evidence is not touchscreen, stylus, or compositor certification.",
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
