#!/usr/bin/env python3
"""Audit source safety boundaries and report optional runtime capabilities."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_ROOTS = (ROOT / "cli", ROOT / "shell", ROOT / "input", ROOT / "hypr")
x11_tool_name = "xdo" + "tool"
FORBIDDEN = {
    "sudo": re.compile(r"(?:^|[;&|]\s*)sudo\s+|\[\s*['\"]sudo['\"]"),
    "pipeline-install": re.compile(r"curl[^\n|]*\|\s*(?:sh|bash)\b"),
    "x11-tool": re.compile(r"\b" + x11_tool_name + r"\b"),
    "bar-replacement": re.compile(r"gnome-shell\s+--replace"),
    "broadcast-kill": re.compile(r"\b(?:pkill|killall)\b"),
}
OPTIONAL_COMMANDS = (
    "nmcli", "bluetoothctl", "wpctl", "brightnessctl", "grim", "wf-recorder",
    "gdbus", "iio-sensor-proxy", "monitor-sensor", "hyprctl", "wtype",
)


def source_files():
    for root in SOURCE_ROOTS:
        if not root.exists():
            continue
        yield from (
            path for path in root.rglob("*")
            if path.is_file() and not path.is_symlink() and path.suffix.lower() not in {".md", ".markdown"}
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    findings = []
    for path in source_files():
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        relative = str(path.relative_to(ROOT))
        for name, pattern in FORBIDDEN.items():
            if pattern.search(content):
                findings.append({"rule": name, "path": relative})
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    if "bar" in manifest.get("kinds", []):
        findings.append({"rule": "replacement-bar-kind", "path": "manifest.json"})
    report = {
        "schemaVersion": 1,
        "clean": not findings,
        "findings": findings,
        "optionalCommands": {name: shutil.which(name) is not None for name in OPTIONAL_COMMANDS},
        "policy": {
            "noSudo": True,
            "noX11": True,
            "noSecondShell": True,
            "noBroadcastKill": True,
            "optionalBackendsFailClosed": True,
        },
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print("dependency audit: clean" if not findings else "dependency audit: FAIL")
        for finding in findings:
            print(f"FAIL: {finding['rule']} in {finding['path']}")
        available = [name for name, present in report["optionalCommands"].items() if present]
        print("available optional commands: " + (", ".join(available) if available else "none"))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
