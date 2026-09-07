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
    if defaults.get("schemaVersion") != 2 or schema.get("properties", {}).get("schemaVersion", {}).get("const") != 2:
        errors.append("config schema must remain at schemaVersion 2")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    readme_ru = (ROOT / "README.ru.md").read_text(encoding="utf-8")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"runnable {version} release" not in readme:
        errors.append("README.md does not identify the current runnable release")
    if f"версии {version}" not in readme_ru:
        errors.append("README.ru.md does not identify the current phase")
    if f"## {version}" not in changelog:
        errors.append("CHANGELOG.md has no current release heading")
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
