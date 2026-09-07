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


def fixture_result(fixture: dict[str, Any]) -> dict[str, Any]:
    devices = fixture.get("devices") if isinstance(fixture.get("devices"), dict) else {}
    touch = fixture.get("touchscreen", fixture.get("touch", devices.get("touch", [])))
    stylus = fixture.get("stylus", devices.get("tablets", devices.get("stylus", [])))
    sensors = fixture.get("sensors", {}) if isinstance(fixture.get("sensors", {}), dict) else {}
    return {
        "touchscreen": check("touchscreen", bool(touch), "fixture reports touchscreen" if touch else "fixture has no touchscreen", "fixture", {"count": len(touch) if isinstance(touch, list) else int(bool(touch))}),
        "stylus": check("stylus", bool(stylus), "fixture reports stylus" if stylus else "fixture has no stylus", "fixture", {"count": len(stylus) if isinstance(stylus, list) else int(bool(stylus))}),
        "rotationSensor": check("rotationSensor", bool(sensors.get("available", sensors.get("accelerometer", False))), "fixture reports a sensor backend" if sensors else "fixture has no sensor backend", "fixture", sensors),
        "wayland": check("wayland", bool(fixture.get("wayland", True)), "fixture reports Wayland" if fixture.get("wayland", True) else "fixture reports no Wayland", "fixture"),
        "hyprland": check("hyprland", bool(fixture.get("hyprland", True)), "fixture reports Hyprland" if fixture.get("hyprland", True) else "fixture reports no Hyprland", "fixture"),
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
        "rotationSensor": check("rotationSensor", bool(sensors.get("autoRotationSupported", False)), sensor_reason if sensors else "sensor-info returned no backend", "input/sensor-info.sh", sensors),
        "wayland": check("wayland", bool(os.environ.get("WAYLAND_DISPLAY")), "WAYLAND_DISPLAY is set" if os.environ.get("WAYLAND_DISPLAY") else "WAYLAND_DISPLAY is unavailable", "environment"),
        "hyprland": check("hyprland", shutil.which("hyprctl") is not None and bool(devices), "hyprctl device probe completed" if devices else (devices_reason or "hyprctl unavailable"), "hyprctl"),
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
