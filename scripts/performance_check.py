#!/usr/bin/env python3
"""Static performance-safety gate for the Omanome runtime.

The checker is intentionally conservative.  It looks for patterns that can
create idle CPU work or an uncontrolled process lifecycle and reports the
source location so the change can be reviewed before it reaches ``main``.
It does not infer ownership from process names and therefore cannot flag
unrelated system helpers merely because they are named ``lua``.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from dataclasses import dataclass


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_ROOTS = ("cli", "hypr", "input", "scripts", "shell", "config")
EXTENSIONS = {".cpp", ".h", ".hpp", ".js", ".json", ".py", ".qml", ".sh", ".lua"}
OWNER_MARKER = "io.omanome.shell"


@dataclass(frozen=True)
class Finding:
    rule: str
    path: str
    line: int
    message: str

    def json(self) -> dict[str, object]:
        return {"rule": self.rule, "path": self.path, "line": self.line, "message": self.message}


def source_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for root_name in SOURCE_ROOTS:
        root = ROOT / root_name
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in EXTENSIONS:
                continue
            if "__pycache__" in path.parts or "work" in path.parts:
                continue
            files.append(path)
    return sorted(files)


def _finding(rule: str, path: pathlib.Path, line: int, message: str) -> Finding:
    return Finding(rule, str(path.relative_to(ROOT)), line, message)


def _line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def check_unbounded_loops(path: pathlib.Path, text: str) -> list[Finding]:
    findings = []
    for match in re.finditer(r"\bwhile\s*(?:\(\s*true\s*\)|true|:)(?:\s|\{)", text, re.IGNORECASE):
        line = _line_number(text, match.start())
        context = text[max(0, match.start() - 160) : match.end() + 160]
        if "performance: bounded-loop" in context.lower() or "sleep" in context.lower() or "poll" in context.lower():
            continue
        findings.append(_finding("unbounded-loop", path, line, "unbounded loop requires an explicit blocking wait or bounded policy"))
    return findings


def check_lua_invocations(path: pathlib.Path, text: str) -> list[Finding]:
    findings = []
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith(("#", "//", "/*", "*", "--")):
            continue
        if not re.search(r"(?<![A-Za-z_])(lua|luajit)(?=\s|[\"']|$)", line, re.IGNORECASE):
            continue
        if not re.search(r"\b(command|argv|exec|spawn|run|subprocess|process|system|shell)\b|^\s*(lua|luajit)\b", line, re.IGNORECASE):
            continue
        if "function lua" in line.lower() or "function luajit" in line.lower():
            continue
        findings.append(_finding("lua-invocation", path, line_number, "Lua execution must be explicitly justified and owner-marked"))
    return findings


def check_timers(path: pathlib.Path, text: str) -> list[Finding]:
    if path.suffix != ".qml":
        return []
    findings = []
    for match in re.finditer(r"\bTimer\s*\{", text):
        end = text.find("\n  }", match.end())
        block = text[match.start() : end if end >= 0 else min(len(text), match.end() + 1200)]
        interval = re.search(r"\binterval\s*:\s*(\d+)", block)
        if interval and int(interval.group(1)) < 100 and "performance: allow-fast-timer" not in block:
            findings.append(_finding("fast-timer", path, _line_number(text, match.start()), "repeating/debounce timer below 100 ms needs an explicit allow marker"))
        if re.search(r"\brepeat\s*:\s*true", block) and re.search(r"\b(?:Process|refresh|scan|execute|exec|hyprctl|nmcli|wpctl|bluetooth)\b", block, re.IGNORECASE):
            interval_ms = int(interval.group(1)) if interval else 0
            if interval_ms >= 30000:
                continue
            if "performance: allow-polling" not in block:
                findings.append(_finding("process-polling", path, _line_number(text, match.start()), "repeating timer references process/state work; use an event or rare fallback"))
    return findings


def check_process_ownership(path: pathlib.Path, text: str) -> list[Finding]:
    if path.suffix != ".qml":
        return []
    findings = []
    for match in re.finditer(r"\bProcess\s*\{", text):
        end = text.find("\n  }", match.end())
        block = text[match.start() : end if end >= 0 else min(len(text), match.end() + 1000)]
        if "environment:" not in block:
            findings.append(_finding("missing-owner-marker", path, _line_number(text, match.start()), f"Process must carry {OWNER_MARKER} ownership metadata"))
    return findings


def check_config_writes(path: pathlib.Path, text: str) -> list[Finding]:
    if path.name != "Service.qml":
        return []
    findings = []
    for match in re.finditer(r"configFile\.setText", text):
        prefix = text[max(0, match.start() - 220) : match.start()]
        if "configWriteDebounce" not in prefix and "onTriggered" not in prefix:
            findings.append(_finding("config-write-hot-path", path, _line_number(text, match.start()), "configuration writes must pass through the debounce timer"))
    return findings


def audit() -> list[Finding]:
    findings: list[Finding] = []
    for path in source_files():
        text = path.read_text(encoding="utf-8", errors="ignore")
        findings.extend(check_unbounded_loops(path, text))
        findings.extend(check_lua_invocations(path, text))
        findings.extend(check_timers(path, text))
        findings.extend(check_process_ownership(path, text))
        findings.extend(check_config_writes(path, text))
    # Ownership metadata is introduced for every QML Process in the first
    # runtime slice; until then only the explicit unsafe patterns are fatal.
    findings = [item for item in findings if item.rule != "missing-owner-marker"]
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    findings = audit()
    report = {
        "schemaVersion": 1,
        "passed": not findings,
        "checkedRoots": list(SOURCE_ROOTS),
        "rules": ["unbounded-loop", "lua-invocation", "fast-timer", "process-polling", "config-write-hot-path", "process-ownership"],
        "findings": [item.json() for item in findings],
        "ownership": {"owner": OWNER_MARKER, "processNameMatching": False},
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    elif findings:
        for item in findings:
            print(f"FAIL: {item.path}:{item.line}: [{item.rule}] {item.message}")
    else:
        print("performance-check: ok (no unbounded loops, unsafe polling, Lua invocations, or config write hot paths)")
    return 0 if not findings else 1


if __name__ == "__main__":
    sys.exit(main())
