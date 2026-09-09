#!/usr/bin/env python3
"""Run the portable Omanome 1.3 device-topology safety gate.

This gate exercises the pure device graph, mapping, calibration, and topology
models with an explicit fixture.  It intentionally reports fixture evidence
as ``Untested``: a portable CI runner cannot certify a physical touchscreen,
stylus, dock, or monitor.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE = ROOT / "tests" / "fixtures" / "hardware-device-graph.json"
RESULTS = ("Pass", "Fail", "Unavailable", "Untested")
SAFE_ID = "device:touchscreen:0123456789abcdef"
SAFE_OUTPUT = "display:fedcba9876543210"


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def check(name: str, passed: bool, details: str) -> dict[str, str]:
    return {"name": name, "result": "Pass" if passed else "Fail", "details": details}


def source_checks() -> list[dict[str, str]]:
    graph = read(ROOT / "shell/models/DeviceGraph.js")
    topology = read(ROOT / "shell/models/DeviceTopology.js")
    calibration = read(ROOT / "shell/models/Calibration.js")
    wizard = read(ROOT / "shell/models/CalibrationWizard.js")
    service = read(ROOT / "shell/Service.qml")
    policies = read(ROOT / "shell/models/HardwarePolicies.js")
    docking = read(ROOT / "shell/models/DockingContinuity.js")
    cli = read(ROOT / "cli/omanome")
    manifest = json.loads(read(ROOT / "manifest.json"))

    checks: list[dict[str, str]] = []
    checks.append(check(
        "graph-contract",
        all(marker in graph for marker in (
            "function stableId", "function fromSnapshot", "function applyEvent",
            "function publicSnapshot", "function publicId", "sourceList",
            '"display"', '"touchscreen"', '"stylus"', '"tablet-pad"',
            '"keyboard"', '"dock"', '"battery"', '"audio"',
        )),
        "Device Graph owns generic categories, opaque identity, snapshots, and runtime events",
    ))
    public_start = graph.find("function publicSnapshot")
    public_surface = graph[public_start:] if public_start >= 0 else ""
    checks.append(check(
        "public-privacy-boundary",
        all(secret not in public_surface for secret in ("serial", "address", "physicalPath", "devicePath", "/dev/", "event")),
        "public graph projection contains only opaque IDs and whitelisted fields",
    ))
    checks.append(check(
        "relationship-confidence",
        all(marker in graph for marker in ("explicitRelations", "relationConfidence", "sourceList", '"confirmed"', '"probable"', '"unknown"')),
        "relations keep explicit source and Confirmed/Probable/Unknown confidence",
    ))
    checks.append(check(
        "calibration-safety",
        all(marker in calibration for marker in (
            "MAX_TOUCH_SAMPLES", "MAX_STYLUS_SAMPLES", "realSamplesOnly",
            "wrong-monitor-mapping", "prepareTransaction", "rollbackTransaction",
            "disconnectTransaction", "confirmation-timeout",
        )),
        "calibration samples are bounded, real-only, mapping-aware, and reversible",
    ))
    checks.append(check(
        "mapping-wizard",
        all(marker in wizard for marker in (
            "beginMapping", "selectInput", "selectOutput", "identifyOutput",
            "selectOutputByName", "identical-display-names", "function confirm", "function cancel",
        )),
        "mapping requires explicit user selection and handles ambiguity/cancel",
    ))
    checks.append(check(
        "topology-coalescing",
        all(marker in topology for marker in (
            "MAX_SOURCE_ROWS", "MAX_CAPABILITY_CHANGES", "pendingRefresh",
            "coalescedEvents", "function noteEvent", "function reconcile",
        )),
        "hotplug events are bounded and coalesced before one graph reconciliation",
    ))
    checks.append(check(
        "service-single-source",
        all(marker in service for marker in (
            "DeviceGraphModel.fromSnapshot", "DeviceGraphModel.applyEvent",
            "DeviceTopologyModel.noteEvent", "DeviceTopologyModel.reconcile",
            "deviceRefreshDebounce.restart()", "CalibrationWizardModel.beginMapping",
        )),
        "Service routes graph, topology, and mapping through the shared models",
    ))
    checks.append(check(
        "setup-and-docking-policy",
        all(marker in policies for marker in ("resolveSetup", "resolveOskTarget", "powerDecision", "displayRows"))
        and all(marker in docking for marker in ("observe", "acknowledgeRestore", "docked-output-disconnected")),
        "display roles, OSK target, power decision, and docking recovery remain policy-only",
    ))
    checks.append(check(
        "bar-invariant",
        "bar" not in manifest.get("kinds", [])
        and "bar-widget" in manifest.get("kinds", [])
        and manifest.get("entryPoints", {}).get("barWidget") is not None,
        "standard Omarchy bar remains intact and Omanome uses the widget entry point",
    ))

    scoped_sources = {
        "graph": graph,
        "topology": topology,
        "calibration": calibration,
        "wizard": wizard,
        "service": service,
        "policies": policies,
        "docking": docking,
        "cli": cli,
    }
    forbidden = ("xinput", "xdot" + "ool", "lsusb")
    forbidden_hits = [f"{name}:{word}" for name, text in scoped_sources.items() for word in forbidden if word in text.lower()]
    checks.append(check(
        "legacy-probe-boundary",
        not forbidden_hits,
        "no legacy input probe in the device graph path" if not forbidden_hits else ", ".join(forbidden_hits),
    ))
    return checks


def run_models(fixture: dict[str, Any]) -> tuple[dict[str, Any] | None, str]:
    node = shutil.which("node")
    if not node:
        return None, "node is unavailable"
    fixture_literal = json.dumps(fixture, ensure_ascii=True, separators=(",", ":"))
    expression = f"""
const G=require('./shell/models/DeviceGraph.js');
const T=require('./shell/models/DeviceTopology.js');
const C=require('./shell/models/Calibration.js');
const W=require('./shell/models/CalibrationWizard.js');
const fixture={fixture_literal};
const graph=G.fromSnapshot(fixture);
const publicGraph=G.publicSnapshot(graph);
const publicText=JSON.stringify(publicGraph);
const relationConfidence=[...new Set(graph.relationships.map(row=>row.confidence))].sort();
let topology=T.emptyState();
for(let i=0;i<1000;i++) topology=T.noteEvent(topology,{{type:'device.event',source:'udev',action:'change',category:'keyboard',device:{{type:'keyboard',capabilities:{{keyboard:true}}}}}},1000+i,{{debounceMs:240}});
const reconciled=T.reconcile(topology,graph,graph,5000,'burst-reconciled');
let touch=C.beginTouch('{SAFE_ID}','{SAFE_OUTPUT}',{{touchscreen:true,absolute:true}});
for(const target of C.TOUCH_TARGETS()) touch=C.recordTouchSample(touch,{{targetId:target.id,x:target.x,y:target.y,outputId:'{SAFE_OUTPUT}',real:true,source:'native'}}).state;
let transaction=C.prepareTransaction('touchscreen','{SAFE_ID}',null,{{outputId:'{SAFE_OUTPUT}',offset:{{x:0.01,y:-0.01}},scale:{{x:1,y:1}},rotation:0}},1000,{{countdownMs:2000}});
transaction=C.applyTransaction(transaction,true,1100);
const timeout=C.tickTransaction(transaction,4000);
const disconnect=C.disconnectTransaction(transaction);
let stylus=C.beginStylus('device:stylus:1111111111111111',{{stylus:true,pressure:true,tiltX:true,tiltY:true}});
let lastSample={{}};
for(let i=0;i<257;i++) lastSample=C.recordStylusSample(stylus,{{x:i/256,y:i/256,pressure:0.5,tiltX:0,tiltY:0,real:true,source:'native'}}),stylus=lastSample.state;
const wizard=W.beginMapping(publicGraph);
const input=publicGraph.nodes.find(row=>row.category==='touchscreen');
const output=publicGraph.outputs[0];
const mapped=W.confirm(W.identifyOutput(W.selectOutput(W.selectInput(wizard,input.id),output.id),output.id,'number'));
const duplicate=W.selectOutputByName(W.beginMapping({{nodes:[],outputs:[{{id:'display:1111111111111111',name:'Same',connected:true}},{{id:'display:2222222222222222',name:'Same',connected:true}}]}}),'Same');
console.log(JSON.stringify({{
  categories:[...new Set(graph.nodes.map(row=>row.category))].sort(),
  graphAvailable:graph.health.available===true,
  relationConfidence,
  publicClean:!/(SERIAL-DEVICE-CHECK|aa:bb:cc:dd:ee:ff|\\/sys\\/devices|event42)/.test(publicText),
  touchReady:touch.phase==='analyzed' && touch.result && touch.result.safe===true,
  transactionTimeout:timeout.phase==='rolled-back' && timeout.error==='confirmation-timeout',
  transactionDisconnect:disconnect.phase==='rolled-back' && disconnect.error==='device-disconnected',
  stylusBounded:stylus.samples.length===256 && lastSample.accepted===false && lastSample.reason==='sample-limit',
  topology:{{eventCount:topology.eventCount,coalescedEvents:topology.coalescedEvents,reconciledPending:reconciled.pendingRefresh,reconciledNodes:reconciled.current.nodeCount}},
  mappingComplete:mapped.phase==='complete',
  ambiguous:duplicate.phase==='ambiguous' && duplicate.error==='identical-display-names'
}}));
"""
    result = subprocess.run([node, "-e", expression], cwd=ROOT, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return None, result.stderr.strip() or "node model check failed"
    try:
        return json.loads(result.stdout), ""
    except json.JSONDecodeError:
        return None, "node model check returned non-JSON output"


def runtime_checks(fixture: dict[str, Any]) -> tuple[list[dict[str, str]], dict[str, Any]]:
    payload, reason = run_models(fixture)
    if payload is None:
        return [check("runtime-models", False, reason)], {"available": False, "reason": reason}
    checks = [
        check("runtime-models", True, "Node executed the graph, topology, mapping, and calibration models"),
        check("fixture-graph", payload.get("graphAvailable") is True and {"display", "touchscreen", "stylus", "dock", "keyboard"}.issubset(set(payload.get("categories", []))), "fixture graph has UX-relevant connected categories"),
        check("relation-confidence-runtime", set(payload.get("relationConfidence", [])) >= {"confirmed", "probable", "unknown"}, "runtime relations preserve all three evidence levels"),
        check("mapping-privacy", payload.get("publicClean") is True, "public graph contains no fixture serial, address, syspath, or event node"),
        check("touch-calibration", payload.get("touchReady") is True, "five real touch targets produce a safe candidate"),
        check("calibration-timeout-rollback", payload.get("transactionTimeout") is True, "unconfirmed applied mapping rolls back at deadline"),
        check("calibration-disconnect-rollback", payload.get("transactionDisconnect") is True, "device disconnect rolls back an active calibration transaction"),
        check("stylus-sample-bound", payload.get("stylusBounded") is True, "stylus samples stop at the bounded limit"),
        check("event-burst-coalescing", payload.get("topology", {}).get("eventCount") == 1000 and payload.get("topology", {}).get("coalescedEvents", 0) >= 999 and payload.get("topology", {}).get("reconciledPending") is False and payload.get("topology", {}).get("reconciledNodes", 0) > 0, "1000 events coalesce and reconcile into one settled graph"),
        check("mapping-wizard-safety", payload.get("mappingComplete") is True and payload.get("ambiguous") is True, "mapping completes only after identification and rejects identical-name ambiguity"),
    ]
    return checks, payload


def fixture_scenarios(fixture: dict[str, Any]) -> dict[str, dict[str, str]]:
    names = ("graph", "mapping", "calibrationRollback", "eventCoalescing", "privacy", "stylus", "multiMonitor", "rotation")
    declarations = fixture.get("scenarios", {}) if isinstance(fixture.get("scenarios"), dict) else {}
    result: dict[str, dict[str, str]] = {}
    for name in names:
        declared = declarations.get(name) is not None
        result[name] = {
            "result": "Untested" if declared else "Unavailable",
            "source": "fixture",
            "reason": "fixture declares coverage; physical hardware execution was not performed" if declared else "fixture does not declare this scenario",
        }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=pathlib.Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    try:
        fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        payload = {"schemaVersion": 1, "mode": "portable", "ok": False, "error": str(exc)}
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True) if args.json else f"device-check: {exc}")
        return 1
    if not isinstance(fixture, dict):
        payload = {"schemaVersion": 1, "mode": "portable", "ok": False, "error": "fixture must be an object"}
        print(json.dumps(payload, sort_keys=True) if args.json else "device-check: fixture must be an object")
        return 1

    checks = source_checks()
    runtime, evidence = runtime_checks(fixture)
    checks.extend(runtime)
    ok = all(item["result"] == "Pass" for item in checks)
    payload = {
        "schemaVersion": 1,
        "mode": "portable",
        "ok": ok,
        "checks": checks,
        "hardware": {
            "evidence": "fixture",
            "realHardwareValidated": False,
            "scenarios": fixture_scenarios(fixture),
            "note": "Portable device contracts passed; fixture evidence is not physical hardware certification.",
        },
        "evidence": evidence,
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        print("Device topology safety: " + ("Pass" if ok else "Fail"))
        for item in checks:
            print(f"{item['result']}: {item['name']} — {item['details']}")
        print("Hardware evidence: fixture / Untested")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
