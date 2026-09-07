#!/usr/bin/env python3
"""Run deterministic, non-destructive Omanome hardware capability probes.

The command is intentionally a probe framework rather than a fake hardware
certification tool.  A fixture can be supplied in CI or support requests;
without one the result records only what the current session exposes.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
EX_CONFIG = 78


def command_json(command: list[str], timeout: float = 3.0) -> tuple[Any, str]:
    executable = shutil.which(command[0])
    if not executable:
        return None, f"{command[0]} is unavailable"
    try:
        result = subprocess.run([executable, *command[1:]], capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, f"{command[0]} probe failed: {exc}"
    if result.returncode != 0:
        return None, f"{command[0]} exited {result.returncode}"
    try:
        return json.loads(result.stdout), ""
    except json.JSONDecodeError:
        return None, f"{command[0]} returned non-JSON output"


def check(name: str, available: bool, reason: str, source: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "name": name,
        "available": bool(available),
        "status": "available" if available else "unavailable",
        "reason": reason,
        "source": source,
        "details": details or {},
    }


def records(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        return [value]
    return []


def feature_present(items: list[dict[str, Any]], names: tuple[str, ...]) -> bool:
    for item in items:
        capabilities = item.get("capabilities", {})
        if isinstance(capabilities, list):
            values = {str(value) for value in capabilities}
        elif isinstance(capabilities, dict):
            values = {str(key) for key, enabled in capabilities.items() if enabled}
        else:
            values = set()
        values.update(str(key) for key, enabled in item.items() if enabled is True)
        tool_type = str(item.get("toolType", item.get("type", ""))).lower()
        if "eraser" in names and "eraser" in tool_type:
            return True
        if any(name in values for name in names):
            return True
        if "buttons" in names:
            try:
                if int(item.get("buttonCount", item.get("buttons", 0)) or 0) > 0:
                    return True
            except (TypeError, ValueError):
                pass
    return False


def feature_results(stylus: Any, source: str) -> dict[str, dict[str, Any]]:
    items = records(stylus)
    feature_names = {
        "pressure": ("pressure",),
        "tilt": ("tilt", "tiltX", "tiltY", "tilt-x", "tilt-y"),
        "distance": ("distance",),
        "rotation": ("rotation",),
        "eraser": ("eraser",),
        "buttons": ("buttons", "barrelButtons"),
        "proximity": ("proximity",),
    }
    result: dict[str, dict[str, Any]] = {}
    for name, names in feature_names.items():
        available = feature_present(items, names)
        result[name] = check(
            f"stylus.{name}",
            available,
            f"{source} reports {name}" if available else f"{source} did not report {name}",
            source,
            {"count": len(items)},
        )
    return result


def event_records(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        value = value.get("events", value.get("sequence", []))
    return records(value)


def lifecycle_results(fixture: dict[str, Any]) -> dict[str, dict[str, Any]]:
    events = event_records(fixture.get("events", fixture.get("deviceEvents", [])))
    hotplug = fixture.get("hotplug", {})
    hotplug_events = event_records(hotplug)
    if hotplug_events:
        events = [*events, *hotplug_events]
    hotplug_available = any(
        str(event.get("action", event.get("event", ""))).lower() in {"add", "remove", "connected", "disconnected"}
        for event in events
    )
    suspend = fixture.get("suspendResume", fixture.get("suspend", {}))
    suspend_events = event_records(suspend)
    if isinstance(suspend, dict) and suspend.get("available") is True:
        suspend_available = True
    else:
        suspend_available = any(
            str(event.get("event", event.get("type", ""))).lower() in {"suspend", "resume", "sleep", "wake"}
            for event in suspend_events
        )
    output_mapping = fixture.get("outputMapping", fixture.get("mapping", {}))
    rollback = fixture.get("rollback", fixture.get("rotationRollback", {}))
    return {
        "hotplug": check("hotplug", hotplug_available, "fixture contains add/remove input or display events" if hotplug_available else "fixture has no add/remove hotplug events", "fixture", {"events": len(events)}),
        "suspendResume": check("suspendResume", suspend_available, "fixture contains suspend/resume events" if suspend_available else "fixture has no suspend/resume events", "fixture", {"events": len(suspend_events)}),
        "waylandReconnect": check("waylandReconnect", bool(fixture.get("waylandReconnect", False)), "fixture reports reconnect coverage" if fixture.get("waylandReconnect", False) else "fixture has no reconnect coverage", "fixture"),
        "outputRemap": check("outputRemap", bool(output_mapping), "fixture contains device/output mapping" if output_mapping else "fixture has no output mapping", "fixture"),
        "rollback": check("rollback", bool(rollback), "fixture contains rollback evidence" if rollback else "fixture has no rollback evidence", "fixture"),
    }


def handwriting_result(fixture: dict[str, Any]) -> dict[str, Any]:
    handwriting = fixture.get("handwriting", {})
    available = isinstance(handwriting, dict) and bool(handwriting.get("ink", handwriting.get("available", False)))
    recognition = handwriting.get("recognition", "unavailable") if isinstance(handwriting, dict) else "unavailable"
    recognition_available = recognition not in {False, None, "unavailable"}
    cloud_available = isinstance(handwriting, dict) and bool(handwriting.get("cloud", False))
    return {
        "ink": check("handwriting.ink", available, "fixture reports bounded local ink" if available else "fixture has no handwriting ink", "fixture"),
        "recognition": check("handwriting.recognition", recognition_available, "fixture reports a recognition provider" if recognition_available else "recognition is unavailable", "fixture", {"provider": recognition}),
        "cloud": check("handwriting.cloud", cloud_available, "cloud provider explicitly enabled by fixture" if cloud_available else "cloud recognition is disabled by default", "fixture"),
    }


def fixture_result(fixture: dict[str, Any]) -> dict[str, Any]:
    devices = fixture.get("devices") if isinstance(fixture.get("devices"), dict) else {}
    touch = fixture.get("touchscreen", fixture.get("touch", devices.get("touch", [])))
    stylus = fixture.get("stylus", devices.get("tablets", devices.get("stylus", [])))
    sensors = fixture.get("sensors", {}) if isinstance(fixture.get("sensors", {}), dict) else {}
    return {
        "touchscreen": check("touchscreen", bool(touch), "fixture reports touchscreen" if touch else "fixture has no touchscreen", "fixture", {"count": len(touch) if isinstance(touch, list) else int(bool(touch))}),
        "stylus": check("stylus", bool(stylus), "fixture reports stylus" if stylus else "fixture has no stylus", "fixture", {"count": len(stylus) if isinstance(stylus, list) else int(bool(stylus))}),
        "stylusFeatures": feature_results(stylus, "fixture"),
        "rotationSensor": check("rotationSensor", bool(sensors.get("available", sensors.get("accelerometer", False))), "fixture reports a sensor backend" if sensors else "fixture has no sensor backend", "fixture", sensors),
        "wayland": check("wayland", bool(fixture.get("wayland", True)), "fixture reports Wayland" if fixture.get("wayland", True) else "fixture reports no Wayland", "fixture"),
        "hyprland": check("hyprland", bool(fixture.get("hyprland", True)), "fixture reports Hyprland" if fixture.get("hyprland", True) else "fixture reports no Hyprland", "fixture"),
        "lifecycle": lifecycle_results(fixture),
        "handwriting": handwriting_result(fixture),
    }


def live_result() -> dict[str, Any]:
    devices, devices_reason = command_json(["hyprctl", "devices", "-j"])
    if not isinstance(devices, dict):
        devices = {}
    touch = devices.get("touch", devices.get("touchDevices", []))
    stylus = devices.get("tablets", devices.get("tabletTools", []))
    sensor_script = ROOT / "input" / "sensor-info.sh"
    sensors: dict[str, Any] = {}
    sensor_reason = "sensor probe unavailable"
    if sensor_script.is_file():
        try:
            result = subprocess.run([str(sensor_script)], capture_output=True, text=True, timeout=3, check=False)
            if result.returncode == 0:
                sensors = json.loads(result.stdout)
                sensor_reason = "sensor-info probe completed"
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            pass
    return {
        "touchscreen": check("touchscreen", bool(touch), "Hyprland exposed touchscreen devices" if touch else (devices_reason or "no touchscreen exposed"), "hyprctl devices", {"count": len(touch) if isinstance(touch, list) else int(bool(touch))}),
        "stylus": check("stylus", bool(stylus), "Hyprland exposed tablet devices" if stylus else (devices_reason or "no stylus exposed"), "hyprctl devices", {"count": len(stylus) if isinstance(stylus, list) else int(bool(stylus))}),
        "stylusFeatures": feature_results(stylus, "hyprctl devices"),
        "rotationSensor": check("rotationSensor", bool(sensors.get("autoRotationSupported", False)), sensor_reason if sensors else "sensor-info returned no backend", "input/sensor-info.sh", sensors),
        "wayland": check("wayland", bool(os.environ.get("WAYLAND_DISPLAY")), "WAYLAND_DISPLAY is set" if os.environ.get("WAYLAND_DISPLAY") else "WAYLAND_DISPLAY is unavailable", "environment"),
        "hyprland": check("hyprland", shutil.which("hyprctl") is not None and bool(devices), "hyprctl device probe completed" if devices else (devices_reason or "hyprctl unavailable"), "hyprctl"),
        "lifecycle": {
            name: check(name, False, "live hardware fixture required; not inferred from a static session probe", "live-session")
            for name in ("hotplug", "suspendResume", "waylandReconnect", "outputRemap", "rollback")
        },
        "handwriting": {
            name: check(f"handwriting.{name}", False, "live handwriting fixture/provider required", "live-session")
            for name in ("ink", "recognition", "cloud")
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=pathlib.Path)
    parser.add_argument("--json", action="store_true", help="kept for CLI symmetry; JSON is always emitted")
    args = parser.parse_args(argv)
    try:
        if args.fixture:
            fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
            if not isinstance(fixture, dict):
                raise ValueError("fixture root must be an object")
            capabilities = fixture_result(fixture)
            mode = "fixture"
        else:
            capabilities = live_result()
            mode = "live-probe"
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return EX_CONFIG
    payload = {
        "schemaVersion": 1,
        "ok": True,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mode": mode,
        "realHardwareValidated": False,
        "note": "Capability probe only; unavailable backends are not simulated.",
        "capabilities": capabilities,
    }
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
