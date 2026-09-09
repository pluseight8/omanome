// Runtime docking continuity and recovery model.
//
// This model records only user intent and opaque graph output IDs. It does not
// move windows, write configuration, or issue compositor commands. A caller
// may consume the bounded restore plan after an explicit runtime boundary.

var SCHEMA_VERSION = 1
var MAX_OUTPUTS = 16
var MAX_ACTIONS = 4
var MIN_DEBOUNCE_MS = 80
var MAX_DEBOUNCE_MS = 1500
var PHASES = ["undocked", "docking", "docked", "undocking", "recovering", "paused"]
var MODES = ["desktop", "tablet", "hybrid", "presentation", "drawing"]
var ORIENTATIONS = ["auto", "normal", "90", "180", "270"]
var DISPLAY_ID = /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function clamp(value, minimum, maximum, fallback) {
  return Math.max(minimum, Math.min(maximum, number(value, fallback)))
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function safeId(value) {
  var id = string(value).trim()
  return DISPLAY_ID.test(id) ? id : ""
}

function safeMode(value) {
  var name = token(value)
  return MODES.indexOf(name) >= 0 ? name : "desktop"
}

function safeOrientation(value) {
  return ORIENTATIONS.indexOf(token(value)) >= 0 ? token(value) : "auto"
}

function outputRows(graph) {
  var source = object(graph)
  var rows = []
  var seen = {}
  var outputs = array(source.outputs)
  for (var i = 0; i < outputs.length; i++) {
    var output = object(outputs[i])
    var id = safeId(output.id)
    if (!id || seen[id]) continue
    seen[id] = true
    rows.push({ id: id, role: token(output.role) || "unknown", connected: output.connected !== false })
  }
  if (rows.length === 0) {
    var nodes = array(source.nodes)
    for (var n = 0; n < nodes.length; n++) {
      var node = object(nodes[n])
      if (token(node.category) !== "display") continue
      var nodeId = safeId(node.id)
      if (!nodeId || seen[nodeId]) continue
      seen[nodeId] = true
      rows.push({ id: nodeId, role: "unknown", connected: node.connected === true })
    }
  }
  return rows.slice(0, MAX_OUTPUTS)
}

function inventory(graph) {
  var rows = outputRows(graph)
  var external = []
  var internal = []
  var unknown = []
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i].connected) continue
    if (rows[i].role === "external") external.push(rows[i].id)
    else if (rows[i].role === "internal") internal.push(rows[i].id)
    else unknown.push(rows[i].id)
  }
  return {
    outputCount: rows.length,
    connectedCount: external.length + internal.length + unknown.length,
    externalIds: external,
    internalIds: internal,
    unknownIds: unknown,
    externalConnected: external.length > 0,
    internalConnected: internal.length > 0,
    unknownConnected: unknown.length > 0,
    signature: external.slice().sort().join(",") + "|" + internal.slice().sort().join(",") + "|" + unknown.slice().sort().join(",")
  }
}

function contextValues(context) {
  var source = object(context)
  var surfaceOutputs = []
  var rawOutputs = array(source.surfaceOutputs || source.surface_outputs)
  for (var i = 0; i < rawOutputs.length && surfaceOutputs.length < MAX_OUTPUTS; i++) {
    var id = safeId(rawOutputs[i])
    if (id && surfaceOutputs.indexOf(id) < 0) surfaceOutputs.push(id)
  }
  return {
    mode: safeMode(source.mode),
    orientation: safeOrientation(source.orientation),
    layoutFamily: token(source.layoutFamily || source.layout_family || source.mode) || "desktop",
    keyboardConnected: source.keyboardConnected === true || Number(source.keyboardCount || 0) > 0,
    keyboardStable: source.keyboardStable !== false,
    automatic: source.automatic !== false,
    dockedHint: source.docked === true,
    primaryDisplayId: safeId(source.primaryDisplayId || source.primary_display_id),
    oskOutputId: safeId(source.oskOutputId || source.osk_output_id),
    surfaceOutputs: surfaceOutputs,
    setupId: token(source.setupId || source.setup_id) || "auto"
  }
}

function debounceMs(options) {
  var value = number(object(options).debounceMs, 260)
  return clamp(value, MIN_DEBOUNCE_MS, MAX_DEBOUNCE_MS, 260)
}

function copyState(state) {
  var source = state && typeof state === "object" ? state : emptyState()
  var result = {}
  for (var key in source) result[key] = source[key]
  result.stableExternalIds = array(source.stableExternalIds).slice()
  result.stableInternalIds = array(source.stableInternalIds).slice()
  result.stableUnknownIds = array(source.stableUnknownIds).slice()
  result.continuity = Object.assign({}, object(source.continuity), { savedExternalIds: array(object(source.continuity).savedExternalIds).slice(), surfaceOutputs: array(object(source.continuity).surfaceOutputs).slice() })
  result.restore = Object.assign({}, object(source.restore), { actions: array(object(source.restore).actions).slice() })
  result.rollback = Object.assign({}, object(source.rollback))
  result.lastEvent = Object.assign({}, object(source.lastEvent))
  return result
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: 0,
    initialized: false,
    phase: "undocked",
    active: false,
    pending: false,
    paused: false,
    stableSignature: "",
    candidateSignature: "",
    candidateSince: 0,
    candidateReadyAt: 0,
    externalConnected: false,
    internalConnected: false,
    unknownConnected: false,
    keyboardConnected: false,
    keyboardStable: true,
    stableExternalIds: [],
    stableInternalIds: [],
    stableUnknownIds: [],
    continuity: { valid: false, savedAt: 0, mode: "desktop", orientation: "auto", layoutFamily: "desktop", savedExternalIds: [], primaryDisplayId: "", oskOutputId: "", surfaceOutputs: [], setupId: "auto" },
    restore: { pending: false, actions: [], targetDisplayId: "", requiresChoice: false, reason: "none" },
    rollback: { required: false, reason: "none", at: 0 },
    lastEvent: { type: "none", reason: "not-evaluated", at: 0 },
    reason: "not-evaluated"
  }
}

function topologySignature(info, values, active) {
  return [active ? "docked" : "undocked", info.signature, values.keyboardConnected, values.keyboardStable, values.mode, values.orientation].join("|")
}

function captureContinuity(info, values, timestamp) {
  return {
    valid: true,
    savedAt: timestamp,
    mode: values.mode,
    orientation: values.orientation,
    layoutFamily: values.layoutFamily,
    savedExternalIds: info.externalIds.slice(0, MAX_OUTPUTS),
    primaryDisplayId: values.primaryDisplayId,
    oskOutputId: values.oskOutputId,
    surfaceOutputs: values.surfaceOutputs.slice(0, MAX_OUTPUTS),
    setupId: values.setupId
  }
}

function contains(values, id) {
  return array(values).indexOf(id) >= 0
}

function restorePlan(state, info, values, reason) {
  var continuity = object(state.continuity)
  var actions = []
  if (continuity.layoutFamily) actions.push("restore-layout")
  if (array(continuity.surfaceOutputs).length > 0) actions.push("restore-surfaces")
  if (continuity.oskOutputId) actions.push("restore-osk-target")
  var available = info.internalIds.concat(info.externalIds).concat(info.unknownIds)
  var target = ""
  if (continuity.primaryDisplayId && contains(available, continuity.primaryDisplayId)) target = continuity.primaryDisplayId
  else if (continuity.oskOutputId && contains(available, continuity.oskOutputId)) target = continuity.oskOutputId
  var missingSavedOutput = array(continuity.savedExternalIds).some(function(id) { return !contains(info.externalIds, id) })
  var needsChoice = missingSavedOutput && target === ""
  if (actions.length > MAX_ACTIONS) actions = actions.slice(0, MAX_ACTIONS)
  return {
    pending: actions.length > 0,
    actions: actions,
    targetDisplayId: target,
    requiresChoice: needsChoice,
    reason: reason || (missingSavedOutput ? "docked-output-disconnected" : "restore-continuity"),
    rollbackRequired: missingSavedOutput
  }
}

function commit(previous, info, values, active, timestamp, eventType, forceRecovery) {
  var next = copyState(previous)
  var wasActive = next.active === true
  next.initialized = true
  next.active = active === true
  next.pending = false
  next.candidateSignature = ""
  next.candidateSince = 0
  next.candidateReadyAt = 0
  next.stableSignature = topologySignature(info, values, next.active)
  next.externalConnected = info.externalConnected
  next.internalConnected = info.internalConnected
  next.unknownConnected = info.unknownConnected
  next.keyboardConnected = values.keyboardConnected
  next.keyboardStable = values.keyboardStable
  next.stableExternalIds = info.externalIds.slice(0, MAX_OUTPUTS)
  next.stableInternalIds = info.internalIds.slice(0, MAX_OUTPUTS)
  next.stableUnknownIds = info.unknownIds.slice(0, MAX_OUTPUTS)
  next.revision = Number(next.revision || 0) + 1
  next.rollback = forceRecovery ? { required: true, reason: "docked-output-disconnected", at: timestamp } : next.rollback
  if (next.active && !wasActive) next.continuity = captureContinuity(info, values, timestamp)
  if (!next.active && wasActive && next.continuity.valid) {
    var plan = restorePlan(next, info, values, forceRecovery ? "docked-output-disconnected" : "undocked-restore")
    next.restore = { pending: plan.pending, actions: plan.actions, targetDisplayId: plan.targetDisplayId, requiresChoice: plan.requiresChoice, reason: plan.reason }
    if (plan.rollbackRequired) next.rollback = { required: true, reason: plan.reason, at: timestamp }
    next.phase = plan.pending ? "recovering" : "undocked"
    next.reason = plan.reason
  } else {
    next.restore = next.restore && next.active ? next.restore : { pending: false, actions: [], targetDisplayId: "", requiresChoice: false, reason: "none" }
    next.phase = next.active ? (forceRecovery ? "recovering" : "docked") : "undocked"
    next.reason = forceRecovery ? "docked-output-disconnected" : (next.active ? "docked-topology-stable" : "undocked-topology-stable")
  }
  next.lastEvent = { type: eventType || (next.active ? "docked" : "undocked"), reason: next.reason, at: timestamp }
  return next
}

function observe(previous, graph, context, now, options) {
  var old = copyState(previous || emptyState())
  var values = contextValues(context)
  var info = inventory(graph)
  var timestamp = Math.max(0, Math.floor(number(now, Date.now())))
  if (old.paused) return { changed: false, pending: false, delayMs: 0, state: old, inventory: info }
  var derivedEligible = info.externalConnected && values.keyboardConnected && values.keyboardStable && values.automatic
  var desired = values.dockedHint || derivedEligible
  var signature = topologySignature(info, values, desired)
  var savedExternal = array(old.continuity.savedExternalIds)
  var disconnected = old.active && savedExternal.some(function(id) { return !contains(info.externalIds, id) })
  if (!old.initialized) {
    if (!desired) return { changed: false, pending: false, delayMs: 0, state: commit(old, info, values, false, timestamp, "initial", false), inventory: info }
    var first = copyState(old)
    first.initialized = true
    first.pending = true
    first.phase = "docking"
    first.candidateSignature = signature
    first.candidateSince = timestamp
    first.candidateReadyAt = timestamp + debounceMs(options)
    first.externalConnected = info.externalConnected
    first.internalConnected = info.internalConnected
    first.keyboardConnected = values.keyboardConnected
    first.keyboardStable = values.keyboardStable
    first.revision = Number(first.revision || 0) + 1
    first.reason = "docking-topology-observed"
    first.lastEvent = { type: "docking", reason: first.reason, at: timestamp }
    return { changed: false, pending: true, delayMs: debounceMs(options), state: first, inventory: info }
  }
  if (disconnected && !desired) {
    var recovered = commit(old, info, values, false, timestamp, "undocked", true)
    return { changed: true, pending: false, delayMs: 0, state: recovered, inventory: info }
  }
  if (disconnected && desired) {
    var degraded = copyState(old)
    degraded.phase = "recovering"
    degraded.rollback = { required: true, reason: "docked-output-disconnected", at: timestamp }
    degraded.restore = restorePlan(degraded, info, values, "docked-output-disconnected")
    degraded.restore = { pending: degraded.restore.pending, actions: degraded.restore.actions, targetDisplayId: degraded.restore.targetDisplayId, requiresChoice: degraded.restore.requiresChoice, reason: degraded.restore.reason }
    degraded.reason = "docked-output-disconnected"
    degraded.revision = Number(degraded.revision || 0) + 1
    degraded.lastEvent = { type: "recovering", reason: degraded.reason, at: timestamp }
    return { changed: false, pending: false, delayMs: 0, state: degraded, inventory: info }
  }
  if (signature === string(old.stableSignature) && !old.pending) {
    var steady = commit(old, info, values, desired, timestamp, null, false)
    steady.revision = Number(old.revision || 0) + 1
    return { changed: false, pending: false, delayMs: 0, state: steady, inventory: info }
  }
  var candidate = copyState(old)
  if (candidate.candidateSignature !== signature || !candidate.candidateSince) {
    candidate.pending = true
    candidate.candidateSignature = signature
    candidate.candidateSince = timestamp
    candidate.candidateReadyAt = timestamp + debounceMs(options)
    candidate.phase = desired ? "docking" : old.active ? "undocking" : "undocked"
    candidate.externalConnected = info.externalConnected
    candidate.internalConnected = info.internalConnected
    candidate.unknownConnected = info.unknownConnected
    candidate.keyboardConnected = values.keyboardConnected
    candidate.keyboardStable = values.keyboardStable
    candidate.reason = desired ? "docking-topology-changing" : "undocking-topology-changing"
    candidate.lastEvent = { type: candidate.phase, reason: candidate.reason, at: timestamp }
    candidate.revision = Number(candidate.revision || 0) + 1
    return { changed: false, pending: true, delayMs: debounceMs(options), state: candidate, inventory: info }
  }
  var remaining = Math.max(0, Number(candidate.candidateReadyAt || 0) - timestamp)
  if (remaining > 0) {
    candidate.pending = true
    candidate.revision = Number(candidate.revision || 0) + 1
    return { changed: false, pending: true, delayMs: remaining, state: candidate, inventory: info }
  }
  var committed = commit(candidate, info, values, desired, timestamp, desired ? "docked" : "undocked", false)
  return { changed: true, pending: false, delayMs: 0, state: committed, inventory: info }
}

function lifecycle(previous, event, now) {
  var next = copyState(previous || emptyState())
  var source = object(event)
  var action = token(source.action || source.event || source.state)
  var timestamp = Math.max(0, Math.floor(number(now, Date.now())))
  if (["suspend", "sleep", "lock"].indexOf(action) >= 0) {
    next.paused = true
    next.pending = false
    next.phase = "paused"
    next.reason = "session-paused"
    next.lastEvent = { type: "paused", reason: next.reason, at: timestamp }
    next.revision = Number(next.revision || 0) + 1
  } else if (["resume", "wakeup", "unlock"].indexOf(action) >= 0) {
    next.paused = false
    next.pending = true
    next.phase = "recovering"
    next.reason = "resume-topology-refresh"
    next.candidateSignature = ""
    next.candidateSince = 0
    next.candidateReadyAt = timestamp
    next.lastEvent = { type: "resume", reason: next.reason, at: timestamp }
    next.revision = Number(next.revision || 0) + 1
  }
  return next
}

function acknowledgeRestore(previous, accepted, reason) {
  var next = copyState(previous || emptyState())
  if (!next.restore.pending) return next
  next.restore.pending = false
  next.restore.reason = accepted === true ? "restore-accepted" : string(reason || "restore-cancelled")
  if (accepted !== true) next.rollback = { required: true, reason: next.restore.reason, at: Date.now() }
  next.revision = Number(next.revision || 0) + 1
  next.reason = next.restore.reason
  return next
}

function summary(state) {
  var source = copyState(state || emptyState())
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: Number(source.revision || 0),
    phase: PHASES.indexOf(string(source.phase)) >= 0 ? string(source.phase) : "undocked",
    active: source.active === true,
    pending: source.pending === true,
    paused: source.paused === true,
    externalConnected: source.externalConnected === true,
    internalConnected: source.internalConnected === true,
    unknownConnected: source.unknownConnected === true,
    keyboardConnected: source.keyboardConnected === true,
    keyboardStable: source.keyboardStable !== false,
    stableExternalIds: array(source.stableExternalIds).slice(0, MAX_OUTPUTS),
    continuity: Object.assign({}, source.continuity, { savedExternalIds: array(source.continuity.savedExternalIds).slice(0, MAX_OUTPUTS), surfaceOutputs: array(source.continuity.surfaceOutputs).slice(0, MAX_OUTPUTS) }),
    restore: Object.assign({}, source.restore, { actions: array(source.restore.actions).slice(0, MAX_ACTIONS), targetDisplayId: safeId(source.restore.targetDisplayId) }),
    rollback: Object.assign({}, source.rollback),
    lastEvent: { type: string(source.lastEvent.type || "none"), reason: string(source.lastEvent.reason || ""), at: Number(source.lastEvent.at || 0) },
    reason: string(source.reason || "")
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  PHASES: PHASES,
  inventory: inventory,
  emptyState: emptyState,
  observe: observe,
  lifecycle: lifecycle,
  acknowledgeRestore: acknowledgeRestore,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
