#!/usr/bin/env python3
"""Run a deterministic, hardware-independent config projection benchmark."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]


def project(config: dict) -> dict:
    return {
        "mode": config.get("general", {}).get("mode"),
        "profile": config.get("general", {}).get("profile"),
        "touchTarget": config.get("tabletMode", {}).get("touchTarget"),
        "dock": config.get("dock", {}).get("position"),
        "previewStreams": config.get("altTab", {}).get("previewStreams"),
        "reducedMotion": config.get("accessibility", {}).get("reducedMotion"),
        "effects": config.get("effects", {}).get("enabled"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=5000)
    parser.add_argument("--budget-ms", type=float, default=2500.0)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("--iterations must be positive")
    config = json.loads((ROOT / "config/defaults.json").read_text(encoding="utf-8"))
    started = time.perf_counter()
    result = {}
    for _ in range(args.iterations):
        result = project(config)
        result = json.loads(json.dumps(result, separators=(",", ":")))
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    report = {
        "schemaVersion": 1,
        "iterations": args.iterations,
        "elapsedMs": round(elapsed_ms, 3),
        "budgetMs": args.budget_ms,
        "passed": elapsed_ms <= args.budget_ms,
        "method": "deterministic config projection and JSON round-trip",
        "hardwareValidated": False,
        "sample": result,
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print(f"performance: {report['elapsedMs']:.3f} ms / {args.iterations} iterations")
        print("performance: pass" if report["passed"] else "performance: FAIL")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
