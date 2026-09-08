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
import tempfile
from datetime import datetime, timezone
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
EX_CONFIG = 78
RESULTS = ("Pass", "Fail", "Unavailable", "Skipped", "Untested")
SESSION_SCHEMA_VERSION = 1
MULTITASKING_SCENARIOS = (
    ("touch-drag-window", "Drag a managed window with touch without triggering an app gesture."),
    ("touch-snap", "Drag the window to a snap zone and confirm the preview commits once."),
    ("divider-drag", "Drag the Split View divider and confirm both windows resize together."),
    ("dock-to-split", "Long-press a Dock app and drop it into the second split slot."),
    ("overview-to-split", "Drag an Overview window card into a split slot."),
    ("portrait-split", "Create a top/bottom split while the tablet is in portrait."),
    ("rotation", "Rotate landscape to portrait and back without losing the pair or ratio."),
    ("stylus-drag", "Drag and snap a window with stylus contact; proximity alone must not act."),
)


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def has_symlink_component(path: pathlib.Path) -> bool:
    """Reject an output path that would traverse a symlink."""

    candidate = path.expanduser()
    if not candidate.is_absolute():
        candidate = pathlib.Path.cwd() / candidate
    current = pathlib.Path(candidate.anchor or "/")
    for part in candidate.parts[1:] if candidate.anchor else candidate.parts:
        current /= part
        if current.is_symlink():
            return True
    return False


def write_private_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path = path.expanduser()
    if has_symlink_component(path) or path.is_symlink():
        raise ValueError(f"refusing symlink path: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if has_symlink_component(path.parent) or path.is_symlink():
        raise ValueError(f"refusing symlink path: {path}")
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = pathlib.Path(temporary)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = -1
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if path.is_symlink():
            raise ValueError(f"refusing symlink path: {path}")
        os.replace(temporary_path, path)
        os.chmod(path, 0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass


def read_session(path: pathlib.Path) -> dict[str, Any]:
    path = path.expanduser()
    if has_symlink_component(path) or path.is_symlink():
        raise ValueError(f"refusing symlink session: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid certification session: {exc}") from exc
    if not isinstance(payload, dict) or payload.get("schemaVersion") != SESSION_SCHEMA_VERSION:
        raise ValueError("unsupported certification session schema")
    if payload.get("mode") not in {"fixture", "live-probe"}:
        raise ValueError("certification session has an invalid mode")
    stored = payload.get("records", {})
    if not isinstance(stored, dict):
        raise ValueError("certification session records must be an object")
    records: dict[str, dict[str, str]] = {}
    for name, record in stored.items():
        if not isinstance(name, str) or not isinstance(record, dict):
            continue
        result = record.get("result")
        if isinstance(result, str) and result in RESULTS:
            records[name] = {"result": result, "recordedAt": str(record.get("recordedAt", ""))}
    payload["records"] = records
    payload["hardwareConfirmed"] = bool(payload.get("hardwareConfirmed", False))
    return payload


def new_session(mode: str) -> dict[str, Any]:
    now = timestamp()
    return {
        "schemaVersion": SESSION_SCHEMA_VERSION,
        "kind": "omanome-hardware-certification",
        "createdAt": now,
        "updatedAt": now,
        "mode": mode,
        "hardwareConfirmed": False,
        "records": {},
        "note": "Manual records are user evidence; fixture data never certifies hardware.",
    }


def parse_record(value: str) -> tuple[str, str]:
    name, separator, result = value.partition("=")
    if not separator or not name.strip() or result not in RESULTS:
        allowed = ", ".join(RESULTS)
        raise ValueError(f"record must be NAME=RESULT where RESULT is one of: {allowed}")
    return name.strip(), result


def target_map(capabilities: dict[str, Any]) -> dict[str, dict[str, Any]]:
    targets: dict[str, dict[str, Any]] = {}
    for section in ("certification", "lifecycle", "handwriting", "stylusFeatures", "multitasking"):
        values = capabilities.get(section, {})
        if isinstance(values, dict):
            for name, value in values.items():
                if isinstance(value, dict) and "result" in value:
                    targets[f"{section}.{name}"] = value
    for name in ("touchscreen", "rotationSensor", "wayland", "hyprland"):
        value = capabilities.get(name)
        if isinstance(value, dict) and "result" in value:
            targets[name] = value
    aliases = {
        "hotplug": "lifecycle.hotplug",
        "suspendResume": "certification.suspendResume",
        "stylus.pressure": "stylusFeatures.pressure",
        "stylus.tilt": "stylusFeatures.tilt",
        "stylus.distance": "stylusFeatures.distance",
        "stylus.rotation": "stylusFeatures.rotation",
        "stylus.eraser": "stylusFeatures.eraser",
        "stylus.buttons": "stylusFeatures.buttons",
        "stylus.proximity": "stylusFeatures.proximity",
    }
    for alias, canonical in aliases.items():
        if canonical in targets:
            targets[alias] = targets[canonical]
    for name in (
        "display",
        "touch",
        "multitouch",
        "stylus",
        "pressure",
        "tilt",
        "eraser",
        "stylusButtons",
        "keyboard",
        "detachableKeyboard",
        "orientation",
        "osk",
        "multiMonitor",
    ):
        canonical = f"certification.{name}"
        if canonical in targets:
            targets.setdefault(name, targets[canonical])
    for name, value in list(targets.items()):
        if "." not in name:
            targets.setdefault(name, value)
    return targets


def apply_manual_records(
    capabilities: dict[str, Any],
    records: dict[str, dict[str, str]],
    mode: str,
    hardware_confirmed: bool,
) -> dict[str, dict[str, str]]:
    if records and mode != "live-probe":
        raise ValueError("fixture evidence cannot be manually certified")
    targets = target_map(capabilities)
    applied: dict[str, dict[str, str]] = {}
    for name, record in records.items():
        target = targets.get(name)
        if target is None:
            raise ValueError(f"unknown hardware certification target: {name}")
        result = record.get("result")
        if result not in RESULTS:
            raise ValueError(f"invalid result for {name}: {result}")
        if result in {"Pass", "Fail"} and not hardware_confirmed:
            raise ValueError("Pass/Fail records require --confirm-hardware in a live session")
        target["result"] = result
        target["manual"] = True
        target["source"] = "manual-session"
        if result in {"Pass", "Fail"}:
            target["available"] = True
            target["status"] = "available"
        elif result == "Unavailable":
            target["available"] = False
            target["status"] = "unavailable"
        applied[name] = {"result": result, "recordedAt": str(record.get("recordedAt", ""))}
    return applied


def iter_checks(capabilities: dict[str, Any]):
    for section in ("certification", "lifecycle", "handwriting", "stylusFeatures", "multitasking"):
        values = capabilities.get(section, {})
        if isinstance(values, dict):
            for name, value in values.items():
                if isinstance(value, dict) and value.get("result") in RESULTS:
                    yield f"{section}.{name}", value
    for name in ("touchscreen", "rotationSensor", "wayland", "hyprland"):
        value = capabilities.get(name)
        if isinstance(value, dict) and value.get("result") in RESULTS:
            yield name, value


def certification_summary(capabilities: dict[str, Any], records: dict[str, dict[str, str]]) -> dict[str, Any]:
    counts = {result: 0 for result in RESULTS}
    for _, value in iter_checks(capabilities):
        counts[str(value["result"])] += 1
    recorded_results = [record["result"] for record in records.values() if record.get("result") in RESULTS]
    if not recorded_results:
        status = "Untested"
    elif "Fail" in recorded_results:
        status = "Fail"
    elif all(result == "Pass" for result in recorded_results):
        status = "Pass"
    elif any(result == "Untested" for result in recorded_results):
        status = "Untested"
    elif any(result == "Unavailable" for result in recorded_results):
        status = "Unavailable"
    elif any(result == "Skipped" for result in recorded_results):
        status = "Skipped"
    else:
        status = "Untested"
    return {
        "status": status,
        "resultCounts": counts,
        "recordedCount": len(recorded_results),
        "recordedResults": recorded_results,
    }


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


def check(
    name: str,
    available: bool,
    reason: str,
    source: str,
    details: dict[str, Any] | None = None,
    result: str | None = None,
) -> dict[str, Any]:
    selected_result = result or ("Untested" if available else "Unavailable")
    if selected_result not in RESULTS:
        raise ValueError(f"invalid hardware result: {selected_result}")
    return {
        "name": name,
        "available": bool(available),
        "status": "available" if available else "unavailable",
        "result": selected_result,
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


def explicit_available(value: Any) -> bool:
    if isinstance(value, dict):
        if "available" in value:
            return bool(value["available"])
        if "supported" in value:
            return bool(value["supported"])
        return bool(value)
    return bool(value)


def multitasking_results(payload: dict[str, Any], source: str) -> dict[str, dict[str, Any]]:
    """Expose the guided multitasking matrix without turning fixtures into certification."""

    declaration = payload.get("multitasking", {}) if isinstance(payload, dict) else {}
    entries = declaration.get("scenarios", declaration.get("tests", {})) if isinstance(declaration, dict) else {}
    if not isinstance(entries, dict):
        entries = {}
    result: dict[str, dict[str, Any]] = {}
    for name, label in MULTITASKING_SCENARIOS:
        entry = entries.get(name)
        if source == "fixture":
            available = entry is not None and explicit_available(entry)
            outcome = "Untested" if available else "Unavailable"
            reason = (
                "fixture declares this scenario; interactive hardware execution was not performed"
                if available
                else "fixture does not declare this scenario"
            )
        else:
            available = False
            outcome = "Untested"
            reason = "guided live hardware test required; a session probe cannot infer interaction success"
        result[name] = check(
            f"multitasking.{name}",
            available,
            reason,
            source,
            {"label": label, "declared": entry is not None},
            outcome,
        )
    return result


def certification_results(fixture: dict[str, Any], touch: Any, stylus: Any, sensors: dict[str, Any]) -> dict[str, dict[str, Any]]:
    devices = fixture.get("devices") if isinstance(fixture.get("devices"), dict) else {}
    keyboards = fixture.get("keyboard", devices.get("keyboards", []))
    detachable = fixture.get("detachableKeyboard", devices.get("detachableKeyboard", []))
    displays = fixture.get("display", fixture.get("displays", fixture.get("outputs", [])))
    multitouch = fixture.get("multitouch", {})
    orientation = fixture.get("orientation", sensors.get("available", sensors.get("accelerometer", False)))
    osk = fixture.get("osk", {})
    features = feature_results(stylus, "fixture")
    lifecycle = lifecycle_results(fixture)
    return {
        "display": check("display", bool(displays), "fixture reports a display/output" if displays else "fixture has no display/output", "fixture"),
        "touch": check("touch", bool(touch), "fixture reports touchscreen input" if touch else "fixture has no touchscreen input", "fixture"),
        "multitouch": check("multitouch", explicit_available(multitouch), "fixture reports multitouch coverage" if explicit_available(multitouch) else "fixture has no multitouch coverage", "fixture"),
        "stylus": check("stylus", bool(stylus), "fixture reports stylus input" if stylus else "fixture has no stylus input", "fixture"),
        "pressure": features["pressure"],
        "tilt": features["tilt"],
        "eraser": features["eraser"],
        "stylusButtons": features["buttons"],
        "keyboard": check("keyboard", bool(keyboards), "fixture reports keyboard input" if keyboards else "fixture has no keyboard input", "fixture"),
        "detachableKeyboard": check("detachableKeyboard", explicit_available(detachable), "fixture reports detachable keyboard" if explicit_available(detachable) else "fixture has no detachable keyboard", "fixture"),
        "orientation": check("orientation", explicit_available(orientation), "fixture reports orientation capability" if explicit_available(orientation) else "fixture has no orientation capability", "fixture"),
        "osk": check("osk", explicit_available(osk), "fixture reports OSK coverage" if explicit_available(osk) else "fixture has no OSK coverage", "fixture"),
        "suspendResume": lifecycle["suspendResume"],
        "multiMonitor": check("multiMonitor", explicit_available(fixture.get("multiMonitor", False)), "fixture reports multi-monitor coverage" if explicit_available(fixture.get("multiMonitor", False)) else "fixture has no multi-monitor coverage", "fixture"),
    }


def live_certification_results(devices: dict[str, Any], monitors: Any, touch: Any, stylus: Any, sensors: dict[str, Any]) -> dict[str, dict[str, Any]]:
    keyboards = devices.get("keyboards", []) if isinstance(devices, dict) else []
    detachable = [item for item in records(keyboards) if item.get("detachable") is True or str(item.get("transport", "")).lower() == "bluetooth"]
    features = feature_results(stylus, "hyprctl devices")
    return {
        "display": check("display", bool(monitors), "Hyprland exposed monitors" if monitors else "no monitors exposed", "hyprctl monitors"),
        "touch": check("touch", bool(touch), "Hyprland exposed touchscreen devices" if touch else "no touchscreen exposed", "hyprctl devices"),
        "multitouch": check("multitouch", False, "interactive multitouch fixture required", "live-session"),
        "stylus": check("stylus", bool(stylus), "Hyprland exposed tablet devices" if stylus else "no stylus exposed", "hyprctl devices"),
        "pressure": features["pressure"],
        "tilt": features["tilt"],
        "eraser": features["eraser"],
        "stylusButtons": features["buttons"],
        "keyboard": check("keyboard", bool(keyboards), "Hyprland exposed keyboard devices" if keyboards else "no keyboard exposed", "hyprctl devices"),
        "detachableKeyboard": check("detachableKeyboard", bool(detachable), "live device metadata reports detachable/Bluetooth keyboard" if detachable else "no detachable keyboard exposed", "hyprctl devices"),
        "orientation": check("orientation", bool(sensors.get("autoRotationSupported", False)), "sensor-info reports orientation support" if sensors.get("autoRotationSupported", False) else "orientation sensor unavailable", "input/sensor-info.sh"),
        "osk": check("osk", False, "interactive text-focus fixture required", "live-session"),
        "suspendResume": check("suspendResume", False, "interactive suspend/resume fixture required", "live-session"),
        "multiMonitor": check("multiMonitor", isinstance(monitors, list) and len(monitors) > 1, "Hyprland exposed multiple monitors" if isinstance(monitors, list) and len(monitors) > 1 else "single/no monitor exposed", "hyprctl monitors"),
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
        "multitasking": multitasking_results(fixture, "fixture"),
        "certification": certification_results(fixture, touch, stylus, sensors),
    }


def live_result() -> dict[str, Any]:
    devices, devices_reason = command_json(["hyprctl", "devices", "-j"])
    if not isinstance(devices, dict):
        devices = {}
    touch = devices.get("touch", devices.get("touchDevices", []))
    stylus = devices.get("tablets", devices.get("tabletTools", []))
    monitors, _ = command_json(["hyprctl", "monitors", "-j"])
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
        "multitasking": multitasking_results({}, "live-session"),
        "certification": live_certification_results(devices, monitors, touch, stylus, sensors),
    }


def guided_result(name: str, label: str) -> str:
    allowed = {value.lower(): value for value in RESULTS}
    while True:
        sys.stderr.write(f"[{name}] {label}\nResult ({', '.join(RESULTS)}): ")
        sys.stderr.flush()
        value = sys.stdin.readline()
        if not value:
            raise ValueError("guided hardware test ended before a result was recorded")
        normalized = value.strip().lower()
        if normalized in allowed:
            return allowed[normalized]
        sys.stderr.write("Please enter one of: " + ", ".join(RESULTS) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=pathlib.Path)
    parser.add_argument("--session", type=pathlib.Path, help="private resumable certification session")
    parser.add_argument("--resume", action="store_true", help="resume an existing --session instead of creating one")
    parser.add_argument(
        "--record",
        action="append",
        default=[],
        metavar="NAME=RESULT",
        help="record a live hardware result: Pass, Fail, Unavailable, Skipped, or Untested",
    )
    parser.add_argument("--confirm-hardware", action="store_true", help="confirm that this is a real hardware session")
    parser.add_argument("--guided", action="store_true", help="run the multitasking matrix as an interactive live-hardware checklist")
    parser.add_argument("--report", type=pathlib.Path, help="write the sanitized JSON report to a private file")
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
        if args.resume and not args.session:
            raise ValueError("--resume requires --session")
        if args.record and not args.session:
            raise ValueError("--record requires --session so evidence is not lost")
        if args.guided and mode != "live-probe":
            raise ValueError("guided hardware tests require a live session; fixture evidence cannot be certified")
        if args.guided and not args.session:
            raise ValueError("--guided requires --session so evidence is resumable and private")
        if args.guided and not sys.stdin.isatty():
            raise ValueError("--guided requires an interactive terminal")
        if args.confirm_hardware and mode != "live-probe":
            raise ValueError("fixture evidence cannot be confirmed as hardware")

        session: dict[str, Any] | None = None
        if args.session:
            session_path = args.session.expanduser()
            if args.resume:
                session = read_session(session_path)
                if session["mode"] != mode:
                    raise ValueError("certification session mode does not match the current probe")
            else:
                if session_path.exists() or session_path.is_symlink():
                    raise ValueError("certification session already exists; use --resume")
                session = new_session(mode)
            if args.confirm_hardware:
                session["hardwareConfirmed"] = True
            records_to_apply = dict(session.get("records", {}))
            for raw_record in args.record:
                name, result = parse_record(raw_record)
                records_to_apply[name] = {"result": result, "recordedAt": timestamp()}
            if args.guided:
                if not session.get("hardwareConfirmed", False):
                    raise ValueError("--guided requires --confirm-hardware for a new or unconfirmed session")
                for name, label in MULTITASKING_SCENARIOS:
                    target = f"multitasking.{name}"
                    if target not in records_to_apply:
                        records_to_apply[target] = {"result": guided_result(name, label), "recordedAt": timestamp()}
            applied_records = apply_manual_records(
                capabilities,
                records_to_apply,
                mode,
                bool(session.get("hardwareConfirmed", False)),
            )
            session["records"] = applied_records
            session["updatedAt"] = timestamp()
            write_private_json(session_path, session)
        else:
            applied_records = {}

        summary = certification_summary(capabilities, applied_records)
        hardware_confirmed = bool(session and session.get("hardwareConfirmed", False))
        real_hardware_validated = bool(
            mode == "live-probe"
            and hardware_confirmed
            and any(record.get("result") in {"Pass", "Fail"} for record in applied_records.values())
        )
        if args.report:
            report_path = args.report.expanduser()
            if args.session and report_path == args.session.expanduser():
                raise ValueError("--report and --session must be different files")
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return EX_CONFIG
    payload = {
        "schemaVersion": 1,
        "ok": True,
        "generatedAt": timestamp(),
        "mode": mode,
        "realHardwareValidated": real_hardware_validated,
        "certification": {
            **summary,
            "evidence": "manual-confirmed" if real_hardware_validated else ("fixture" if mode == "fixture" else "probe-only"),
            "sessionPresent": bool(session),
        },
        "guided": {
            "available": mode == "live-probe",
            "interactive": mode == "live-probe" and sys.stdin.isatty(),
            "requiresConfirmHardware": True,
            "scenarioCount": len(MULTITASKING_SCENARIOS),
        },
        "note": "Capability probe only; unavailable backends are not simulated. Fixture evidence never certifies hardware.",
        "capabilities": capabilities,
    }
    if args.report:
        try:
            write_private_json(args.report, payload)
        except (OSError, ValueError) as exc:
            print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
            return EX_CONFIG
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
