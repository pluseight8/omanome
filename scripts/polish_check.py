#!/usr/bin/env python3
"""Aggregate the 1.4 polish and regression-safety checks.

This gate is deliberately deterministic and local.  It checks the repository
contract that can be verified without a compositor or physical hardware:
source integrity, executable modes, metadata parity, privacy boundaries,
accessibility wiring, performance findings, and bounded model behavior.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import stat
import subprocess
import sys
from dataclasses import dataclass
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_EXTENSIONS = {
    ".cpp",
    ".h",
    ".hpp",
    ".js",
    ".json",
    ".lock",
    ".md",
    ".py",
    ".qml",
    ".rs",
    ".sh",
    ".toml",
    ".xml",
    ".yaml",
    ".yml",
}
SPECIAL_SOURCE_NAMES = {"Makefile", "omanome"}
EXCLUDED_PARTS = {
    ".git",
    ".pytest_cache",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "target",
}


@dataclass(frozen=True)
class Check:
    name: str
    passed: bool
    detail: str

    def json(self) -> dict[str, Any]:
        return {"name": self.name, "passed": self.passed, "detail": self.detail}


class PolishFailure(RuntimeError):
    """Raised when a subprocess or structural assertion cannot be verified."""


def relative(path: pathlib.Path) -> str:
    return path.relative_to(ROOT).as_posix()


def source_files() -> list[pathlib.Path]:
    result: list[pathlib.Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in EXCLUDED_PARTS for part in path.parts):
            continue
        if path.name in SPECIAL_SOURCE_NAMES or path.suffix.lower() in SOURCE_EXTENSIONS:
            result.append(path)
    return sorted(result)


def read_sources() -> tuple[dict[pathlib.Path, str], list[str]]:
    texts: dict[pathlib.Path, str] = {}
    errors: list[str] = []
    for path in source_files():
        try:
            data = path.read_bytes()
        except OSError as error:
            errors.append(f"{relative(path)} cannot be read: {error}")
            continue
        if not data:
            errors.append(f"{relative(path)} is empty")
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as error:
            errors.append(f"{relative(path)} is not valid UTF-8: {error}")
            continue
        if "\ufffd" in text:
            errors.append(f"{relative(path)} contains the Unicode replacement character")
        texts[path] = text
    return texts, errors


def expected_executable(path: pathlib.Path, text: str | None = None) -> bool:
    rel = pathlib.Path(relative(path))
    if rel == pathlib.Path("cli/omanome"):
        return True
    if rel.parts and rel.parts[0] == "input" and path.suffix.lower() == ".sh":
        return True
    if rel.parts and rel.parts[0] == "scripts" and path.suffix.lower() == ".py":
        first_line = (text or "").splitlines()[:1]
        return bool(first_line and first_line[0].startswith("#!"))
    return False


def check_source_integrity(texts: dict[pathlib.Path, str], errors: list[str]) -> Check:
    structural = {
        "shell/Service.qml": (1000, ("import Quickshell", "function shutdown", "DeviceGraphModel", "property bool masterEnabled")),
        "cli/omanome": (1000, ("#!/usr/bin/env bash", "repository_url", "install_cmd")),
        "shell/models/DeviceGraph.js": (100, ("function fromSnapshot", "function applyEvent", "function publicSnapshot", "var api")),
        "shell/models/Config.js": (100, ("function defaults", "function migrateDetailed", "var CURRENT_RELEASE")),
        "input/omanome-input/src/main.rs": (100, ("const PROTOCOL_VERSION", "fn main", "input.ack")),
        "shell/models/I18n.js": (100, ("var en", "var ru", "function text")),
    }
    problems = list(errors)
    for name, (minimum_lines, markers) in structural.items():
        path = ROOT / name
        text = texts.get(path)
        if text is None:
            problems.append(f"{name} is missing from the UTF-8 source set")
            continue
        if len(text.splitlines()) < minimum_lines:
            problems.append(f"{name} has {len(text.splitlines())} lines; expected at least {minimum_lines}")
        for marker in markers:
            if marker not in text:
                problems.append(f"{name} is missing structural marker {marker!r}")
    detail = "; ".join(problems[:8]) if problems else f"{len(texts)} UTF-8 source files and structural markers verified"
    if len(problems) > 8:
        detail += f" (+{len(problems) - 8} more)"
    return Check("source-integrity", not problems, detail)


def check_executable_modes(texts: dict[pathlib.Path, str]) -> Check:
    mismatches: list[str] = []
    expected: list[str] = []
    actual_executable: list[str] = []
    for path in source_files():
        if path not in texts:
            continue
        should_be_executable = expected_executable(path, texts[path])
        is_executable = bool(path.stat().st_mode & stat.S_IXUSR)
        name = relative(path)
        if should_be_executable:
            expected.append(name)
        if is_executable:
            actual_executable.append(name)
        if should_be_executable != is_executable:
            wanted = "executable" if should_be_executable else "non-executable"
            mismatches.append(f"{name} is {('executable' if is_executable else 'non-executable')}; expected {wanted}")
    detail = (
        "; ".join(mismatches[:8])
        if mismatches
        else f"{len(expected)} expected executables; no unexpected executable source modes"
    )
    if len(mismatches) > 8:
        detail += f" (+{len(mismatches) - 8} more)"
    return Check("executable-modes", not mismatches, detail)


def run_command(args: list[str], timeout: float = 60.0) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise PolishFailure(f"command {' '.join(args)!r} failed to run: {error}") from error


def command_json(args: list[str], timeout: float = 60.0) -> Any:
    result = run_command(args, timeout=timeout)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().replace("\n", " ")
        raise PolishFailure(f"command {' '.join(args)!r} exited {result.returncode}: {detail[:360]}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise PolishFailure(f"command {' '.join(args)!r} did not emit JSON: {error}") from error


def node_json(expression: str, timeout: float = 60.0) -> Any:
    return command_json(["node", "-e", expression], timeout=timeout)


def check_config_consistency() -> Check:
    try:
        defaults = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
        schema = json.loads((ROOT / "config/schema.json").read_text(encoding="utf-8"))
        js_defaults = node_json(
            "const C=require('./shell/models/Config.js'); process.stdout.write(JSON.stringify(C.defaults()));"
        )
        if defaults != js_defaults:
            return Check("config-consistency", False, "config/defaults.json differs from Config.defaults()")
        properties = schema.get("properties", {})
        missing = sorted(set(defaults) - set(properties))
        if missing:
            return Check("config-consistency", False, f"schema is missing default keys: {', '.join(missing)}")
        if defaults.get("schemaVersion") != 2 or properties.get("schemaVersion", {}).get("const") != 2:
            return Check("config-consistency", False, "config schemaVersion must remain 2")
        return Check("config-consistency", True, f"{len(defaults)} default sections match Config.js and schema")
    except (OSError, json.JSONDecodeError, PolishFailure) as error:
        return Check("config-consistency", False, str(error))


def check_i18n(texts: dict[pathlib.Path, str]) -> Check:
    try:
        result = node_json(
            "const fs=require('fs'); const vm=require('vm'); const context={}; "
            "vm.runInNewContext(fs.readFileSync('shell/models/I18n.js','utf8')+"
            "'; this.__i18n={en:Object.keys(en).sort(),ru:Object.keys(ru).sort(),values:[en,ru]};',context); "
            "process.stdout.write(JSON.stringify(context.__i18n));"
        )
        if result.get("en") != result.get("ru"):
            return Check("i18n-parity", False, "English and Russian key sets differ")
        values = result.get("values", [])
        if len(values) != 2 or any(not isinstance(value, str) or not value.strip() for locale in values for value in locale.values()):
            return Check("i18n-parity", False, "a locale contains an empty or non-string value")
        return Check("i18n-parity", True, f"{len(result.get('en', []))} keys are present in both locales")
    except (PolishFailure, TypeError, AttributeError) as error:
        return Check("i18n-parity", False, str(error))


def check_version() -> Check:
    try:
        result = command_json([sys.executable, "scripts/validate_version.py", "--json"])
        if not result.get("synchronized"):
            return Check("version-consistency", False, "; ".join(result.get("errors", [])))
        return Check("version-consistency", True, f"metadata synchronized at {result.get('version')}")
    except PolishFailure as error:
        return Check("version-consistency", False, str(error))


def check_performance() -> Check:
    try:
        sys.path.insert(0, str(ROOT / "scripts"))
        import performance_check

        findings = performance_check.audit()
        if findings:
            first = findings[0]
            return Check("performance-safety", False, f"{first.path}:{first.line} [{first.rule}] {first.message}")
        return Check("performance-safety", True, "no unsafe timers, polling, unbounded loops, or hot-path writes")
    except (ImportError, OSError, UnicodeError) as error:
        return Check("performance-safety", False, str(error))


def check_accessibility(texts: dict[pathlib.Path, str]) -> Check:
    action = texts.get(ROOT / "shell/components/ActionButton.qml", "")
    tokens = texts.get(ROOT / "shell/components/DesignTokens.qml", "")
    settings = texts.get(ROOT / "shell/views/Settings.qml", "")
    required = {
        "ActionButton Accessible.name": "Accessible.name",
        "ActionButton Accessible.description": "Accessible.description",
        "ActionButton role": "Accessible.role: Accessible.Button",
        "ActionButton tab focus": "activeFocusOnTab",
        "ActionButton Return key": "Keys.onReturnPressed",
        "ActionButton Space key": "Keys.onSpacePressed",
        "ActionButton focus ring": "focusRing",
        "DesignTokens reduced motion": "reducedMotion",
        "DesignTokens high contrast": "highContrast",
        "DesignTokens text scale": "textScale",
        "Settings accessibility": "accessibility.screenReaderHints",
    }
    missing = [name for name, marker in required.items() if marker not in (action if name.startswith("ActionButton") else tokens if name.startswith("DesignTokens") else settings)]
    return Check(
        "accessibility-critical-controls",
        not missing,
        "shared control semantics, keyboard activation, focus ring, and accessibility tokens verified"
        if not missing
        else f"missing: {', '.join(missing)}",
    )


def check_privacy(texts: dict[pathlib.Path, str]) -> Check:
    x11_tool = "xdo" + "tool"
    shell_replacement = "gnome-shell" + r"\s+--replace"
    process_broadcast = r"\b(?:" + "pk" + "ill" + "|" + "kill" + "all" + r")\b"
    forbidden = re.compile(x11_tool + "|" + shell_replacement + "|" + process_broadcast, re.IGNORECASE)
    findings: list[str] = []
    runtime_roots = {"cli", "hypr", "input", "shell", "config"}
    for path, text in texts.items():
        name = relative(path)
        root_name = path.relative_to(ROOT).parts[0]
        if name == "scripts/polish_check.py" or root_name not in runtime_roots or path.suffix.lower() in {".md", ".toml", ".lock"}:
            continue
        match = forbidden.search(text)
        if match:
            findings.append(f"{name} contains forbidden replacement/process pattern {match.group(0)!r}")
    markers = {
        "shell/models/Privacy.js": "function boundary",
        "scripts/support_bundle.py": "redact",
        "input/omanome-input/protocol.json": '"typedTextEmitted": false',
        "shell/Service.qml": 'typedTextLogged: false',
    }
    for name, marker in markers.items():
        if marker not in texts.get(ROOT / name, ""):
            findings.append(f"{name} is missing privacy marker {marker!r}")
    return Check(
        "privacy-boundary",
        not findings,
        "replacement commands are absent and runtime/support-bundle privacy markers are present"
        if not findings
        else "; ".join(findings[:8]),
    )


FUZZ_SCRIPT = r"""
const R = require('./shell/models/Responsive.js');
const L = require('./shell/models/LayoutEngine.js');
const G = require('./shell/models/DeviceGraph.js');
const C = require('./shell/models/Config.js');
const Cal = require('./shell/models/Calibration.js');
let seed = 0x14f00d;
function next() { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; }
function ok(value, message) { if (!value) throw new Error(message); }
function finite(value) { return typeof value === 'number' && Number.isFinite(value); }
function right(rect) { return rect.x + rect.width; }
function bottom(rect) { return rect.y + rect.height; }
function hexId() { return ('00000000' + (seed >>> 0).toString(16)).slice(-8) + ('00000000' + Math.floor(next() * 0xffffffff).toString(16)).slice(-8); }
for (let i = 0; i < 160; i++) {
  const width = 480 + Math.floor(next() * 4800);
  const height = 360 + Math.floor(next() * 3000);
  const scale = 0.5 + next() * 3.5;
  const input = ['mouse', 'touchpad', 'touch', 'stylus', 'keyboard'][i % 5];
  const mode = ['desktop', 'tablet', 'hybrid'][i % 3];
  const context = R.context(width, height, scale, input, mode, { textScale: 0.9 + next() * 0.6, touchTargetSize: i % 4 === 0 ? 'large' : 'default' });
  ok(finite(context.logicalWidth) && context.logicalWidth > 0, 'responsive logical width');
  ok(finite(context.logicalHeight) && context.logicalHeight > 0, 'responsive logical height');
  ok(finite(context.targetSize) && context.targetSize >= 40, 'responsive target size');
  const monitor = { x: -Math.floor(next() * 400), y: -Math.floor(next() * 300), width, height, scale, reserved: { top: Math.floor(next() * 24), right: Math.floor(next() * 16), bottom: Math.floor(next() * 32), left: Math.floor(next() * 16) } };
  const pair = L.splitPair(monitor, ['50/50', '40/60', '60/40', '33/67', '67/33'][i % 5], { gap: next() * 48 }, ['a', 'b']);
  const area = pair.usable;
  for (const slot of pair.slots) {
    const rect = slot.rect;
    ok([rect.x, rect.y, rect.width, rect.height].every(finite) && rect.width > 0 && rect.height > 0, 'layout slot bounds');
    ok(rect.x >= area.x - 2 && rect.y >= area.y - 2 && right(rect) <= right(area) + 2 && bottom(rect) <= bottom(area) + 2, 'layout slot escapes usable area');
  }
  const outputName = 'fixture-display-' + i;
  const graph = G.fromSnapshot({ backend: 'fixture', outputs: [{ name: outputName, width, height, internal: i % 2 === 0 }], touchscreens: [{ label: 'Fixture touch', path: '/dev/input/event' + i, serial: 'SERIAL-DEVICE-' + i, capabilities: { absolute: true } }] }, null, {});
  const updated = G.applyEvent(graph, { action: 'add', category: 'keyboard', device: { label: 'Fixture keyboard', id: 'fixture-keyboard-' + i, connected: true } }, {});
  const publicGraph = G.publicSnapshot(updated);
  ok(publicGraph.nodes.length <= G.BOUNDS.nodes && publicGraph.outputs.length <= G.BOUNDS.outputs && publicGraph.relationships.length <= G.BOUNDS.relationships, 'device graph bounds');
  const serializedGraph = JSON.stringify(publicGraph);
  ok(serializedGraph.indexOf('/dev/') < 0 && serializedGraph.indexOf('SERIAL-DEVICE') < 0, 'device graph privacy boundary');
  const config = C.defaults();
  config.general.profile = 'fuzz-profile-' + i;
  config.keyboard.layout = i % 2 ? 'ru' : 'auto';
  config.multitasking.layoutPersistence.maxRecent = 1 + (i % 12);
  config.deviceProfiles.profiles = { preserved: { id: 'profile-' + i } };
  config.deviceProfiles.calibrations.entries = { preserved: { id: 'cal-' + i, kind: 'touchscreen' } };
  const migrated = C.migrateDetailed(config);
  ok(migrated.ok && migrated.config.schemaVersion === C.CURRENT_SCHEMA_VERSION, 'config migration result');
  ok(migrated.config.general.profile === config.general.profile && migrated.config.keyboard.layout === config.keyboard.layout, 'config migration preserves sentinels');
  ok(migrated.config.multitasking.layoutPersistence.maxRecent === config.multitasking.layoutPersistence.maxRecent, 'multitasking migration preserves sentinel');
  ok(migrated.config.deviceProfiles.profiles.preserved.id === 'profile-' + i && migrated.config.deviceProfiles.calibrations.entries.preserved.id === 'cal-' + i, 'device profile migration preserves sentinels');
  const deviceId = 'device:touchscreen:' + hexId();
  const outputId = 'display:' + hexId();
  let calibration = Cal.beginTouch(deviceId, outputId, { absolute: true }, {});
  ok(calibration.phase === 'collecting', 'calibration starts');
  for (const target of Cal.TOUCH_TARGETS()) {
    const recorded = Cal.recordTouchSample(calibration, { targetId: target.id, actualX: target.x, actualY: target.y, coordinateSpace: 'normalized', outputId, real: true, source: 'native', timestamp: i });
    ok(recorded.accepted === true && recorded.state.samples.length <= Cal.TOUCH_TARGETS().length, 'calibration sample bound');
    calibration = recorded.state;
  }
  ok(calibration.phase === 'analyzed' && calibration.samples.length === Cal.TOUCH_TARGETS().length, 'calibration completes');
}
process.stdout.write(JSON.stringify({iterations: 160, seed: 0x14f00d, models: ['Responsive', 'LayoutEngine', 'DeviceGraph', 'Config', 'Calibration']}));
"""


def check_fuzz() -> Check:
    try:
        result = node_json(FUZZ_SCRIPT, timeout=90)
        if result.get("iterations") != 160:
            return Check("deterministic-fuzz-lite", False, "unexpected fuzz iteration count")
        return Check("deterministic-fuzz-lite", True, json.dumps(result, sort_keys=True))
    except PolishFailure as error:
        return Check("deterministic-fuzz-lite", False, str(error))


def run_checks() -> tuple[list[Check], dict[str, Any]]:
    texts, integrity_errors = read_sources()
    checks = [
        check_source_integrity(texts, integrity_errors),
        check_executable_modes(texts),
        check_config_consistency(),
        check_i18n(texts),
        check_version(),
        check_performance(),
        check_accessibility(texts),
        check_privacy(texts),
        check_fuzz(),
    ]
    fuzz = next((json.loads(item.detail) for item in checks if item.name == "deterministic-fuzz-lite" and item.passed), None)
    return checks, fuzz or {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit a machine-readable report")
    args = parser.parse_args()
    checks, fuzz = run_checks()
    report = {
        "schemaVersion": 1,
        "version": json.loads((ROOT / "manifest.json").read_text(encoding="utf-8")).get("version", "unknown"),
        "passed": all(item.passed for item in checks),
        "checks": [item.json() for item in checks],
        "fuzz": fuzz,
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        for item in checks:
            print(f"{'OK' if item.passed else 'FAIL'} {item.name}: {item.detail}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
