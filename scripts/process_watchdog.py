#!/usr/bin/env python3
"""Notify about sustained CPU or memory pressure in Omanome-owned helpers.

This is deliberately a diagnostic watchdog, not a process killer.  It reads
the owner-only process snapshot, waits for a sustained threshold, and emits a
component-specific warning.  Foreign processes are never inspected as
Omanome candidates and no signal is sent to any process.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
from typing import Any

from process_snapshot import OWNER, snapshot


SCHEMA_VERSION = 1
DEFAULT_CPU_THRESHOLD = 80.0
DEFAULT_DURATION_SECONDS = 10.0


def evaluate(
    report: dict[str, Any],
    state: dict[str, dict[str, float]],
    now: float,
    cpu_threshold: float = DEFAULT_CPU_THRESHOLD,
    duration_seconds: float = DEFAULT_DURATION_SECONDS,
    memory_limit_mb: float = 0.0,
) -> tuple[dict[str, dict[str, float]], dict[str, Any]]:
    """Evaluate one owner-only sample and return updated state plus a report."""

    next_state: dict[str, dict[str, float]] = {}
    observations: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []
    for item in report.get("processes", []):
        if not isinstance(item, dict):
            continue
        pid = int(item.get("pid", 0) or 0)
        component = str(item.get("component", "unknown"))
        key = f"{component}:{pid}"
        cpu = float(item.get("cpuPercent", 0.0) or 0.0)
        memory_mb = float(item.get("memoryBytes", 0) or 0) / (1024.0 * 1024.0)
        cpu_high = cpu >= cpu_threshold
        memory_high = memory_limit_mb > 0 and memory_mb >= memory_limit_mb
        previous = state.get(key, {})
        first_high_at = float(previous.get("firstHighAt", 0.0) or 0.0)
        if cpu_high or memory_high:
            if first_high_at <= 0:
                first_high_at = now
            next_state[key] = {"firstHighAt": first_high_at, "lastSeen": now}
        sustained_for = max(0.0, now - first_high_at) if first_high_at > 0 else 0.0
        sustained = (cpu_high or memory_high) and sustained_for >= duration_seconds
        observation = {
            "pid": pid,
            "component": component,
            "cpuPercent": round(cpu, 3),
            "memoryBytes": int(item.get("memoryBytes", 0) or 0),
            "cpuThresholdPercent": cpu_threshold,
            "memoryThresholdMb": memory_limit_mb,
            "sustainedForSeconds": round(sustained_for, 3),
            "sustained": sustained,
        }
        observations.append(observation)
        if sustained:
            warnings.append({
                **observation,
                "action": "notify-only",
                "automaticTermination": False,
                "message": "Sustained resource pressure in an Omanome-owned component",
            })
    return next_state, {
        "schemaVersion": SCHEMA_VERSION,
        "owner": OWNER,
        "policy": "notify-only",
        "automaticTermination": False,
        "sampledAt": report.get("measuredAt"),
        "systemCpuPercent": report.get("systemCpuPercent"),
        "ownerCpuPercent": report.get("ownerCpuPercent", report.get("totalCpuPercent", 0.0)),
        "processCount": report.get("processCount", 0),
        "observations": observations,
        "warnings": warnings,
        "foreignProcessesExcluded": True,
    }


def print_text(result: dict[str, Any]) -> None:
    warnings = result.get("warnings", [])
    if not warnings:
        print(
            "No sustained pressure detected in Omanome-owned processes "
            f"(owner CPU {float(result.get('ownerCpuPercent', 0.0) or 0.0):.3f}%)."
        )
        return
    for warning in warnings:
        print(
            f"WARNING {warning['component']} pid={warning['pid']}: "
            f"CPU {warning['cpuPercent']:.3f}%, RAM {warning['memoryBytes']} bytes, "
            f"sustained {warning['sustainedForSeconds']:.1f}s; notify-only, no process termination"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=pathlib.Path, default=None)
    parser.add_argument("--json", action="store_true", help="emit machine-readable samples")
    parser.add_argument("--watch", action="store_true", help="keep sampling until interrupted")
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--sample-ms", type=float, default=100.0)
    parser.add_argument("--cpu-threshold", type=float, default=DEFAULT_CPU_THRESHOLD)
    parser.add_argument("--duration", type=float, default=DEFAULT_DURATION_SECONDS)
    parser.add_argument("--memory-mb", type=float, default=0.0)
    args = parser.parse_args()
    if not 0 <= args.sample_ms <= 1000:
        parser.error("--sample-ms must be between 0 and 1000")
    if not 0.25 <= args.interval <= 60:
        parser.error("--interval must be between 0.25 and 60 seconds")
    if args.cpu_threshold <= 0:
        parser.error("--cpu-threshold must be positive")
    if args.duration < 0:
        parser.error("--duration must not be negative")
    if args.memory_mb < 0:
        parser.error("--memory-mb must not be negative")

    state: dict[str, dict[str, float]] = {}
    while True:
        report = snapshot(args.registry, args.sample_ms / 1000.0)
        state, result = evaluate(
            report,
            state,
            time.monotonic(),
            cpu_threshold=args.cpu_threshold,
            duration_seconds=args.duration,
            memory_limit_mb=args.memory_mb,
        )
        if args.json:
            print(json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
        else:
            print_text(result)
        if not args.watch:
            break
        try:
            time.sleep(args.interval)
        except KeyboardInterrupt:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
