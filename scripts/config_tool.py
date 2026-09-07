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
    if isinstance(updates, dict) and updates.get("channel", "stable") not in {"stable", "beta", "nightly"}:
        errors.append("updates.channel must be stable, beta, or nightly")
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


def atomic_write(path_text: str, content: str) -> None:
    path = pathlib.Path(path_text)
    if path.exists() and path.is_symlink():
        raise ConfigError("symlink-refused", f"refusing to replace symlink: {path}")
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
            temporary.unlink(missing_ok=True)
        except (OSError, UnboundLocalError):
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
    while destination.exists():
        destination = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, destination)
    os.chmod(destination, 0o600)
    return str(destination)


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
    try:
        args = parser.parse_args(argv)
        return int(args.function(args))
    except ConfigError as exc:
        payload = {"ok": False, "reason": exc.reason, "message": str(exc)}
        if argv and "--json" in argv:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        else:
            print(f"omanome-config: {exc.reason}: {exc}", file=sys.stderr)
        return EX_NOINPUT if exc.reason == "missing-input" else EX_CONFIG
    except OSError as exc:
        print(f"omanome-config: {exc}", file=sys.stderr)
        return EX_CANTCREAT


if __name__ == "__main__":
    sys.exit(main())
