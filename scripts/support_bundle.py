#!/usr/bin/env python3
"""Create a redacted, reproducible Omanome support bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
EX_CONFIG = 78
PRIVATE_KEYS = {
    "address", "bluetoothaddress", "clipboard", "devpath", "deviceid", "devicepath", "idpath",
    "idserialshort", "mac", "name", "path", "phys", "serial", "serialnumber", "text", "title",
    "typedtext", "uniqueid", "uniq",
}
MAC_PATTERN = re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b")


def private_key(key: Any) -> str:
    return str(key).replace("-", "").replace("_", "").lower()


def redact(value: Any, home: str, private: bool = False) -> Any:
    if isinstance(value, str):
        result = value.replace(home, "<home>") if home else value
        return MAC_PATTERN.sub("<redacted-mac>", result) if private else result
    if isinstance(value, list):
        return [redact(item, home, private) for item in value]
    if isinstance(value, dict):
        return {
            key: "<redacted>" if private and private_key(key) in PRIVATE_KEYS else redact(item, home, private)
            for key, item in value.items()
        }
    return value


def run_json(command: list[str], env: dict[str, str]) -> Any:
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=8, check=False)
        return json.loads(result.stdout) if result.stdout.strip() else {"ok": False, "exitCode": result.returncode}
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        return {"ok": False, "error": str(exc)}


def config_metadata(config_path: pathlib.Path, env: dict[str, str]) -> dict[str, Any]:
    result: dict[str, Any] = {"exists": config_path.is_file(), "path": "<config>/config.json"}
    if not config_path.is_file():
        return result
    try:
        raw = config_path.read_bytes()
        result["bytes"] = len(raw)
        result["sha256"] = hashlib.sha256(raw).hexdigest()
        parsed = json.loads(raw.decode("utf-8"))
        result["schemaVersion"] = parsed.get("schemaVersion") if isinstance(parsed, dict) else None
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        result["parseError"] = str(exc)
    result["validation"] = run_json(["python3", str(ROOT / "scripts" / "config_tool.py"), "validate", str(config_path), "--json"], env)
    return result


def build_payload(config_path: pathlib.Path, state_dir: pathlib.Path, env: dict[str, str]) -> dict[str, Any]:
    manifest: Any
    try:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        manifest = {"error": str(exc)}
    commands = ["omarchy", "omarchy-shell", "quickshell", "hyprctl", "wl-copy", "wl-paste", "wtype", "jq", "curl", "git"]
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "manifest": {key: manifest.get(key) for key in ("id", "version", "kinds", "entryPoints")} if isinstance(manifest, dict) else manifest,
        "config": config_metadata(config_path, env),
        "capabilities": run_json(["python3", str(ROOT / "scripts" / "hardware_test.py"), "--json"], env),
        "performance": run_json(["python3", str(ROOT / "scripts" / "process_snapshot.py"), "--json", "--sample-ms", "0"], env),
        "effects": run_json([str(ROOT / "input" / "effects-info.sh")], env),
        "sensors": run_json([str(ROOT / "input" / "sensor-info.sh")], env),
        "companion": run_json([str(ROOT / "input" / "companion-info.sh")], env),
        "environment": {
            "wayland": bool(env.get("WAYLAND_DISPLAY")),
            "omarchyPathSet": bool(env.get("OMARCHY_PATH")),
            "commands": {command: bool(shutil.which(command, path=env.get("PATH"))) for command in commands},
            "personalContent": "excluded",
        },
        "state": {"path": "<state>/omanome", "exists": state_dir.is_dir()},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--config", required=True, type=pathlib.Path)
    parser.add_argument("--state", required=True, type=pathlib.Path)
    parser.add_argument("--private", action="store_true", help="apply aggressive identifier/content redaction")
    args = parser.parse_args(argv)
    output = args.output.expanduser()
    if output.exists() and output.is_symlink():
        print(json.dumps({"ok": False, "reason": "symlink-refused", "path": str(output)}))
        return EX_CONFIG
    output.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    payload = redact(build_payload(args.config, args.state, env), env.get("HOME", ""), args.private)
    payload["privacy"] = {
        "mode": "private" if args.private else "default-redacted",
        "bluetoothMacEmitted": False,
        "serialsEmitted": False,
        "typedTextLogged": False,
        "personalContent": "excluded",
    }
    try:
        with tempfile.TemporaryDirectory(prefix="omanome-bundle-", dir=output.parent) as temporary:
            temporary_path = pathlib.Path(temporary)
            (temporary_path / "report.json").write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
            (temporary_path / "README.txt").write_text(
                "Omanome support bundle\nPersonal clipboard, window titles, typed text, and config values are excluded.\n",
                encoding="utf-8",
            )
            archive = temporary_path / "bundle.tar.gz"
            with tarfile.open(archive, "w:gz") as handle:
                handle.add(temporary_path / "report.json", arcname="report.json")
                handle.add(temporary_path / "README.txt", arcname="README.txt")
            os.replace(archive, output)
    except OSError as exc:
        print(json.dumps({"ok": False, "reason": "write-failed", "message": str(exc)}))
        return EX_CONFIG
    print(json.dumps({"ok": True, "path": str(output), "schemaVersion": 1, "redacted": True, "private": args.private}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
