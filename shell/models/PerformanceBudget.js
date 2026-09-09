// Shared, observable limits for hardware-aware runtime state.
//
// This is a policy/reporting model only. It never schedules work or claims
// that a physical device was certified. Unknown measurements remain unknown;
// only observed values above a hard collection limit make the report fail.

var SCHEMA_VERSION = 1
var LIMITS = {
  graphNodes: 256,
  graphOutputs: 32,
  graphRelationships: 512,
  batterySources: 16,
  topologySources: 16,
  topologyCapabilityChanges: 32,
  touchSamples: 5,
  stylusSamples: 256,
  inputDevices: 256,
  inputQueue: 64,
  livePreviewStreams: 8
}
var METRICS = Object.keys(LIMITS)

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function number(value) {
  var result = Number(value)
  return isFinite(result) && result >= 0 ? result : null
}

function limitCopy() {
  var result = {}
  for (var key in LIMITS) result[key] = LIMITS[key]
  return result
}

function metric(value, limit) {
  var observed = number(value)
  return { observed: observed, limit: limit, known: observed !== null, withinLimit: observed === null || observed <= limit }
}

function snapshot(raw) {
  var source = object(raw)
  var metrics = {}
  var checks = []
  var overBudget = []
  for (var i = 0; i < METRICS.length; i++) {
    var name = METRICS[i]
    var row = metric(source[name], LIMITS[name])
    metrics[name] = row
    checks.push({ name: name, result: row.withinLimit ? "Pass" : "Fail", observed: row.observed, limit: row.limit, known: row.known })
    if (!row.withinLimit) overBudget.push(name)
  }
  return {
    schemaVersion: SCHEMA_VERSION,
    mode: "event-driven",
    evidence: "runtime-state",
    backgroundPolling: false,
    recomputation: "coalesced",
    bounded: overBudget.length === 0,
    limits: limitCopy(),
    metrics: metrics,
    checks: checks,
    overBudget: overBudget
  }
}

function emptyState() { return snapshot({}) }

function summary(value) {
  var source = object(value)
  var metrics = object(source.metrics)
  var result = {}
  for (var i = 0; i < METRICS.length; i++) {
    var name = METRICS[i]
    var row = object(metrics[name])
    result[name] = { observed: number(row.observed), limit: LIMITS[name], withinLimit: row.withinLimit !== false }
  }
  return {
    schemaVersion: SCHEMA_VERSION,
    mode: String(source.mode || "event-driven"),
    evidence: String(source.evidence || "runtime-state"),
    backgroundPolling: source.backgroundPolling === true,
    recomputation: String(source.recomputation || "coalesced"),
    bounded: source.bounded !== false,
    metrics: result,
    overBudget: Array.isArray(source.overBudget) ? source.overBudget.slice(0, METRICS.length) : []
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  LIMITS: LIMITS,
  snapshot: snapshot,
  emptyState: emptyState,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
