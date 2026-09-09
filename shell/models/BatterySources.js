// Privacy-safe battery and power-source inventory.
//
// UPower may expose more than one battery (for example a tablet and an
// attached accessory).  This model keeps those sources separate while making
// identity opaque.  It never creates a row for a missing source and never
// exposes UPower object paths, serials, addresses, or kernel node names.

var SCHEMA_VERSION = 1
var MAX_SOURCES = 16
var MAX_LABEL_LENGTH = 96
var MAX_EVENT_COUNT = 1000000
var BATTERY_STATES = ["charging", "discharging", "fully-charged", "pending-charge", "unknown"]
var BATTERY_ROLES = ["system", "peripheral", "ups", "unknown"]

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

function bool(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback === undefined ? false : fallback
  var name = string(value).toLowerCase()
  return value === true || value === 1 || name === "true" || name === "yes" || name === "1"
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function allowed(value, values, fallback) {
  var name = token(value)
  return values.indexOf(name) >= 0 ? name : fallback
}

function clamp(value, minimum, maximum, fallback) {
  return Math.max(minimum, Math.min(maximum, number(value, fallback)))
}

function safeText(value, fallback) {
  var result = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!result || result.length > MAX_LABEL_LENGTH || /[\\/\n\r]/.test(result)) return fallback
  if (/\/dev\/|\/sys\/|\/org\/freedesktop\/UPower\/|\bevent[0-9]+\b/i.test(result)) return fallback
  if (/(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i.test(result)) return fallback
  return result
}

// FNV-1a is used only to make a stable opaque public key.  It is not a
// security primitive and the source material never leaves this module.
function opaquePart(value) {
  var source = string(value)
  var first = 2166136261
  var second = 2166136261 ^ 0x9e3779b9
  for (var i = 0; i < source.length; i++) {
    var code = source.charCodeAt(i)
    first ^= code
    first = Math.imul(first, 16777619)
    second ^= code + ((i + 1) * 17)
    second = Math.imul(second, 16777619)
  }
  return ("00000000" + (first >>> 0).toString(16)).slice(-8) + ("00000000" + (second >>> 0).toString(16)).slice(-8)
}

function first(source, names) {
  var item = object(source)
  for (var i = 0; i < names.length; i++) {
    var value = string(item[names[i]]).trim()
    if (value) return value
  }
  return ""
}

function numericField(source, names, fallback) {
  var item = object(source)
  for (var i = 0; i < names.length; i++) {
    if (item[names[i]] === undefined || item[names[i]] === null || item[names[i]] === "") continue
    var raw = string(item[names[i]]).replace(/%/g, "").trim()
    var result = Number(raw)
    if (isFinite(result)) return result
  }
  return fallback
}

function percent(source) {
  var result = numericField(source, ["percent", "percentage", "batteryPercent", "battery_percentage"], -1)
  return result < 0 || result > 100 ? -1 : Math.round(result * 10) / 10
}

function state(source) {
  var name = token(first(source, ["state", "batteryState", "battery_state"]))
  if (name === "fully-charged") return "fully-charged"
  if (name === "fullycharged" || name === "full") return "fully-charged"
  if (name === "pending-charge" || name === "pendingcharge") return "pending-charge"
  return BATTERY_STATES.indexOf(name) >= 0 ? name : "unknown"
}

function role(source) {
  var item = object(source)
  var name = token(first(item, ["role", "batteryRole", "battery_role", "kind", "type", "deviceType", "device_type"]))
  if (name === "battery") name = "system"
  if (name === "line-power" || name === "linepower" || name === "power-supply") name = "peripheral"
  if (name === "uninterruptible-power-supply" || name === "uninterruptible-power" || name === "ups") name = "ups"
  if (name === "keyboard" || name === "tablet" || name === "base") name = "peripheral"
  return BATTERY_ROLES.indexOf(name) >= 0 ? name : "unknown"
}

function sourceName(source) {
  return "upower"
}

function identityMaterial(source, sourceRole, index) {
  var item = object(source)
  var path = first(item, ["nativePath", "native_path", "objectPath", "object_path", "path", "upowerPath", "upower_path"])
  var explicit = first(item, ["stableId", "stable_id", "deviceId", "device_id", "id", "identifier"])
  var model = first(item, ["model", "modelName", "model_name", "vendor", "type", "kind"])
  var label = first(item, ["label", "name", "displayName", "display_name"])
  return (path ? "path|" + path : explicit ? "id|" + explicit : "fallback|" + model + "|" + label + "|" + sourceRole + "|" + index)
}

function sourceId(source, sourceRole, index) {
  return "device:battery:" + opaquePart(identityMaterial(source, sourceRole, index))
}

function actualSource(source) {
  var item = object(source)
  if (Object.keys(item).length === 0) return false
  if (item.present === false || item.exists === false || item.removed === true) return false
  if (item.available === false && item.present === undefined && item.exists === undefined) return false
  var type = token(first(item, ["type", "deviceType", "device_type", "kind"]))
  var hasKnownType = ["battery", "ups", "power-source", "power-supply"].indexOf(type) >= 0
  var hasPath = !!first(item, ["nativePath", "native_path", "objectPath", "object_path", "path", "upowerPath", "upower_path"])
  var hasModel = !!first(item, ["model", "modelName", "model_name", "name"])
  return percent(item) >= 0 || state(item) !== "unknown" || hasKnownType || hasModel || (hasPath && token(first(item, ["source", "backend", "provider"])) === "upower")
}

function normalize(raw, index) {
  var source = object(raw)
  var position = Math.max(0, Math.floor(number(index, 0)))
  if (!actualSource(source)) return null
  var sourceRole = role(source)
  var sourceType = token(first(source, ["type", "deviceType", "device_type", "kind"]))
  if (["battery", "ups", "power-source", "power-supply"].indexOf(sourceType) < 0) sourceType = sourceRole === "ups" ? "ups" : "battery"
  var fallbackLabel = sourceRole === "system" ? "System battery" : sourceRole === "peripheral" ? "Attached battery" : sourceRole === "ups" ? "UPS battery" : "Battery " + String(position + 1)
  var label = safeText(first(source, ["label", "displayName", "display_name", "model", "name"]), fallbackLabel)
  var sourcePercent = percent(source)
  var sourceState = state(source)
  var connected = source.connected !== undefined ? bool(source.connected, true) : source.online !== undefined ? bool(source.online, true) : true
  var result = {
    schemaVersion: SCHEMA_VERSION,
    id: sourceId(source, sourceRole, position),
    label: label,
    role: sourceRole,
    kind: sourceType,
    source: sourceName(source),
    percent: sourcePercent,
    state: sourceState,
    connected: connected,
    confidence: allowed(source.confidence, ["confirmed", "probable", "unknown"], "confirmed")
  }
  if (source.powerSupply !== undefined || source.power_supply !== undefined) result.powerSupply = bool(source.powerSupply !== undefined ? source.powerSupply : source.power_supply, false)
  if (source.onAc !== undefined || source.on_ac !== undefined) result.onAc = bool(source.onAc !== undefined ? source.onAc : source.on_ac, false)
  if (source.energy !== undefined || source.energyWh !== undefined || source.energy_wh !== undefined) result.energyWh = clamp(source.energy !== undefined ? source.energy : source.energyWh !== undefined ? source.energyWh : source.energy_wh, 0, 1000000000, 0)
  if (source.energyFull !== undefined || source.energyFullWh !== undefined || source.energy_full_wh !== undefined) result.energyFullWh = clamp(source.energyFull !== undefined ? source.energyFull : source.energyFullWh !== undefined ? source.energyFullWh : source.energy_full_wh, 0, 1000000000, 0)
  if (source.power !== undefined || source.powerWatts !== undefined || source.power_watts !== undefined) result.powerWatts = clamp(source.power !== undefined ? source.power : source.powerWatts !== undefined ? source.powerWatts : source.power_watts, -1000000000, 1000000000, 0)
  return result
}

function rowsFrom(value) {
  if (Array.isArray(value)) return value
  var source = object(value)
  var rows = source.batterySources
  if (rows === undefined) rows = source.battery_sources
  if (rows === undefined) rows = source.batteries
  if (rows === undefined) rows = source.powerSources
  if (rows === undefined) rows = source.power_sources
  if (Array.isArray(rows)) return rows
  if (rows && typeof rows === "object") {
    var result = []
    for (var key in rows) result.push(rows[key])
    return result
  }
  return []
}

function sourceRows(value) {
  if (Array.isArray(value)) return value
  return array(object(value).sources)
}

function primary(value) {
  var rows = sourceRows(value)
  for (var i = 0; i < rows.length; i++) if (rows[i] && rows[i].role === "system") return rows[i]
  for (var j = 0; j < rows.length; j++) if (rows[j] && rows[j].connected !== false) return rows[j]
  return rows.length > 0 ? rows[0] : null
}

function aggregate(rows) {
  var list = sourceRows(rows)
  var main = primary(list)
  var states = {}
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].state) states[list[i].state] = true
  return {
    available: !!main,
    id: main ? String(main.id || "") : "",
    role: main ? allowed(main.role, BATTERY_ROLES, "unknown") : "unknown",
    percent: main ? number(main.percent, -1) : -1,
    state: main ? allowed(main.state, BATTERY_STATES, "unknown") : "unknown",
    sourceCount: list.length,
    mixedState: Object.keys(states).length > 1
  }
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    available: false,
    backend: "unavailable",
    sources: [],
    aggregate: aggregate([]),
    revision: 0,
    eventCount: 0,
    coalescedEvents: 0,
    pendingRefresh: false,
    lastEvent: { type: "", source: "", action: "", at: 0 },
    reason: "no-battery-sources",
    privacy: { rawPathsEmitted: false, serialsEmitted: false, addressesEmitted: false }
  }
}

function fromSnapshot(value, previous) {
  var old = object(previous)
  var rows = rowsFrom(value)
  var sources = []
  var seen = {}
  for (var i = 0; i < rows.length && sources.length < MAX_SOURCES; i++) {
    var normalized = normalize(rows[i], i)
    if (!normalized || seen[normalized.id]) continue
    seen[normalized.id] = true
    sources.push(normalized)
  }
  var result = emptyState()
  result.sources = sources
  result.available = sources.length > 0
  result.backend = sources.length > 0 ? "upower" : "unavailable"
  result.aggregate = aggregate(sources)
  result.revision = Math.max(0, Math.floor(number(old.revision, 0))) + 1
  result.eventCount = Math.max(0, Math.floor(number(old.eventCount, 0)))
  result.coalescedEvents = Math.max(0, Math.floor(number(old.coalescedEvents, 0)))
  result.lastEvent = Object.assign({}, emptyState().lastEvent, object(old.lastEvent))
  result.reason = sources.length > 0 ? "upower-snapshot" : "no-battery-sources"
  return result
}

function safeAction(value) {
  var name = token(value || "change")
  if (["add", "change", "remove", "delete", "online", "offline", "connect", "disconnect", "update"].indexOf(name) < 0) return "change"
  return name
}

function applyEvent(previous, event) {
  var old = Object.assign(emptyState(), object(previous))
  old.sources = sourceRows(previous).slice(0, MAX_SOURCES)
  old.aggregate = aggregate(old.sources)
  var source = object(event)
  var type = token(source.type || source.eventType || source.event_type)
  if (["power.event", "battery.event", "power-change", "battery-change"].indexOf(type) < 0) {
    old.revision = Math.max(0, Math.floor(number(old.revision, 0))) + 1
    old.reason = "ignored-power-event"
    return old
  }
  var wasPending = old.pendingRefresh === true
  old.schemaVersion = SCHEMA_VERSION
  old.revision = Math.max(0, Math.floor(number(old.revision, 0))) + 1
  old.eventCount = Math.min(MAX_EVENT_COUNT, Math.max(0, Math.floor(number(old.eventCount, 0))) + 1)
  old.coalescedEvents = Math.min(MAX_EVENT_COUNT, Math.max(0, Math.floor(number(old.coalescedEvents, 0))) + (wasPending ? 1 : 0))
  old.pendingRefresh = true
  old.lastEvent = { type: "power.event", source: "upower", action: safeAction(source.action || source.event || source.state), at: Math.max(0, Math.floor(number(source.at, Date.now()))) }
  old.reason = "upower-event-awaiting-snapshot"
  return old
}

function safeSourceSummary(value) {
  var source = object(value)
  var result = {
    id: /^device:battery:[0-9a-f]{16}$/.test(string(source.id)) ? source.id : "",
    label: safeText(source.label, "Battery"),
    role: allowed(source.role, BATTERY_ROLES, "unknown"),
    kind: ["battery", "ups", "power-source", "power-supply"].indexOf(token(source.kind)) >= 0 ? token(source.kind) : "battery",
    source: "upower",
    percent: number(source.percent, -1),
    state: allowed(source.state, BATTERY_STATES, "unknown"),
    connected: source.connected !== false,
    confidence: allowed(source.confidence, ["confirmed", "probable", "unknown"], "unknown")
  }
  if (result.percent < 0 || result.percent > 100) result.percent = -1
  if (source.powerSupply !== undefined) result.powerSupply = source.powerSupply === true
  if (source.onAc !== undefined) result.onAc = source.onAc === true
  return result
}

function summary(value) {
  var source = object(value)
  var rows = sourceRows(source).slice(0, MAX_SOURCES).map(safeSourceSummary).filter(function(row) { return row.id !== "" })
  var main = primary(rows)
  return {
    schemaVersion: SCHEMA_VERSION,
    available: rows.length > 0,
    backend: rows.length > 0 ? "upower" : "unavailable",
    sourceCount: rows.length,
    sources: rows,
    aggregate: aggregate(rows),
    revision: Math.max(0, Math.floor(number(source.revision, 0))),
    eventCount: Math.min(MAX_EVENT_COUNT, Math.max(0, Math.floor(number(source.eventCount, 0)))),
    coalescedEvents: Math.min(MAX_EVENT_COUNT, Math.max(0, Math.floor(number(source.coalescedEvents, 0)))),
    pendingRefresh: source.pendingRefresh === true,
    lastEvent: { type: string(source.lastEvent && source.lastEvent.type || ""), source: string(source.lastEvent && source.lastEvent.source || ""), action: safeAction(source.lastEvent && source.lastEvent.action), at: Math.max(0, Math.floor(number(source.lastEvent && source.lastEvent.at, 0))) },
    reason: string(source.reason || (main ? "upower-snapshot" : "no-battery-sources")),
    privacy: { rawPathsEmitted: false, serialsEmitted: false, addressesEmitted: false }
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_SOURCES: MAX_SOURCES,
  BATTERY_STATES: BATTERY_STATES,
  BATTERY_ROLES: BATTERY_ROLES,
  normalize: normalize,
  fromSnapshot: fromSnapshot,
  primary: primary,
  aggregate: aggregate,
  applyEvent: applyEvent,
  emptyState: emptyState,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
