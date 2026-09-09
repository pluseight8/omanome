#!/usr/bin/env python3
"""Validate that the release version is synchronized across public metadata."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected", nargs="?", help="require this exact version")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable report")
    args = parser.parse_args()

    manifest = load_json(ROOT / "manifest.json")
    compatibility = load_json(ROOT / "hypr/omanome-hypr/compatibility.json")
    defaults = load_json(ROOT / "config/defaults.json")
    schema = load_json(ROOT / "config/schema.json")
    companion_source = (ROOT / "hypr/omanome-hypr/omanome-hypr.cpp").read_text(encoding="utf-8")
    native_manifest = (ROOT / "input/omanome-input/Cargo.toml").read_text(encoding="utf-8")
    native_lock = (ROOT / "input/omanome-input/Cargo.lock").read_text(encoding="utf-8")
    native_source = (ROOT / "input/omanome-input/src/main.rs").read_text(encoding="utf-8")
    version = str(manifest.get("version", ""))
    errors: list[str] = []
    if not SEMVER.fullmatch(version):
        errors.append(f"manifest version is not semver: {version!r}")
    if args.expected and version != args.expected:
        errors.append(f"expected {args.expected}, found {version}")
    if compatibility.get("pluginVersion") != version:
        errors.append("companion pluginVersion is out of sync")
    if compatibility.get("build", {}).get("pluginBuild") != version:
        errors.append("companion build.pluginBuild is out of sync")
    if f'constexpr std::string_view kPluginVersion = "{version}";' not in companion_source:
        errors.append("companion source version is out of sync")
    if not re.search(rf'^version\s*=\s*"{re.escape(version)}"$', native_manifest, re.MULTILINE):
        errors.append("native helper Cargo.toml version is out of sync")
    if f'name = "omanome-input"\nversion = "{version}"' not in native_lock:
        errors.append("native helper Cargo.lock version is out of sync")
    if f'omanome-input {{PROTOCOL_VERSION}} ({version})' not in native_source:
        errors.append("native helper runtime version is out of sync")
    if defaults.get("schemaVersion") != 2 or schema.get("properties", {}).get("schemaVersion", {}).get("const") != 2:
        errors.append("config schema must remain at schemaVersion 2")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    readme_ru = (ROOT / "README.ru.md").read_text(encoding="utf-8")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    compatibility_doc = (ROOT / "docs/COMPATIBILITY.md").read_text(encoding="utf-8")
    features_doc = (ROOT / "docs/FEATURES.md").read_text(encoding="utf-8")
    hardware_doc = (ROOT / "docs/HARDWARE.md").read_text(encoding="utf-8")
    release_doc = (ROOT / "docs/RELEASE.md").read_text(encoding="utf-8")
    release_family = ".".join(version.split(".")[:2])
    if f"runnable {version} release" not in readme:
        errors.append("README.md does not identify the current runnable release")
    if f"версии {version}" not in readme_ru:
        errors.append("README.ru.md does not identify the current phase")
    if f"## {version}" not in changelog:
        errors.append("CHANGELOG.md has no current release heading")
    if f"# Compatibility snapshot ({version})" not in compatibility_doc:
        errors.append("docs/COMPATIBILITY.md does not identify the current snapshot")
    if f"# Omanome {release_family} feature truth matrix" not in features_doc:
        errors.append("docs/FEATURES.md does not identify the current feature matrix")
    if f"# Omanome {release_family} hardware validation and certification" not in hardware_doc:
        errors.append("docs/HARDWARE.md does not identify the current hardware matrix")
    if f"v{version}" not in release_doc or f"omanome-{version}.tar.gz" not in release_doc:
        errors.append("docs/RELEASE.md does not identify the current tag and archive")
    report = {
        "schemaVersion": 1,
        "version": version,
        "expected": args.expected,
        "synchronized": not errors,
        "errors": errors,
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    elif errors:
        for error in errors:
            print(f"FAIL: {error}")
    else:
        print(f"version: {version} (metadata synchronized)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
