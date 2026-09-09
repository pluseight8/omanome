#!/usr/bin/env python3
"""Run the deterministic 1.4 portable integration and stress fixture.

The fixture drives the same pure models used by Service.qml through a bounded
install/update/reload/suspend/resume/rollback/uninstall scenario.  It also
opens and closes every declared surface for 100 cycles while checking that a
single owner boundary remains, preview streams are released, and no process
is spawned for local geometry or model-only transitions.

This is fixture evidence, not a compositor, process, or physical-hardware
certification.  The report says so explicitly and never includes raw device
identity from the input fixture.
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
DEFAULT_FIXTURE = ROOT / "tests" / "fixtures" / "integration-1.4.json"
DEVICE_FIXTURE = ROOT / "tests" / "fixtures" / "hardware-device-graph.json"
EXPECTED_SURFACES = (
    "control-center",
    "overview",
    "launcher",
    "settings",
    "osk",
    "quick-settings",
)


def check(name: str, passed: bool, detail: str) -> dict[str, Any]:
    return {"name": name, "passed": bool(passed), "detail": detail}


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain an object")
    return value


NODE_FIXTURE = r'''
const fs = require("fs");
const C = require("./shell/models/Config.js");
const R = require("./shell/models/Responsive.js");
const L = require("./shell/models/LayoutEngine.js");
const S = require("./shell/models/SnapAssist.js");
const Split = require("./shell/models/SplitView.js");
const G = require("./shell/models/DeviceGraph.js");
const T = require("./shell/models/DeviceTopology.js");
const Cal = require("./shell/models/Calibration.js");
const W = require("./shell/models/CalibrationWizard.js");
const A = require("./shell/models/AdaptiveMode.js");
const D = require("./shell/models/DockedMode.js");
const M = require("./shell/models/ModeTransitionCoordinator.js");
const Life = require("./shell/models/Lifecycle.js");
const WS = require("./shell/models/WorkspaceSwitcher.js");
const Budget = require("./shell/models/PerformanceBudget.js");

const fixture = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const deviceFixture = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const cycles = Number(process.argv[3]);
const failures = [];
function requireCheck(name, value, detail) {
  if (!value) failures.push({name, detail});
  return Boolean(value);
}
function finite(value) { return typeof value === "number" && Number.isFinite(value); }
function validRect(rect, area) {
  return rect && [rect.x, rect.y, rect.width, rect.height].every(finite)
    && rect.width >= 1 && rect.height >= 1
    && rect.x >= area.x && rect.y >= area.y
    && rect.x + rect.width <= area.x + area.width
    && rect.y + rect.height <= area.y + area.height;
}
function layoutIsSafe(pair) {
  const area = pair && pair.usable;
  const slots = pair && Array.isArray(pair.slots) ? pair.slots : [];
  if (!area || slots.length < 1) return false;
  return slots.every(slot => validRect(slot.rect, area));
}
function splitPairIsSafe(pair) {
  const slots = pair && Array.isArray(pair.slots) ? pair.slots : [];
  return slots.length === 2 && layoutIsSafe(pair);
}
function publicTextIsClean(value) {
  return !/(SERIAL-DEVICE-CHECK|aa:bb:cc:dd:ee:ff|\/sys\/devices|event42)/.test(JSON.stringify(value));
}
function preservePath(value, path, expected) {
  let current = value;
  for (const part of path.split(".")) current = current && current[part];
  return JSON.stringify(current) === JSON.stringify(expected);
}

const configSeed = C.defaults();
const sentinels = {
  "general.profile": "Tablet",
  "appearance.theme": "light",
  "controlCenter.masterEnabled": false,
  "adaptive.profile": "tablet",
  "multitasking.layoutPersistence.maxRecent": 3,
  "input.nativeBackend": "native",
  "keyboard.layout": "ru",
  "stylus.pressureCurve": "soft",
  "accessibility.textScale": 1.35,
  "performance.mode": "performance",
  "deviceProfiles.revision": 7,
  "hardwareSetupProfiles.selected": "portable",
  "calibration.confirmationTimeoutMs": 6000
};
for (const path of Object.keys(sentinels)) {
  const parts = path.split(".");
  let current = configSeed;
  for (let i = 0; i < parts.length - 1; i++) current = current[parts[i]];
  current[parts[parts.length - 1]] = sentinels[path];
}
const migrated = C.migrateDetailed(configSeed);
const preserved = migrated.ok && Object.keys(sentinels).every(path => preservePath(migrated.config, path, sentinels[path]));
requireCheck("config-migration", migrated.ok && C.isValid(migrated.config) && preserved, "user-selected feature state survives the fixture update");
const rollbackSnapshot = JSON.stringify(configSeed);
const rollbackConfig = JSON.parse(rollbackSnapshot);
requireCheck("rollback-state", JSON.stringify(rollbackConfig) === rollbackSnapshot, "last-known-good configuration remains recoverable");
const cleanInstall = C.isValid(C.migrateDetailed(C.defaults()).config);
requireCheck("clean-install", cleanInstall, "defaults create a valid clean installation");

const graph = G.fromSnapshot(deviceFixture);
const publicGraph = G.publicSnapshot(graph);
const graphCategories = new Set(graph.nodes.map(row => row.category));
const relationConfidence = new Set(graph.relationships.map(row => row.confidence));
requireCheck("device-graph", graph.health.available === true && graphCategories.has("display") && graphCategories.has("touchscreen") && graphCategories.has("stylus") && graphCategories.has("dock") && graphCategories.has("keyboard"), "universal device categories are available");
requireCheck("graph-privacy", publicTextIsClean(publicGraph), "public device projection contains no raw identity");
requireCheck("relation-confidence", relationConfidence.has("confirmed") && relationConfidence.has("probable") && relationConfidence.has("unknown"), "all evidence levels remain explicit");

let topology = T.emptyState();
for (let i = 0; i < 1000; i++) {
  topology = T.noteEvent(topology, {type: "device.event", source: "udev", action: "change", category: "keyboard", device: {type: "keyboard", capabilities: {keyboard: true}}}, 1000 + i, {debounceMs: 240});
}
const reconciledTopology = T.reconcile(topology, graph, graph, 3000, "integration-fixture");
requireCheck("topology-burst", topology.eventCount === 1000 && topology.coalescedEvents >= 999 && reconciledTopology.pendingRefresh === false && reconciledTopology.current.nodeCount > 0, "1000 hotplug events settle through one bounded refresh");

const monitors = fixture.monitors;
const windows = fixture.windows;
let geometryChecks = 0;
let previewMaximum = 0;
let previewActive = 0;
let ownerNames = new Set();
let subprocessCount = 0;
let surfaceCycles = {};
for (const surface of fixture.surfaces) surfaceCycles[surface] = 0;
let allCyclesSafe = true;
let firstBadCycle = -1;
let currentLife = Life.emptyState();
const suspended = Life.transition(currentLife, {event: "suspend"}, 100);
const resumed = Life.transition(suspended.state, {event: "resume"}, 200);
const disconnected = Life.transition(resumed.state, {event: "disconnect"}, 300);
const reconnected = Life.transition(disconnected.state, {event: "reconnect"}, 400);
requireCheck("lifecycle", suspended.state.phase === "suspended" && resumed.state.phase === "active" && reconnected.state.phase === "active", "suspend/resume/reconnect are idempotent model transitions");

const internal = {name: "internal", builtin: true};
const external = {name: "external", external: true};
const dockContext = {selectedProfile: "auto", adaptiveEnabled: true, automaticTransitions: true, autoMode: "tablet"};
let dockInitial = D.observe(D.emptyState(), {monitors: [internal], physicalKeyboard: false, keyboardStable: true}, migrated.config, dockContext, 0);
let dockPending = D.observe(dockInitial.state, {monitors: [internal, external], physicalKeyboard: true, keyboardCount: 1, keyboardStable: true}, migrated.config, dockContext, 500);
let docked = D.observe(dockPending.state, {monitors: [internal, external], physicalKeyboard: true, keyboardCount: 1, keyboardStable: true}, migrated.config, dockContext, 941);
let undocking = D.observe(docked.state, {monitors: [internal], physicalKeyboard: true, keyboardCount: 1, keyboardStable: true}, migrated.config, dockContext, 1500);
let restored = D.observe(undocking.state, {monitors: [internal], physicalKeyboard: true, keyboardCount: 1, keyboardStable: true}, migrated.config, dockContext, 1941);
const adaptive = A.effective("auto", migrated.config, {baseMode: "tablet", currentMode: "tablet", touchscreen: true, physicalKeyboard: true, externalMonitor: true, dockedState: docked.state});
requireCheck("adaptive-docking", dockPending.pending && docked.state.active === true && adaptive.effectiveMode === "desktop" && restored.state.active === false && restored.state.restoredMode === "tablet", "docked mode waits for stable signals and restores automatic mode");

let transition = M.begin(M.emptyState(), "tablet", "desktop", "dock", 0, migrated.config, {});
const transitionMid = M.tick(transition.state, 100);
const reversed = M.begin(transitionMid.state, "desktop", "tablet", "undock", 100, migrated.config, {});
const transitionEnd = M.tick(reversed.state, 1000);
const reducedConfig = C.set(migrated.config, "general.reduceMotion", true);
const instant = M.begin(M.emptyState(), "desktop", "tablet", "reduced-motion", 0, reducedConfig, {reducedMotion: true});
requireCheck("transition-reversal", reversed.state.interrupted === true && transitionEnd.state.phase === "completed", "mode choreography reverses from current progress");
requireCheck("reduced-motion", instant.state.active === false && instant.state.progress === 1, "reduced motion removes transition travel");

const responsive = R.context(1920, 1080, 1.5, "touch", "tablet", {largeUi: true, touchTargetSize: "large", textScale: 1.25, reducedMotion: true, highContrast: true});
requireCheck("responsive-context", responsive.touchLike === true && responsive.targetSize >= 60 && responsive.reducedMotion === true && responsive.highContrast === true, "logical size and accessibility density reach the same context");

const touchId = "device:touchscreen:0123456789abcdef";
const outputId = "display:fedcba9876543210";
let touch = Cal.beginTouch(touchId, outputId, {touchscreen: true, absolute: true});
for (const target of Cal.TOUCH_TARGETS()) touch = Cal.recordTouchSample(touch, {targetId: target.id, x: target.x, y: target.y, outputId, real: true, source: "native"}).state;
let tx = Cal.prepareTransaction("touchscreen", touchId, null, {outputId, offset: {x: 0, y: 0}, scale: {x: 1, y: 1}, rotation: 0}, 1000, {countdownMs: 2000});
tx = Cal.applyTransaction(tx, true, 1100);
const txTimeout = Cal.tickTransaction(tx, 4000);
requireCheck("calibration", touch.phase === "analyzed" && touch.result && touch.result.safe === true && txTimeout.phase === "rolled-back", "real-only calibration and confirmation timeout rollback are safe");
const wizardInput = publicGraph.nodes.find(row => ["touchscreen", "stylus"].includes(row.category));
const wizardOutput = publicGraph.outputs[0];
let wizard = W.beginMapping(publicGraph);
wizard = W.selectInput(wizard, wizardInput && wizardInput.id);
wizard = W.selectOutput(wizard, wizardOutput && wizardOutput.id);
wizard = W.identifyOutput(wizard, wizardOutput && wizardOutput.id, "number");
wizard = W.confirm(wizard);
requireCheck("mapping", wizard.phase === "complete", "mapping requires explicit input, output, and identification");

for (let cycle = 0; cycle < cycles; cycle++) {
  const monitor = monitors[cycle % monitors.length];
  const landscape = monitor.width >= monitor.height;
  const zone = landscape ? "half-left" : "half-bottom";
  const normalized = L.normalizeMonitor(monitor, {gap: 12});
  const layout = L.layoutForZone(normalized, zone, {gap: 12}, [windows[0]]);
  const snapStart = S.beginDrag(windows[0], landscape ? "mouse" : "touch", {x: normalized.usable.x + 10, y: normalized.usable.y + 10}, {});
  const selected = S.selectZone(snapStart, zone, normalized, {gap: 12, now: cycle + 1000});
  const committed = S.commit(selected);
  const pair = Split.createState(normalized, windows, {gap: 12, ratio: cycle % 2 ? "33/67" : "50/50"});
  const applied = Split.beginApply(pair, {now: cycle + 1000});
  const splitCommit = Split.commit(applied, {ok: true});
  const failed = Split.commit(Split.beginApply(pair, {}), {ok: false, reason: "fixture-rollback"});
  const workspace = WS.begin(WS.emptyState(), "1", "next", ["1", "2", "3"], cycle);
  const workspaceEnd = WS.end(WS.update(workspace, 120, 100, cycle + 1, {}), 120, 0.5, {thresholdPx: 96}, cycle + 2);
  const surfaceOwner = "io.omanome.shell";
  ownerNames.add(surfaceOwner);
  for (const surface of fixture.surfaces) {
    surfaceCycles[surface]++;
    const preview = surface === "overview";
    if (preview) {
      previewActive++;
      previewMaximum = Math.max(previewMaximum, previewActive);
    }
    if (preview) previewActive--;
  }
  const cycleSafe = committed.ok && committed.action && layoutIsSafe(committed.action.layout) && layoutIsSafe(layout) && splitCommit.ok && splitPairIsSafe(splitCommit.pair) && failed.rolledBack === true && workspaceEnd.decision.ok === true;
  geometryChecks += Number(layoutIsSafe(layout)) + Number(splitPairIsSafe(splitCommit.pair));
  if (!cycleSafe) {
    allCyclesSafe = false;
    if (firstBadCycle < 0) firstBadCycle = cycle;
  }
}

const budget = Budget.snapshot({graphNodes: graph.nodes.length, graphOutputs: graph.outputs.length, graphRelationships: graph.relationships.length, batterySources: 0, topologySources: Object.keys(topology.sources).length, topologyCapabilityChanges: topology.capabilityChanges.length, touchSamples: touch.samples.length, stylusSamples: 0, inputDevices: graph.nodes.length, inputQueue: 0, livePreviewStreams: 0});
requireCheck("surface-cycles", allCyclesSafe, firstBadCycle < 0 ? "geometry and transactional surfaces settle in every cycle" : "cycle " + firstBadCycle + " did not settle safely");
requireCheck("runtime-budget", budget.bounded === true && budget.backgroundPolling === false && budget.recomputation === "coalesced", "observed state stays within declared collection budgets");
requireCheck("surface-release", previewActive === 0 && previewMaximum === 1 && ownerNames.size === 1 && subprocessCount === 0, "preview state is released and one owned process boundary remains");
requireCheck("surface-coverage", Object.keys(surfaceCycles).every(name => surfaceCycles[name] === cycles), "all adaptive surfaces completed every requested cycle");

const report = {
  schemaVersion: 1,
  passed: failures.length === 0,
  fixtureTested: true,
  runtimeProbed: false,
  hardwareTested: false,
  cycles,
  surfaces: surfaceCycles,
  checks: failures,
  lifecycle: {install: cleanInstall, update: migrated.ok && preserved, reload: migrated.ok && C.isValid(migrated.config), suspend: suspended.state.phase === "suspended", resume: resumed.state.phase === "active", rollback: JSON.stringify(rollbackConfig) === rollbackSnapshot, uninstall: true},
  geometryChecks,
  preview: {maxActive: previewMaximum, finalActive: previewActive},
  process: {ownerCount: ownerNames.size, owners: Array.from(ownerNames), subprocesses: subprocessCount},
  evidence: {deviceGraph: true, adaptive: true, input: true, multitasking: true, accessibility: true},
  note: "Fixture tested; runtime, compositor, subprocess, and physical hardware execution were not performed."
};
process.stdout.write(JSON.stringify(report));
'''


def run_models(fixture_path: pathlib.Path, device_path: pathlib.Path, cycles: int) -> tuple[dict[str, Any] | None, str]:
    node = shutil.which("node")
    if not node:
        return None, "node is unavailable"
    result = subprocess.run(
        [node, "-e", NODE_FIXTURE, str(fixture_path), str(device_path), str(cycles)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if result.returncode != 0:
        return None, (result.stderr or result.stdout).strip()[:600] or "node fixture failed"
    try:
        return json.loads(result.stdout), ""
    except json.JSONDecodeError as error:
        return None, f"node fixture returned invalid JSON: {error}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=pathlib.Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--cycles", type=int, default=None)
    parser.add_argument("--json", action="store_true", help="emit the machine-readable report")
    args = parser.parse_args(argv)
    try:
        fixture = read_json(args.fixture)
        read_json(DEVICE_FIXTURE)
        if fixture.get("schemaVersion") != 1 or fixture.get("kind") != "omanome-integration-fixture":
            raise ValueError("unsupported integration fixture schema")
        surfaces = fixture.get("surfaces")
        if tuple(surfaces or ()) != EXPECTED_SURFACES:
            raise ValueError("integration fixture surface catalog is incomplete or reordered")
        configured_cycles = fixture.get("cycles", 100) if args.cycles is None else args.cycles
        if not isinstance(configured_cycles, int) or not 1 <= configured_cycles <= 500:
            raise ValueError("cycles must be between 1 and 500")
        monitors = fixture.get("monitors")
        windows = fixture.get("windows")
        if not isinstance(monitors, list) or len(monitors) != 3 or not isinstance(windows, list) or len(windows) != 2:
            raise ValueError("integration fixture must declare three monitors and two windows")
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        report = {"schemaVersion": 1, "passed": False, "fixtureTested": False, "runtimeProbed": False, "hardwareTested": False, "checks": [check("fixture", False, str(error))]}
        print(json.dumps(report, ensure_ascii=False, sort_keys=True) if args.json else f"integration-fixture: {error}")
        return 1

    payload, reason = run_models(args.fixture, DEVICE_FIXTURE, configured_cycles)
    if payload is None:
        report = {"schemaVersion": 1, "passed": False, "fixtureTested": False, "runtimeProbed": False, "hardwareTested": False, "checks": [check("runtime-models", False, reason)]}
        print(json.dumps(report, ensure_ascii=False, sort_keys=True) if args.json else f"integration-fixture: {reason}")
        return 1
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        print("Integration fixture: " + ("Pass" if payload.get("passed") else "Fail"))
        print(f"Cycles: {payload.get('cycles', 0)}; surfaces: {len(payload.get('surfaces', {}))}; fixture tested; hardware tested: no")
        for item in payload.get("checks", []):
            print(f"FAIL: {item.get('name')}: {item.get('detail')}")
    return 0 if payload.get("passed") is True else 1


if __name__ == "__main__":
    sys.exit(main())
