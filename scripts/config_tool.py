#!/usr/bin/env python3
"""Safe, dependency-free Omanome configuration operations.

The graphical service and the CLI deliberately share the same migration
contract.  This helper is used for validation/import/export/diff operations;
it never replaces a future-schema file with defaults and all writes are
atomic, mode 0600, and refused when the destination is a symlink.
"""

from __future__ import annotations

import argparse
import copy
import difflib
import json
import os
import pathlib
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULTS_PATH = ROOT / "config" / "defaults.json"
CURRENT_SCHEMA_VERSION = 2
EX_USAGE = 2
EX_CONFIG = 78
EX_NOINPUT = 66
EX_CANTCREAT = 73
LKG_SUFFIX = ".lkg"
CORRUPT_SUFFIX = ".corrupt"


class ConfigError(Exception):
    def __init__(self, reason: str, message: str | None = None) -> None:
        self.reason = reason
        super().__init__(message or reason)


def load_defaults() -> dict[str, Any]:
    try:
        value = json.loads(DEFAULTS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:  # pragma: no cover - repository failure
        raise ConfigError("defaults-unavailable", str(exc)) from exc
    if not isinstance(value, dict):
        raise ConfigError("defaults-invalid", "config/defaults.json must contain an object")
    return value


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(result.get(key), dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def migration_zero_to_one(source: dict[str, Any], applied: list[str]) -> None:
    if isinstance(source.get("tablet"), dict) and "tabletMode" not in source:
        source["tabletMode"] = copy.deepcopy(source["tablet"])
    if isinstance(source.get("osk"), dict) and "keyboard" not in source:
        source["keyboard"] = copy.deepcopy(source["osk"])
    if "onboarding" not in source:
        source["onboarding"] = {
            "completed": True,
            "skipped": True,
            "version": 1,
            "privacyAcknowledged": False,
        }
    source["schemaVersion"] = 1
    applied.append("0->1")


def migration_one_to_two(source: dict[str, Any], applied: list[str]) -> None:
    source.setdefault(
        "onboarding",
        {"completed": True, "skipped": True, "version": 1, "privacyAcknowledged": False},
    )
    updates = source.setdefault("updates", {})
    if not isinstance(updates, dict):
        updates = source["updates"] = {}
    updates.setdefault("channel", "stable")
    updates.setdefault("automaticInstall", False)
    updates.setdefault("notify", True)
    updates.setdefault("rollbackRetention", 3)
    updates.setdefault("checkTimeoutSeconds", 8)
    updates.setdefault("healthTimeoutSeconds", 5)

    recovery = source.setdefault("recovery", {})
    if not isinstance(recovery, dict):
        recovery = source["recovery"] = {}
    recovery.setdefault("autoRollback", True)
    recovery.setdefault("safeModeOnCrash", True)
    recovery.setdefault("maxCrashAttempts", 2)
    recovery.setdefault("preserveFailedUpdates", True)

    diagnostics = source.setdefault("diagnostics", {})
    if not isinstance(diagnostics, dict):
        diagnostics = source["diagnostics"] = {}
    diagnostics.setdefault("logLevel", "info")
    diagnostics.setdefault("supportBundleRetention", 3)
    diagnostics.setdefault("redactPaths", True)
    diagnostics.setdefault("includeSystemCommands", True)
    source["schemaVersion"] = 2
    applied.append("1->2")


def migration_multitasking_1_1(source: dict[str, Any], applied: list[str]) -> None:
    defaults = load_defaults().get("multitasking", {})
    multitasking = source.setdefault("multitasking", {})
    if not isinstance(multitasking, dict):
        multitasking = source["multitasking"] = {}
    changed = False
    for section in ("tabletSwitcher", "layoutPersistence", "shortcuts"):
        if not isinstance(multitasking.get(section), dict):
            multitasking[section] = copy.deepcopy(defaults.get(section, {}))
            changed = True
    for section in ("tabletSwitcher", "layoutPersistence", "shortcuts"):
        target = multitasking[section]
        for key, value in defaults.get(section, {}).items():
            if key not in target:
                target[key] = copy.deepcopy(value)
                changed = True
    if changed and "multitasking-1.1-defaults" not in applied:
        applied.append("multitasking-1.1-defaults")


def fill_missing(target: dict[str, Any], template: dict[str, Any]) -> bool:
    changed = False
    for key, value in template.items():
        if key not in target:
            target[key] = copy.deepcopy(value)
            changed = True
        elif isinstance(target.get(key), dict) and isinstance(value, dict):
            if fill_missing(target[key], value):
                changed = True
    return changed


def legacy_adaptive_profile(source: dict[str, Any]) -> str:
    general = source.get("general")
    raw = general.get("profile", "") if isinstance(general, dict) else ""
    profile = str(raw).lower().replace("_", "-").replace(" ", "-")
    if profile in {"", "automatic", "default"}:
        return "auto"
    if profile in {"desktop", "tablet", "hybrid", "presentation", "gaming", "custom"}:
        return profile
    if profile in {"stylus", "gnome-like"}:
        return "hybrid"
    return "auto"


def migration_adaptive_1_2(source: dict[str, Any], applied: list[str]) -> None:
    defaults = load_defaults()
    changed = False
    had_adaptive = isinstance(source.get("adaptive"), dict)
    had_control_center = isinstance(source.get("controlCenter"), dict)

    if not had_control_center:
        source["controlCenter"] = copy.deepcopy(defaults.get("controlCenter", {}))
        changed = True
    elif fill_missing(source["controlCenter"], defaults.get("controlCenter", {})):
        changed = True

    if not had_adaptive:
        source["adaptive"] = copy.deepcopy(defaults.get("adaptive", {}))
        source["adaptive"]["profile"] = legacy_adaptive_profile(source)
        changed = True
    elif fill_missing(source["adaptive"], defaults.get("adaptive", {})):
        changed = True

    control_center = source["controlCenter"]
    widget = control_center.get("widget")
    if not isinstance(widget, dict):
        control_center["widget"] = copy.deepcopy(defaults["controlCenter"]["widget"])
        changed = True
    elif widget.get("position") not in {"left", "center", "right"}:
        widget["position"] = "right"
        changed = True

    if not isinstance(control_center.get("compactToggles"), list):
        control_center["compactToggles"] = copy.deepcopy(defaults["controlCenter"]["compactToggles"])
        changed = True
    if not isinstance(control_center.get("visibleModules"), list):
        control_center["visibleModules"] = copy.deepcopy(defaults["controlCenter"]["visibleModules"])
        changed = True
    if not isinstance(control_center.get("moduleOrder"), list):
        control_center["moduleOrder"] = copy.deepcopy(defaults["controlCenter"]["moduleOrder"])
        changed = True
    if not isinstance(source["adaptive"].get("deviceRules"), list):
        source["adaptive"]["deviceRules"] = []
        changed = True

    if changed and "adaptive-1.2-defaults" not in applied:
        applied.append("adaptive-1.2-defaults")


def migrate(value: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    if not isinstance(value, dict):
        raise ConfigError("invalid-root", "configuration root must be a JSON object")
    source = copy.deepcopy(value)
    raw_version = source.get("schemaVersion", 0)
    if isinstance(raw_version, bool) or not isinstance(raw_version, (int, float)):
        raise ConfigError("invalid-schema-version", "schemaVersion must be an integer")
    version = int(raw_version)
    if version != raw_version or version < 0:
        raise ConfigError("invalid-schema-version", "schemaVersion must be a non-negative integer")
    if version > CURRENT_SCHEMA_VERSION:
        raise ConfigError("future-schema", f"schemaVersion {version} is newer than supported {CURRENT_SCHEMA_VERSION}")
    applied: list[str] = []
    if version < 1:
        migration_zero_to_one(source, applied)
    if int(source.get("schemaVersion", 0)) < 2:
        migration_one_to_two(source, applied)
    migration_multitasking_1_1(source, applied)
    migration_adaptive_1_2(source, applied)
    normalized = deep_merge(load_defaults(), source)
    normalized["schemaVersion"] = CURRENT_SCHEMA_VERSION
    return normalized, {
        "from": version,
        "to": CURRENT_SCHEMA_VERSION,
        "applied": applied,
        "migrated": bool(applied),
    }


def validate(value: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(value, dict):
        return ["root must be an object"]
    if value.get("schemaVersion") != CURRENT_SCHEMA_VERSION:
        errors.append(f"schemaVersion must be {CURRENT_SCHEMA_VERSION}")
    defaults = load_defaults()
    for key in defaults:
        if key == "schemaVersion":
            continue
        if key not in value:
            errors.append(f"missing section: {key}")
        elif not isinstance(value[key], dict):
            errors.append(f"section must be an object: {key}")
    updates = value.get("updates")
    if isinstance(updates, dict) and updates.get("channel", "stable") not in {"stable", "beta", "main", "nightly"}:
        errors.append("updates.channel must be stable, beta, main, or nightly")
    recovery = value.get("recovery")
    if isinstance(recovery, dict) and not isinstance(recovery.get("maxCrashAttempts", 2), int):
        errors.append("recovery.maxCrashAttempts must be an integer")
    return errors


def read_json(path: str) -> Any:
    if path == "-":
        raw = sys.stdin.read()
        display = "stdin"
    else:
        source = pathlib.Path(path)
        display = str(source)
        if not source.is_file():
            raise ConfigError("missing-input", f"configuration file not found: {source}")
        try:
            raw = source.read_text(encoding="utf-8")
        except OSError as exc:
            raise ConfigError("read-failed", f"cannot read {source}: {exc}") from exc
    try:
        return json.loads(raw), display
    except json.JSONDecodeError as exc:
        raise ConfigError("invalid-json", f"invalid JSON in {display}: {exc}") from exc


def read_and_migrate(path: str) -> tuple[dict[str, Any], dict[str, Any], str]:
    raw, display = read_json(path)
    normalized, report = migrate(raw)
    errors = validate(normalized)
    if errors:
        raise ConfigError("invalid-config", "; ".join(errors))
    return normalized, report, display


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


def has_symlink_component(path: pathlib.Path) -> bool:
    """Return true when an existing component of an absolute path is a link."""

    if not path.is_absolute():
        return False
    cursor = pathlib.Path(path.anchor)
    for component in path.parts[1:]:
        cursor /= component
        if cursor.is_symlink():
            return True
    return False


def sibling_path(path: pathlib.Path, suffix: str) -> pathlib.Path:
    return path.with_name(path.name + suffix)


def atomic_write(path_text: str, content: str) -> None:
    path = pathlib.Path(path_text)
    if (path.exists() and path.is_symlink()) or has_symlink_component(path.parent):
        raise ConfigError("symlink-refused", f"refusing to replace symlink: {path}")
    temporary: pathlib.Path | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, prefix=".omanome-config-", delete=False) as handle:
            temporary = pathlib.Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except OSError as exc:
        try:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise ConfigError("write-failed", f"cannot atomically write {path}: {exc}") from exc


def backup(path_text: str) -> str | None:
    path = pathlib.Path(path_text)
    if not path.is_file():
        return None
    if path.is_symlink():
        raise ConfigError("symlink-refused", f"refusing to back up symlink: {path}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}")
    counter = 1
    while destination.exists() or destination.is_symlink():
        destination = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, destination)
    os.chmod(destination, 0o600)
    return str(destination)


def private_copy(source: pathlib.Path, destination: pathlib.Path) -> None:
    """Copy a damaged config without following or replacing a link."""

    if source.is_symlink() or destination.is_symlink() or has_symlink_component(destination.parent):
        raise ConfigError("symlink-refused", f"refusing to preserve config through symlink: {destination}")
    try:
        with source.open("rb") as source_handle, destination.open("xb") as destination_handle:
            shutil.copyfileobj(source_handle, destination_handle)
            destination_handle.flush()
            os.fsync(destination_handle.fileno())
        os.chmod(destination, 0o600)
    except FileExistsError:
        raise ConfigError("write-failed", f"refusing to overwrite preserved config: {destination}")
    except OSError as exc:
        try:
            destination.unlink(missing_ok=True)
        except OSError:
            pass
        raise ConfigError("write-failed", f"cannot preserve damaged config: {exc}") from exc


def lkg_path(path: pathlib.Path) -> pathlib.Path:
    return sibling_path(path, LKG_SUFFIX)


def preserve_corrupt(path: pathlib.Path) -> pathlib.Path | None:
    if not path.exists():
        return None
    if path.is_symlink() or not path.is_file():
        raise ConfigError("symlink-refused", f"refusing to preserve non-regular config: {path}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    destination = sibling_path(path, f"{CORRUPT_SUFFIX}.{stamp}")
    counter = 1
    while destination.exists() or destination.is_symlink():
        destination = sibling_path(path, f"{CORRUPT_SUFFIX}.{stamp}.{counter}")
        counter += 1
    private_copy(path, destination)
    return destination


def valid_candidate(path: pathlib.Path) -> tuple[dict[str, Any], dict[str, Any]] | None:
    if path.is_symlink() or not path.is_file():
        return None
    try:
        normalized, report, _ = read_and_migrate(str(path))
    except ConfigError as exc:
        # A future-schema LKG is not safe to overwrite with old defaults.
        if exc.reason == "future-schema":
            return None
        return None
    return normalized, report


def command_recover(args: argparse.Namespace) -> int:
    path = pathlib.Path(args.path)
    if path.is_symlink() or has_symlink_component(path.parent):
        raise ConfigError("symlink-refused", f"refusing to recover config through symlink: {path}")

    # A future-schema file is intentionally left byte-for-byte untouched. The
    # running older release must not destroy data it cannot understand.
    if path.is_file():
        try:
            normalized, report, display = read_and_migrate(str(path))
        except ConfigError as exc:
            if exc.reason == "future-schema":
                raise
        else:
            atomic_write(str(lkg_path(path)), json_text(normalized))
            output_result(
                {
                    "ok": True,
                    "path": display,
                    "recovered": False,
                    "source": "current",
                    "schemaVersion": normalized["schemaVersion"],
                    "migration": report,
                },
                args.json,
            )
            return 0

    preserved = preserve_corrupt(path)
    source = "defaults"
    normalized = load_defaults()
    report: dict[str, Any] = {
        "from": CURRENT_SCHEMA_VERSION,
        "to": CURRENT_SCHEMA_VERSION,
        "applied": [],
        "migrated": False,
    }
    candidates: list[pathlib.Path] = [lkg_path(path)]
    candidates.extend(sorted(path.parent.glob(f"{path.name}.bak.*"), reverse=True))
    for candidate in candidates:
        valid = valid_candidate(candidate)
        if valid is None:
            continue
        normalized, report = valid
        source = str(candidate)
        break

    atomic_write(str(path), json_text(normalized))
    atomic_write(str(lkg_path(path)), json_text(normalized))
    payload = {
        "ok": True,
        "path": str(path),
        "recovered": True,
        "source": source,
        "schemaVersion": normalized["schemaVersion"],
        "migration": report,
        "preservedCorrupt": str(preserved) if preserved else None,
    }
    output_result(payload, args.json)
    return 0


def output_result(payload: dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        if payload.get("ok") is True:
            print("ok")
            for key in ("path", "schemaVersion", "migration", "backup", "changed"):
                if key in payload:
                    print(f"{key}: {payload[key]}")
        else:
            print(f"error: {payload.get('reason', 'unknown')}: {payload.get('message', '')}", file=sys.stderr)


def command_validate(args: argparse.Namespace) -> int:
    normalized, report, display = read_and_migrate(args.path)
    payload = {"ok": True, "path": display, "schemaVersion": normalized["schemaVersion"], "migration": report, "errors": []}
    output_result(payload, args.json)
    return 0


def command_export(args: argparse.Namespace) -> int:
    if args.path:
        normalized, report, display = read_and_migrate(args.path)
    else:
        normalized, report, display = load_defaults(), {"from": CURRENT_SCHEMA_VERSION, "to": CURRENT_SCHEMA_VERSION, "applied": [], "migrated": False}, "defaults"
    if args.output:
        atomic_write(args.output, json_text(normalized))
        payload = {"ok": True, "path": args.output, "schemaVersion": normalized["schemaVersion"], "migration": report}
        output_result(payload, args.json)
    else:
        print(json_text(normalized), end="")
    return 0


def command_migrate(args: argparse.Namespace) -> int:
    normalized, report, display = read_and_migrate(args.path)
    atomic_write(args.output, json_text(normalized))
    output_result({"ok": True, "path": args.output, "schemaVersion": normalized["schemaVersion"], "migration": report}, args.json)
    return 0


def command_import(args: argparse.Namespace) -> int:
    normalized, report, display = read_and_migrate(args.source)
    previous = backup(args.target)
    atomic_write(args.target, json_text(normalized))
    atomic_write(str(lkg_path(pathlib.Path(args.target))), json_text(normalized))
    output_result({"ok": True, "path": args.target, "schemaVersion": normalized["schemaVersion"], "migration": report, "backup": previous}, args.json)
    return 0


def command_diff(args: argparse.Namespace) -> int:
    candidate, report, display = read_and_migrate(args.path)
    if args.against:
        baseline, _, baseline_display = read_and_migrate(args.against)
    else:
        baseline, baseline_display = load_defaults(), "defaults"
    before = json_text(baseline).splitlines(keepends=True)
    after = json_text(candidate).splitlines(keepends=True)
    diff = "".join(difflib.unified_diff(before, after, fromfile=baseline_display, tofile=display))
    if args.json:
        output_result({"ok": True, "changed": baseline != candidate, "from": baseline_display, "to": display, "diff": diff, "migration": report}, True)
    else:
        print(diff, end="")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("path")
    validate_parser.add_argument("--json", action="store_true")
    validate_parser.set_defaults(function=command_validate)
    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("path", nargs="?")
    export_parser.add_argument("--output")
    export_parser.add_argument("--json", action="store_true")
    export_parser.set_defaults(function=command_export)
    migrate_parser = subparsers.add_parser("migrate")
    migrate_parser.add_argument("path")
    migrate_parser.add_argument("--output", required=True)
    migrate_parser.add_argument("--json", action="store_true")
    migrate_parser.set_defaults(function=command_migrate)
    recover_parser = subparsers.add_parser("recover")
    recover_parser.add_argument("path")
    recover_parser.add_argument("--json", action="store_true")
    recover_parser.set_defaults(function=command_recover)
    import_parser = subparsers.add_parser("import")
    import_parser.add_argument("source")
    import_parser.add_argument("target")
    import_parser.add_argument("--json", action="store_true")
    import_parser.set_defaults(function=command_import)
    diff_parser = subparsers.add_parser("diff")
    diff_parser.add_argument("path")
    diff_parser.add_argument("--against")
    diff_parser.add_argument("--json", action="store_true")
    diff_parser.set_defaults(function=command_diff)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        args = parser.parse_args(arguments)
        return int(args.function(args))
    except ConfigError as exc:
        payload = {"ok": False, "reason": exc.reason, "message": str(exc)}
        if "--json" in arguments:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        else:
            print(f"omanome-config: {exc.reason}: {exc}", file=sys.stderr)
        return EX_NOINPUT if exc.reason == "missing-input" else EX_CONFIG
    except OSError as exc:
        print(f"omanome-config: {exc}", file=sys.stderr)
        return EX_CANTCREAT


if __name__ == "__main__":
    sys.exit(main())
