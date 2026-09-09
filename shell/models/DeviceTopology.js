// Event-driven topology aggregation for the universal device graph.
//
// This module is deliberately a runtime coordinator, not another hardware
// database. It keeps bounded event metadata, coalesces refresh requests, and
// compares two already-sanitized graph snapshots. Raw udev paths, serials,
// addresses, and ephemeral event numbers never enter its public state.

var SCHEMA_VERSION = 1
var MAX_SOURCE_ROWS = 16
var MAX_CAPABILITY_CHANGES = 32
var MAX_CAPABILITY_FIELDS = 24
var MIN_DEBOUNCE_MS = 80
var MAX_DEBOUNCE_MS = 1200

var SOURCES = ["libinput", "udev", "sysfs", "compositor", "edid", "physical-path", "seat", "dbus", "kernel", "upower", "pipewire", "user", "fixture", "backend"]
var ACTIONS = ["add", "change", "remove", "delete", "online", "offline", "connect", "disconnect", "attach", "detach", "update", "resume", "suspend", "lock", "unlock"]
var CATEGORIES = ["display", "touchscreen", "stylus", "tablet-pad", "keyboard", "mouse", "touchpad", "gamepad", "sensor", "dock", "battery", "audio"]

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
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function clamp(value, minimum, maximum, fallback) {
  var parsed = number(value, fallback)
  return Math.max(minimum, Math.min(maximum, parsed))
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function safeSource(value, fallback) {
  var name = token(value || fallback || "backend")
  if (name === "physicalpath") name = "physical-path"
  if (name === "input" || name === "hid" || name === "drm") name = name === "drm" ? "compositor" : "udev"
  if (name === "display" || name === "monitor" || name === "wayland") name = "compositor"
  if (name === "hyprland" || name === "hypr") name = "compositor"
  if (name === "bluez" || name === "power") name = name === "power" ? "upower" : "dbus"
  if (SOURCES.indexOf(name) >= 0) return name
  if (name.indexOf("libinput") >= 0) return "libinput"
  if (name.indexOf("udev") >= 0) return "udev"
  if (name.indexOf("compositor") >= 0 || name.indexOf("hypr") >= 0) return "compositor"
  if (name.indexOf("sysfs") >= 0) return "sysfs"
  if (name.indexOf("edid") >= 0) return "edid"
  if (name.indexOf("dbus") >= 0 || name.indexOf("bluez") >= 0) return "dbus"
  if (name.indexOf("upower") >= 0 || name.indexOf("battery") >= 0) return "upower"
  if (name.indexOf("pipewire") >= 0 || name.indexOf("pulse") >= 0) return "pipewire"
  if (name.indexOf("fixture") >= 0) return "fixture"
  if (name.indexOf("kernel") >= 0) return "kernel"
  return "backend"
}

function safeAction(value, fallback) {
  var name = token(value || fallback || "change")
  if (name === "connected") name = "connect"
  if (name === "disconnected") name = "disconnect"
  if (name === "removed") name = "remove"
  if (name === "added") name = "add"
  if (ACTIONS.indexOf(name) >= 0) return name
  return "change"
}

function safeCategory(value) {
  var name = token(value)
  if (name === "touch" || name === "touch-device" || name === "touch-screen") name = "touchscreen"
  if (name === "pen" || name === "tablet" || name === "tablet-tool") name = "stylus"
  if (name === "pad") name = "tablet-pad"
  return CATEGORIES.indexOf(name) >= 0 ? name : ""
}

function safeGraphId(value) {
  var id = string(value).trim()
  // DeviceGraph.js owns identity generation. This validator only allows its
  // opaque public forms; it is intentionally incompatible with raw paths.
  return /^(device|display):[a-z0-9-]+:[0-9a-f]{16}$/.test(id) ? id : ""
}

function safeType(event) {
  var source = object(event)
  var type = token(source.type || source.eventType || source.event_type || "")
  if (type === "device" || type === "hardware" || type === "topology") type += ".event"
  if (type === "power" || type === "battery") type += ".event"
  if (type === "capability" || type === "capabilities") type = "capability.change"
  if (["device.event", "topology.event", "hardware.event", "display.event", "power.event", "battery.event", "capability.change", "session.event"].indexOf(type) >= 0) return type
  if (source.device || source.subsystem === "input" || source.subsystem === "drm") return source.subsystem === "drm" ? "display.event" : "device.event"
  return ""
}

function eventCategory(event) {
  var source = object(event)
  var item = object(source.device)
  return safeCategory(source.category || source.deviceCategory || source.device_category || item.category || item.type || item.role)
}

function capabilityHint(event) {
  var source = object(event)
  var item = object(source.device)
  var raw = item.capabilities || item.capability || source.capabilities || source.capability
  var result = []
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length && result.length < MAX_CAPABILITY_FIELDS; i++) {
      var name = token(raw[i])
      if (name && result.indexOf(name) < 0) result.push(name)
    }
  } else {
    for (var key in object(raw)) {
      if (object(raw)[key] !== true && object(raw)[key] !== 1 && string(object(raw)[key]).toLowerCase() !== "true") continue
      var normalized = token(key)
      if (normalized && result.length < MAX_CAPABILITY_FIELDS && result.indexOf(normalized) < 0) result.push(normalized)
    }
  }
  return result.sort()
}

function normalizeEvent(event, now) {
  var source = object(event)
  var type = safeType(source)
  if (!type) return null
  var subsystem = token(source.subsystem || source.backend || source.provider || source.source || "")
  var action = safeAction(source.action || source.event || source.state, type === "capability.change" ? "update" : "change")
  var connected = null
  if (source.connected !== undefined) connected = source.connected === true
  else if (source.present !== undefined) connected = source.present !== false
  var at = Math.max(0, Math.floor(number(now, Date.now())))
  return {
    type: type,
    source: safeSource(source.source || source.sourceName || subsystem, type === "display.event" ? "compositor" : "backend"),
    action: action,
    category: eventCategory(source),
    connected: connected,
    capabilityHint: capabilityHint(source),
    at: at,
    display: type === "display.event" || subsystem === "drm"
  }
}

function debounceFor(event, options) {
  var settings = object(options)
  var candidate = number(settings.debounceMs, 240)
  var source = event && event.source
  if (source === "edid" || source === "compositor" || event && event.display) candidate = number(settings.displayDebounceMs, candidate)
  if (source === "libinput" || source === "kernel") candidate = number(settings.capabilityDebounceMs, candidate)
  if (event && (event.action === "remove" || event.action === "disconnect" || event.action === "detach")) candidate = Math.min(candidate, number(settings.disconnectDebounceMs, 180))
  return clamp(candidate, MIN_DEBOUNCE_MS, MAX_DEBOUNCE_MS, 240)
}

function copyState(state) {
  var source = object(state)
  var result = {}
  for (var key in source) result[key] = source[key]
  result.lastEvent = Object.assign({}, object(source.lastEvent))
  result.sources = Object.assign({}, object(source.sources))
  result.capabilityChanges = array(source.capabilityChanges).slice()
  result.current = Object.assign({}, object(source.current))
  return result
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: 0,
    phase: "idle",
    available: false,
    paused: false,
    stale: false,
    pendingRefresh: false,
    refreshDueAt: 0,
    pendingReason: "",
    eventCount: 0,
    coalescedEvents: 0,
    droppedEvents: 0,
    capabilityRevision: 0,
    capabilityChanges: [],
    lastEvent: { type: "", source: "", action: "", category: "", connected: null, at: 0 },
    sources: {},
    current: { nodeCount: 0, connectedCount: 0, outputCount: 0, categories: {} },
    reason: "no-topology-snapshot"
  }
}

function sourceRows(previous, event) {
  var result = Object.assign({}, object(previous))
  var source = event.source
  var old = object(result[source])
  result[source] = {
    events: Math.min(1000000, Number(old.events || 0) + 1),
    lastAt: event.at,
    available: true
  }
  var keys = Object.keys(result).sort()
  while (keys.length > MAX_SOURCE_ROWS) {
    var remove = keys.shift()
    delete result[remove]
  }
  return result
}

function noteEvent(previous, event, now, options) {
  var old = copyState(previous || emptyState())
  var observed = normalizeEvent(event, now)
  if (!observed) {
    old.droppedEvents = Math.min(1000000, Number(old.droppedEvents || 0) + 1)
    old.revision = Number(old.revision || 0) + 1
    return old
  }
  var wasPending = old.pendingRefresh === true
  var due = observed.at + debounceFor(observed, options)
  old.schemaVersion = SCHEMA_VERSION
  old.revision = Number(old.revision || 0) + 1
  old.available = true
  old.eventCount = Math.min(1000000, Number(old.eventCount || 0) + 1)
  old.coalescedEvents = Math.min(1000000, Number(old.coalescedEvents || 0) + (wasPending ? 1 : 0))
  old.pendingRefresh = true
  old.refreshDueAt = Math.max(Number(old.refreshDueAt || 0), due)
  old.pendingReason = observed.display ? "display-topology-event" : observed.source === "upower" || observed.type === "power.event" || observed.type === "battery.event" ? "power-state-event" : observed.action === "remove" || observed.action === "disconnect" || observed.action === "detach" ? "device-disconnected" : observed.type === "capability.change" ? "capability-change" : "device-topology-event"
  old.stale = true
  old.phase = old.paused ? "paused" : observed.action === "remove" || observed.action === "disconnect" || observed.action === "detach" ? "disconnecting" : observed.action === "add" || observed.action === "connect" || observed.action === "attach" ? "connecting" : "changing"
  old.lastEvent = observed
  old.sources = sourceRows(old.sources, observed)
  old.reason = old.pendingReason
  return old
}

function graphNodes(graph) {
  return array(object(graph).nodes)
}

function capabilitySet(node) {
  var source = object(node)
  var caps = object(source.capabilities)
  var result = {}
  for (var key in caps) {
    if (caps[key] === true) result[token(key)] = true
  }
  return result
}

function sortedCapabilityDifference(before, after) {
  var result = []
  var keys = {}
  for (var oldKey in before) keys[oldKey] = true
  for (var newKey in after) keys[newKey] = true
  var names = Object.keys(keys).sort()
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    if (!!before[name] !== !!after[name]) result.push(name)
  }
  return result.slice(0, MAX_CAPABILITY_FIELDS)
}

function capabilityDelta(previousGraph, nextGraph) {
  var before = {}
  var after = {}
  var oldNodes = graphNodes(previousGraph)
  var newNodes = graphNodes(nextGraph)
  for (var i = 0; i < oldNodes.length; i++) {
    var oldId = safeGraphId(oldNodes[i] && oldNodes[i].id)
    if (oldId) before[oldId] = oldNodes[i]
  }
  for (var j = 0; j < newNodes.length; j++) {
    var newId = safeGraphId(newNodes[j] && newNodes[j].id)
    if (newId) after[newId] = newNodes[j]
  }
  var ids = {}
  for (var oldNodeId in before) ids[oldNodeId] = true
  for (var newNodeId in after) ids[newNodeId] = true
  var changes = []
  var sortedIds = Object.keys(ids).sort()
  for (var k = 0; k < sortedIds.length && changes.length < MAX_CAPABILITY_CHANGES; k++) {
    var id = sortedIds[k]
    var oldNode = object(before[id])
    var newNode = object(after[id])
    var added = sortedCapabilityDifference(capabilitySet(oldNode), capabilitySet(newNode)).filter(function(name) { return !capabilitySet(oldNode)[name] })
    var removed = sortedCapabilityDifference(capabilitySet(oldNode), capabilitySet(newNode)).filter(function(name) { return !capabilitySet(newNode)[name] })
    var oldConnected = before[id] ? before[id].connected === true : null
    var newConnected = after[id] ? after[id].connected === true : null
    var category = safeCategory(newNode.category || oldNode.category)
    if (added.length === 0 && removed.length === 0 && oldConnected === newConnected) continue
    changes.push({
      deviceId: id,
      category: category,
      added: added,
      removed: removed,
      connectedBefore: oldConnected,
      connectedAfter: newConnected,
      kind: before[id] && after[id] ? "capability-change" : before[id] ? "device-removed" : "device-added"
    })
  }
  return { changed: changes.length > 0, changes: changes }
}

function graphSummary(graph) {
  var source = object(graph)
  var nodes = graphNodes(source)
  var outputs = array(source.outputs)
  var categories = {}
  var connected = 0
  for (var i = 0; i < nodes.length; i++) {
    var category = safeCategory(nodes[i] && nodes[i].category) || "unknown"
    categories[category] = Number(categories[category] || 0) + 1
    if (nodes[i] && nodes[i].connected === true) connected++
  }
  return { nodeCount: nodes.length, connectedCount: connected, outputCount: outputs.length, categories: categories }
}

function reconcile(previous, previousGraph, nextGraph, now, reason) {
  var old = copyState(previous || emptyState())
  var timestamp = Math.max(0, Math.floor(number(now, Date.now())))
  var delta = capabilityDelta(previousGraph, nextGraph)
  old.schemaVersion = SCHEMA_VERSION
  old.revision = Number(old.revision || 0) + 1
  old.available = graphSummary(nextGraph).nodeCount > 0 || graphSummary(nextGraph).outputCount > 0
  old.pendingRefresh = false
  old.refreshDueAt = 0
  old.pendingReason = ""
  old.stale = false
  old.paused = old.paused === true
  old.phase = old.paused ? "paused" : "stable"
  old.current = graphSummary(nextGraph)
  old.capabilityChanges = delta.changes
  if (delta.changed) old.capabilityRevision = Number(old.capabilityRevision || 0) + 1
  old.reason = string(reason || (delta.changed ? "capability-change-reconciled" : "snapshot-reconciled"))
  old.lastReconciledAt = timestamp
  if (old.available) old.sources = Object.assign({}, object(old.sources), { compositor: { events: Number(object(old.sources).compositor && object(old.sources).compositor.events || 0), lastAt: timestamp, available: true } })
  return old
}

function shouldRefresh(state, now) {
  var source = object(state)
  return source.pendingRefresh === true && source.paused !== true && number(now, Date.now()) >= Number(source.refreshDueAt || 0)
}

function lifecycle(previous, event, now, options) {
  var old = copyState(previous || emptyState())
  var source = object(event)
  var action = safeAction(source.action || source.event || source.state, "change")
  var type = safeType(source) || "session.event"
  var timestamp = Math.max(0, Math.floor(number(now, Date.now())))
  if (type !== "session.event" && ["suspend", "resume", "lock", "unlock"].indexOf(action) < 0) return old
  old.revision = Number(old.revision || 0) + 1
  old.lastEvent = { type: "session.event", source: "dbus", action: action, category: "", connected: null, at: timestamp, capabilityHint: [] }
  old.sources = sourceRows(old.sources, old.lastEvent)
  if (action === "suspend" || action === "lock") {
    old.paused = true
    old.phase = "paused"
    old.stale = true
    old.pendingRefresh = false
    old.refreshDueAt = 0
    old.pendingReason = "session-paused"
    old.reason = old.pendingReason
    return old
  }
  if (action === "resume" || action === "unlock") {
    old.paused = false
    old.phase = "resuming"
    old.stale = true
    old.pendingRefresh = true
    old.refreshDueAt = timestamp + debounceFor({ source: "dbus", action: "resume", type: "session.event", display: false }, options)
    old.pendingReason = "resume-topology-refresh"
    old.reason = old.pendingReason
  }
  return old
}

function summary(state) {
  var source = object(state)
  var last = object(source.lastEvent)
  return {
    schemaVersion: Number(source.schemaVersion || SCHEMA_VERSION),
    revision: Number(source.revision || 0),
    phase: string(source.phase || "idle"),
    available: source.available === true,
    paused: source.paused === true,
    stale: source.stale === true,
    pendingRefresh: source.pendingRefresh === true,
    refreshDueAt: Number(source.refreshDueAt || 0),
    pendingReason: string(source.pendingReason || ""),
    eventCount: Number(source.eventCount || 0),
    coalescedEvents: Number(source.coalescedEvents || 0),
    droppedEvents: Number(source.droppedEvents || 0),
    capabilityRevision: Number(source.capabilityRevision || 0),
    capabilityChanges: array(source.capabilityChanges).slice(0, MAX_CAPABILITY_CHANGES),
    lastEvent: {
      type: string(last.type || ""),
      source: safeSource(last.source, "backend"),
      action: safeAction(last.action, "change"),
      category: safeCategory(last.category),
      connected: last.connected === null || last.connected === undefined ? null : last.connected === true,
      at: Number(last.at || 0)
    },
    sources: Object.assign({}, object(source.sources)),
    current: Object.assign({}, object(source.current)),
    reason: string(source.reason || "")
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  SOURCES: SOURCES,
  ACTIONS: ACTIONS,
  emptyState: emptyState,
  normalizeEvent: normalizeEvent,
  noteEvent: noteEvent,
  capabilityDelta: capabilityDelta,
  reconcile: reconcile,
  shouldRefresh: shouldRefresh,
  lifecycle: lifecycle,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
