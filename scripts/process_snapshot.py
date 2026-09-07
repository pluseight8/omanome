#!/usr/bin/env python3
"""Inspect only processes that carry Omanome's explicit ownership marker.

Process names are intentionally not used as an ownership signal.  A process
is included only when its environment contains ``OMANOME_OWNER`` with the
exact plugin owner value, or when a live PID is present in the registry and
still matches the recorded process identity.  This prevents unrelated
processes such as Omarchy's Lua helpers from being attributed to Omanome.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
from typing import Any, Iterable


OWNER = "io.omanome.shell"
REGISTRY_SCHEMA = 1
PROC_ENV_OWNER = "OMANOME_OWNER"
PROC_ENV_COMPONENT = "OMANOME_COMPONENT"
PROC_ENV_SHELL_PID = "OMANOME_SHELL_PID"
HZ = int(os.sysconf("SC_CLK_TCK"))
PAGE_SIZE = int(os.sysconf("SC_PAGE_SIZE"))


def default_registry_path() -> pathlib.Path:
    state_home = pathlib.Path(os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state"))
    return state_home / "omanome" / "processes.json"


def _read_text(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except (FileNotFoundError, PermissionError, OSError):
        return ""


def _read_bytes(path: pathlib.Path) -> bytes:
    try:
        return path.read_bytes()
    except (FileNotFoundError, PermissionError, OSError):
        return b""


def _proc_stat(pid: int) -> dict[str, Any] | None:
    raw = _read_text(pathlib.Path("/proc") / str(pid) / "stat")
    if not raw:
        return None
    closing = raw.rfind(")")
    if closing < 0:
        return None
    fields = raw[closing + 2 :].split()
    if len(fields) < 20:
        return None
    try:
        return {
            "state": fields[0],
            "ppid": int(fields[1]),
            "utimeTicks": int(fields[11]),
            "stimeTicks": int(fields[12]),
            "threads": int(fields[17]),
            "startTicks": int(fields[19]),
        }
    except ValueError:
        return None


def _system_ticks() -> int:
    line = _read_text(pathlib.Path("/proc/stat")).splitlines()
    if not line:
        return 0
    fields = line[0].split()
    try:
        return sum(int(value) for value in fields[1:])
    except (IndexError, ValueError):
        return 0


def _environment(pid: int) -> dict[str, str]:
    raw = _read_bytes(pathlib.Path("/proc") / str(pid) / "environ")
    result: dict[str, str] = {}
    for item in raw.split(b"\0"):
        if b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        try:
            key_text = key.decode("utf-8", "replace")
            if key_text in {PROC_ENV_OWNER, PROC_ENV_COMPONENT, PROC_ENV_SHELL_PID}:
                result[key_text] = value.decode("utf-8", "replace")
        except UnicodeDecodeError:
            continue
    return result


def _command(pid: int) -> list[str]:
    raw = _read_bytes(pathlib.Path("/proc") / str(pid) / "cmdline")
    return [part.decode("utf-8", "replace") for part in raw.split(b"\0") if part]


def _redact_command(command: Iterable[str]) -> list[str]:
    values = list(command)
    result: list[str] = []
    redact_next = False
    executable = pathlib.Path(values[0]).name if values else ""
    for value in values:
        if redact_next:
            result.append("<redacted>")
            redact_next = False
            continue
        if value in {"password", "--password", "secret", "--secret", "token", "--token"}:
            result.append(value)
            redact_next = True
            continue
        if executable in {"wtype", "omanome-input"} and value not in {values[0], "-k", "-M", "-m", "--"}:
            result.append("<input>")
            continue
        result.append(value)
    if redact_next:
        result.append("<redacted>")
    return result


def _memory_bytes(pid: int) -> int:
    for line in _read_text(pathlib.Path("/proc") / str(pid) / "status").splitlines():
        if line.startswith("VmRSS:"):
            match = re.search(r"(\d+)", line)
            if match:
                return int(match.group(1)) * 1024
    return 0


def _uptime_seconds(start_ticks: int, now: float | None = None) -> float:
    uptime_text = _read_text(pathlib.Path("/proc/uptime")).split()
    try:
        uptime = float(uptime_text[0])
    except (IndexError, ValueError):
        return 0.0
    boot_start = time.time() - uptime
    started = boot_start + (start_ticks / HZ)
    return max(0.0, (now if now is not None else time.time()) - started)


def _load_registry(path: pathlib.Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, PermissionError, OSError, json.JSONDecodeError):
        return {"schemaVersion": REGISTRY_SCHEMA, "owner": OWNER, "processes": [], "counters": {}}
    if not isinstance(payload, dict) or payload.get("owner") not in {None, OWNER}:
        return {"schemaVersion": REGISTRY_SCHEMA, "owner": OWNER, "processes": [], "counters": {}}
    processes = payload.get("processes")
    payload["processes"] = processes if isinstance(processes, list) else []
    payload["owner"] = OWNER
    return payload


def _registry_by_pid(registry: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for item in registry.get("processes", []):
        if not isinstance(item, dict):
            continue
        try:
            pid = int(item.get("pid", 0))
        except (TypeError, ValueError):
            continue
        if pid > 0:
            result[pid] = item
    return result


def _process_record(pid: int, registry_item: dict[str, Any] | None, cpu_percent: float) -> dict[str, Any] | None:
    stat = _proc_stat(pid)
    if stat is None:
        return None
    env = _environment(pid)
    command = _command(pid)
    marker = env.get(PROC_ENV_OWNER) == OWNER
    registry_match = isinstance(registry_item, dict) and int(registry_item.get("pid", 0) or 0) == pid
    if not marker and not registry_match:
        return None
    evidence = []
    if marker:
        evidence.append("environment-marker")
    if registry_match:
        evidence.append("runtime-registry")
    executable = ""
    try:
        executable = os.readlink(f"/proc/{pid}/exe")
    except (FileNotFoundError, PermissionError, OSError):
        pass
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except (FileNotFoundError, PermissionError, OSError):
        cwd = ""
    record = {
        "pid": pid,
        "ppid": stat["ppid"],
        "component": env.get(PROC_ENV_COMPONENT) or str((registry_item or {}).get("component", "unknown")),
        "purpose": str((registry_item or {}).get("purpose", "")),
        "command": _redact_command(command),
        "executable": executable,
        "workingDirectory": cwd,
        "state": stat["state"],
        "threads": stat["threads"],
        "memoryBytes": _memory_bytes(pid),
        "cpuPercent": round(max(0.0, cpu_percent), 3),
        "uptimeSeconds": round(_uptime_seconds(stat["startTicks"]), 3),
        "startTicks": stat["startTicks"],
        "restartCount": int((registry_item or {}).get("restartCount", 0) or 0),
        "restartPolicy": str((registry_item or {}).get("restartPolicy", "none")),
        "ownershipEvidence": evidence,
        "owner": OWNER,
    }
    shell_pid = env.get(PROC_ENV_SHELL_PID) or (registry_item or {}).get("shellPid")
    if shell_pid:
        record["shellPid"] = str(shell_pid)
    return record


def _cpu_samples(pids: list[int], sample_seconds: float) -> dict[int, float]:
    before_total = _system_ticks()
    before: dict[int, int] = {}
    for pid in pids:
        stat = _proc_stat(pid)
        if stat:
            before[pid] = stat["utimeTicks"] + stat["stimeTicks"]
    if sample_seconds > 0:
        time.sleep(sample_seconds)
    after_total = _system_ticks()
    total_delta = max(1, after_total - before_total)
    result: dict[int, float] = {}
    for pid, value in before.items():
        stat = _proc_stat(pid)
        if not stat:
            continue
        process_delta = max(0, stat["utimeTicks"] + stat["stimeTicks"] - value)
        result[pid] = process_delta / total_delta * (os.cpu_count() or 1) * 100.0
    return result


def snapshot(registry_path: pathlib.Path | None = None, sample_seconds: float = 0.1) -> dict[str, Any]:
    registry_path = registry_path or default_registry_path()
    registry = _load_registry(registry_path)
    registry_by_pid = _registry_by_pid(registry)
    candidates: set[int] = set(registry_by_pid)
    proc_root = pathlib.Path("/proc")
    for entry in proc_root.iterdir():
        if entry.name.isdigit():
            pid = int(entry.name)
            if _environment(pid).get(PROC_ENV_OWNER) == OWNER:
                candidates.add(pid)
    cpu = _cpu_samples(sorted(candidates), max(0.0, min(sample_seconds, 1.0)))
    processes = []
    for pid in sorted(candidates):
        record = _process_record(pid, registry_by_pid.get(pid), cpu.get(pid, 0.0))
        if record is not None:
            processes.append(record)
    total_cpu = sum(float(item["cpuPercent"]) for item in processes)
    total_memory = sum(int(item["memoryBytes"]) for item in processes)
    helpers = [item for item in processes if item.get("component") not in {"shell", "service"}]
    counters = registry.get("counters") if isinstance(registry.get("counters"), dict) else {}
    return {
        "schemaVersion": REGISTRY_SCHEMA,
        "owner": OWNER,
        "measuredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sampleSeconds": round(max(0.0, min(sample_seconds, 1.0)), 3),
        "processCount": len(processes),
        "helperProcessCount": len(helpers),
        "totalCpuPercent": round(total_cpu, 3),
        "totalMemoryBytes": total_memory,
        "spawnedTotal": int(counters.get("spawnedTotal", 0) or 0),
        "activeSubprocesses": len(processes),
        "eventsReceived": int(counters.get("eventsReceived", 0) or 0),
        "configWrites": int(counters.get("configWrites", 0) or 0),
        "previewStreams": int(counters.get("previewStreams", 0) or 0),
        "helperRestarts": int(counters.get("helperRestarts", 0) or 0),
        "processes": processes,
        "ownership": {
            "method": "explicit environment marker or matching runtime registry",
            "foreignProcessesExcluded": True,
            "registry": str(registry_path),
        },
    }


def _format_bytes(value: int) -> str:
    if value < 1024 * 1024:
        return f"{value / 1024:.1f} KiB"
    return f"{value / (1024 * 1024):.1f} MiB"


def print_text(report: dict[str, Any]) -> None:
    print(f"Omanome-owned processes: {report['processCount']}")
    print(f"Total CPU: {report['totalCpuPercent']:.3f}%")
    print(f"Total RAM: {_format_bytes(int(report['totalMemoryBytes']))}")
    if not report["processes"]:
        print("No Omanome-owned helper is currently registered.")
        return
    print("PID     Component                 CPU       RAM       State  Purpose")
    for item in report["processes"]:
        print(
            f"{item['pid']:<7} {str(item['component'])[:24]:<24} "
            f"{item['cpuPercent']:>7.3f}% {_format_bytes(int(item['memoryBytes'])):>9} "
            f"{item['state']:<6} {item['purpose']}"
        )


def reset_counters(registry_path: pathlib.Path | None = None) -> dict[str, Any]:
    registry_path = registry_path or default_registry_path()
    registry = _load_registry(registry_path)
    registry["counters"] = {
        "spawnedTotal": 0,
        "eventsReceived": 0,
        "configWrites": 0,
        "previewStreams": 0,
        "helperRestarts": 0,
    }
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = registry_path.with_name(registry_path.name + f".tmp.{os.getpid()}")
    temporary.write_text(json.dumps(registry, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, registry_path)
    return registry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit a machine-readable report")
    parser.add_argument("--registry", type=pathlib.Path, default=None)
    parser.add_argument("--sample-ms", type=float, default=100.0)
    parser.add_argument("--watch", action="store_true", help="keep sampling until interrupted")
    parser.add_argument("--interval", type=float, default=1.0, help="watch interval in seconds")
    parser.add_argument("--reset", action="store_true", help="reset local counters without touching live processes")
    args = parser.parse_args()
    if args.sample_ms < 0 or args.sample_ms > 1000:
        parser.error("--sample-ms must be between 0 and 1000")
    if args.interval < 0.25 or args.interval > 60:
        parser.error("--interval must be between 0.25 and 60 seconds")
    if args.reset:
        reset_counters(args.registry)
        report = snapshot(args.registry, 0)
        if args.json:
            print(json.dumps({"reset": True, "report": report}, ensure_ascii=False, sort_keys=True))
        else:
            print("Omanome performance counters reset; live process registry was preserved.")
        return 0
    while True:
        report = snapshot(args.registry, args.sample_ms / 1000.0)
        if args.json:
            print(json.dumps(report, ensure_ascii=False, sort_keys=True), flush=True)
        else:
            print_text(report)
        if not args.watch:
            break
        try:
            time.sleep(args.interval)
        except KeyboardInterrupt:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
