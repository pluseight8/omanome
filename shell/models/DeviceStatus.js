// Compact, truthful device status for Control Center and diagnostics.
//
// This model is intentionally a projection of already-sanitized runtime
// state. It does not inspect names, paths, event nodes, or vendor strings and
// it never turns an unknown display role into an external-display fact.

var SCHEMA_VERSION = 1
var CONFIDENCE = ["unknown", "probable", "confirmed"]
var CATEGORY_KEYS = ["keyboard", "touchscreen", "stylus", "display"]

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function confidence(value) {
  var result = string(value || "unknown").toLowerCase()
  return CONFIDENCE.indexOf(result) >= 0 ? result : "unknown"
}

function bestConfidence(rows) {
  var result = "unknown"
  for (var i = 0; i < rows.length; i++) {
    var current = confidence(rows[i] && rows[i].confidence)
    if (CONFIDENCE.indexOf(current) > CONFIDENCE.indexOf(result)) result = current
  }
  return result
}

function categoryRows(graph, category) {
  var rows = array(object(graph).nodes)
  return rows.filter(function(row) { return row && string(row.category).toLowerCase() === category })
}

function connectedRows(rows) {
  return rows.filter(function(row) { return row && row.connected === true })
}

function fallbackSignals(signals, category) {
  var source = object(signals)
  var devices = array(source[category + "Devices"])
  var has = category === "keyboard" ? source.hasPhysicalKeyboard === true : category === "touchscreen" ? source.hasTouchscreen === true : category === "stylus" ? source.hasStylus === true : false
  var connected = devices.filter(function(row) { return row && row.connected === true }).length
  if (category === "keyboard" && source.hasPhysicalKeyboard === true && connected === 0) connected = 1
  if (category === "touchscreen" && source.hasTouchscreen === true && connected === 0) connected = 1
  if (category === "stylus" && source.hasStylus === true && connected === 0) connected = 1
  return { available: devices.length > 0 || has, connected: connected, count: devices.length, confidence: "unknown", source: "input-state" }
}

function connectionState(available, connected, unknown) {
  if (!available) return "unavailable"
  if (unknown === true) return "unknown"
  return connected > 0 ? "connected" : "disconnected"
}

function inputRow(key, label, icon, category, signals) {
  var source = object(signals)
  var rows = categoryRows(source.graph, category)
  var fallback = fallbackSignals(source, category)
  var available = rows.length > 0 || fallback.available
  var connected = connectedRows(rows).length
  var count = rows.length
  var evidence = rows.length > 0 ? bestConfidence(rows) : fallback.confidence
  var sourceName = rows.length > 0 ? "device-graph" : fallback.source
  if (rows.length === 0 && connected === 0 && fallback.connected > 0) connected = fallback.connected
  if (rows.length === 0 && count === 0 && fallback.count > 0) count = fallback.count
  if (count === 0 && connected > 0) count = connected
  return {
    key: key,
    label: label,
    icon: icon,
    status: connectionState(available, connected, false),
    available: available,
    connected: connected > 0,
    count: count,
    confidence: evidence,
    source: sourceName,
    reason: available ? (connected > 0 ? "connected-device-evidence" : "known-device-disconnected") : "no-verified-device"
  }
}

function displayRows(graph, policy) {
  var state = object(policy)
  var displays = object(state.displays)
  var rows = array(displays.rows)
  if (rows.length > 0) return rows
  return array(object(graph).outputs)
}

function displayRole(row) {
  var source = object(row)
  // HardwarePolicies keeps baseRole when a display is also the primary
  // display. Preserve that explicit evidence for external-display status.
  return { role: string(source.role || "unknown").toLowerCase(), baseRole: string(source.baseRole || "").toLowerCase() }
}

function externalDisplayRow(graph, policy) {
  var rows = displayRows(graph, policy)
  var external = []
  var unknownConnected = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i] || {}
    var role = displayRole(row)
    if (role.role === "external" || role.role === "presentation" || role.baseRole === "external" || role.baseRole === "presentation") external.push(row)
    else if (row.connected === true && role.role === "unknown") unknownConnected.push(row)
  }
  var connected = external.filter(function(row) { return row && row.connected === true }).length
  var available = rows.length > 0
  var unknown = connected === 0 && external.length === 0 && unknownConnected.length > 0
  var state = connectionState(available, connected, unknown)
  return {
    key: "external-display",
    label: "External display",
    icon: "▣",
    status: state,
    available: available,
    connected: connected > 0,
    count: connected,
    confidence: bestConfidence(external.length > 0 ? external : rows),
    source: rows.length > 0 ? "display-policy" : "device-graph",
    reason: !available ? "no-display-inventory" : state === "unknown" ? "external-role-unresolved" : connected > 0 ? "explicit-external-role" : external.length > 0 ? "external-display-disconnected" : "no-explicit-external-role"
  }
}

function topologySummary(value) {
  var source = object(value)
  var phase = string(source.phase || "idle")
  var pending = source.pendingRefresh === true
  return {
    phase: phase,
    pendingRefresh: pending,
    stale: source.stale === true,
    groupedEvents: true,
    eventCount: Math.max(0, Math.floor(number(source.eventCount, 0))),
    coalescedEvents: Math.max(0, Math.floor(number(source.coalescedEvents, 0))),
    reason: string(source.pendingReason || source.reason || "")
  }
}

function modeRow(signals) {
  var source = object(signals)
  var mode = string(source.effectiveMode || source.detectedMode || "desktop") || "desktop"
  return {
    key: "mode",
    label: "Mode",
    icon: "◈",
    status: "active",
    available: true,
    connected: true,
    count: 1,
    value: mode,
    profile: string(source.adaptiveProfile || "auto"),
    confidence: "confirmed",
    source: "runtime-policy",
    reason: "effective-mode"
  }
}

function emptyNotice() {
  return { schemaVersion: SCHEMA_VERSION, visible: false, key: "", categories: [], grouped: true, at: 0, expiresAt: 0, eventCount: 0, coalescedEvents: 0 }
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: 0,
    rows: [modeRow({}), inputRow("keyboard", "Keyboard", "⌨", "keyboard", {}), inputRow("touch", "Touch", "⌁", "touchscreen", {}), inputRow("stylus", "Stylus", "✎", "stylus", {}), externalDisplayRow({}, {})],
    topology: topologySummary({}),
    notice: emptyNotice(),
    available: false,
    connected: 0,
    unknown: 0
  }
}

function snapshot(graph, policy, signals) {
  var source = object(signals)
  source.graph = graph
  var rows = [
    modeRow(source),
    inputRow("keyboard", "Keyboard", "⌨", "keyboard", source),
    inputRow("touch", "Touch", "⌁", "touchscreen", source),
    inputRow("stylus", "Stylus", "✎", "stylus", source),
    externalDisplayRow(graph, policy)
  ]
  var available = rows.filter(function(row) { return row.available === true }).length
  var connected = rows.filter(function(row) { return row.connected === true }).length
  var unknown = rows.filter(function(row) { return row.status === "unknown" }).length
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: Number(object(graph).revision || 0),
    rows: rows,
    topology: topologySummary(source.topology),
    notice: object(source.notice).visible === true ? source.notice : emptyNotice(),
    available: available > 0,
    connected: connected,
    unknown: unknown
  }
}

function connectedCategoryCounts(graph) {
  var result = {}
  var nodes = array(object(graph).nodes)
  for (var i = 0; i < nodes.length; i++) {
    var row = nodes[i] || {}
    if (row.connected !== true) continue
    var category = string(row.category || "unknown").toLowerCase()
    result[category] = Number(result[category] || 0) + 1
  }
  var outputs = array(object(graph).outputs)
  var displays = outputs.filter(function(row) { return row && row.connected === true }).length
  if (displays > 0) result.display = displays
  return result
}

function changedCategories(previous, next) {
  var before = connectedCategoryCounts(previous)
  var after = connectedCategoryCounts(next)
  var names = {}
  for (var oldName in before) names[oldName] = true
  for (var newName in after) names[newName] = true
  return Object.keys(names).filter(function(name) { return Number(before[name] || 0) !== Number(after[name] || 0) }).sort()
}

function connectionNotice(previous, next, topology, now, previousNotice, options) {
  var timestamp = Math.max(0, Math.floor(number(now, Date.now())))
  var settings = object(options)
  var duration = Math.max(800, Math.min(10000, Math.floor(number(settings.durationMs, 2600))))
  var oldNotice = object(previousNotice)
  var oldGraph = object(previous)
  if (!previous || (!Array.isArray(oldGraph.nodes) && !Array.isArray(oldGraph.outputs))) return emptyNotice()
  var categories = changedCategories(previous, next)
  if (categories.length === 0) {
    if (oldNotice.visible === true && Number(oldNotice.expiresAt || 0) > timestamp) return oldNotice
    return emptyNotice()
  }
  var source = object(topology)
  var added = []
  var removed = []
  var before = connectedCategoryCounts(previous)
  var after = connectedCategoryCounts(next)
  for (var i = 0; i < categories.length; i++) {
    var category = categories[i]
    if (Number(after[category] || 0) > Number(before[category] || 0)) added.push(category)
    if (Number(after[category] || 0) < Number(before[category] || 0)) removed.push(category)
  }
  var key = added.length > 0 && removed.length === 0 ? "connected" : removed.length > 0 && added.length === 0 ? "disconnected" : "changed"
  return {
    schemaVersion: SCHEMA_VERSION,
    visible: true,
    key: key,
    categories: categories.slice(0, 8),
    grouped: categories.length > 1 || Number(source.coalescedEvents || 0) > 0,
    at: timestamp,
    expiresAt: timestamp + duration,
    eventCount: Math.max(0, Math.floor(number(source.eventCount, 0))),
    coalescedEvents: Math.max(0, Math.floor(number(source.coalescedEvents, 0)))
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  CATEGORY_KEYS: CATEGORY_KEYS,
  emptyNotice: emptyNotice,
  emptyState: emptyState,
  snapshot: snapshot,
  connectionNotice: connectionNotice,
  topologySummary: topologySummary
}
if (typeof module !== "undefined") module.exports = api
