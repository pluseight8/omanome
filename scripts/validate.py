#!/usr/bin/env python3
"""Static validation for the Omanome repository.

This intentionally mirrors the safety-relevant subset of the Omarchy Quattro
manifest contract without importing Omarchy's private QML implementation.
"""

from __future__ import annotations

import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"validate: {message}")


def read_json(path: pathlib.Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - diagnostic path
        fail(f"invalid JSON in {path.relative_to(ROOT)}: {exc}")


def safe_relative(value: object) -> bool:
    if not isinstance(value, str) or not value or value.startswith("/"):
        return False
    path = pathlib.PurePosixPath(value)
    return ".." not in path.parts and not value.startswith("~")


def validate_manifest() -> None:
    path = ROOT / "manifest.json"
    manifest = read_json(path)
    required = ("schemaVersion", "id", "name", "version", "author", "description", "kinds", "entryPoints")
    missing = [key for key in required if key not in manifest]
    if missing:
        fail(f"manifest missing {', '.join(missing)}")
    if manifest["schemaVersion"] != 1:
        fail("manifest schemaVersion must be 1")
    if "bar" in manifest["kinds"]:
        fail("Omanome must never declare the replacement 'bar' kind")
    allowed = {"service", "bar-widget", "panel", "overlay", "menu"}
    unknown = set(manifest["kinds"]) - allowed
    if unknown:
        fail(f"unknown plugin kinds: {sorted(unknown)}")
    for kind, entry in manifest["entryPoints"].items():
        if not safe_relative(entry):
            fail(f"unsafe entry point for {kind}: {entry!r}")
        target = ROOT / entry
        if not target.is_file():
            fail(f"entry point does not exist: {entry}")
    bar_widget = manifest.get("barWidget", {})
    if bar_widget.get("defaultSection", "center") not in {"left", "center", "right"}:
        fail("barWidget.defaultSection must be left, center, or right")
    for candidate in ROOT.rglob("*"):
        if candidate.is_symlink():
            fail(f"symlinks are not allowed in a plugin checkout: {candidate}")


def validate_config() -> None:
    defaults = read_json(ROOT / "config" / "defaults.json")
    schema = read_json(ROOT / "config" / "schema.json")
    if defaults.get("schemaVersion") != 2:
        fail("config/defaults.json must have schemaVersion 2")
    if schema.get("properties", {}).get("schemaVersion", {}).get("const") != 2:
        fail("config/schema.json must require schemaVersion 2")
    expected_sections = {
        "general", "appearance", "controlCenter", "adaptive", "tabletMode", "input", "deviceProfiles", "hardwareSetupProfiles", "calibration", "power", "quirks", "touch", "stylus", "windowControls",
        "quickSettings", "dock", "overview", "launcher", "keyboard", "clipboard",
        "notifications", "altTab", "blur", "effects", "rotation", "privacy",
        "animations", "performance", "applicationRules", "wobbly", "cube", "forceQuit",
        "shortcuts", "updates", "recovery", "diagnostics",
    }
    missing = sorted(expected_sections - defaults.keys())
    if missing:
        fail(f"config/defaults.json missing sections: {', '.join(missing)}")
    missing_schema = sorted(expected_sections - schema.get("properties", {}).keys())
    if missing_schema:
        fail(f"config/schema.json missing sections: {', '.join(missing_schema)}")


def main() -> int:
    validate_manifest()
    validate_config()
    print("manifest: ok (no replacement bar declared)")
    print("config: ok (schemaVersion 2; migrations 0->1->2)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
