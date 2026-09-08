// Persistent Omanome-managed layout metadata.  It deliberately stores
// application identities and layout intent only; compositor runtime objects
// are reconstructed from the current session when needed.

var SCHEMA_VERSION = 1
var MAX_SAVED = 32
var MAX_RECENT = 12
var MAX_SLOTS = 4
var MAX_TEXT = 128
var RATIOS = ["50/50", "40/60", "60/40", "33/67", "67/33"]
var KINDS = ["split-pair", "workspace-group", "app-pair", "layout"]
var WORKSPACE_POLICIES = ["active", "original", "ask"]
var MONITOR_POLICIES = ["active", "original", "ask", "per-app"]

function object(value) { return value && typeof value === "object" && !Array.isArray(value) ? value : {} }
function list(value) { return Array.isArray(value) ? value : [] }
function clone(value) { return JSON.parse(JSON.stringify(value)) }
function text(value, fallback, limit) { return String(value === undefined || value === null ? (fallback || "") : value).trim().slice(0, Math.max(1, Number(limit || MAX_TEXT))) }
function number(value, fallback) { var result = Number(value); return isFinite(result) ? result : Number(fallback || 0) }
function boundedTime(value) { return Math.max(0, Math.min(8640000000000, Math.round(number(value, 0)))) }

function appId(value) {
  var result = text(value, "", MAX_TEXT)
  if (result.slice(-8) === ".desktop") result = result.slice(0, -8)
  return result
}

function uniqueApps(values) {
  var result = []
  var seen = {}
  var source = list(values)
  for (var i = 0; i < source.length && result.length < MAX_SLOTS; i++) {
    var value = appId(source[i])
    if (!value || seen[value]) continue
    seen[value] = true
    result.push(value)
  }
  return result
}

function ratio(value) {
  var result = text(value, "50/50", 16).replace(/\s+/g, "")
  if (RATIOS.indexOf(result) >= 0) return result
  var numeric = number(value, 0.5)
  if (numeric >= 0.25 && numeric <= 0.75) {
    var first = Math.round(numeric * 100)
    var second = 100 - first
    var candidate = first + "/" + second
    if (RATIOS.indexOf(candidate) >= 0) return candidate
  }
  return "50/50"
}

function slot(value, index, fallbackApp) {
  var source = object(value)
  return {
    id: text(source.id, "slot-" + (index + 1), 64),
    appId: appId(source.appId || source.application || source.desktopId || fallbackApp),
    zoneId: text(source.zoneId || source.zone || source.layoutZone, "", 64),
    order: Math.max(0, Math.min(MAX_SLOTS - 1, Math.round(number(source.order, index))))
  }
}

function layout(value, apps) {
  var source = object(value)
  var applications = uniqueApps(apps)
  var sourceSlots = list(source.slots)
  var slots = []
  for (var i = 0; i < sourceSlots.length && slots.length < MAX_SLOTS; i++) {
    var item = slot(sourceSlots[i], i, applications[i] || "")
    if (!item.appId && applications[i]) item.appId = applications[i]
    if (item.appId) slots.push(item)
  }
  for (var appIndex = slots.length; appIndex < applications.length && slots.length < MAX_SLOTS; appIndex++)
    slots.push(slot({}, slots.length, applications[appIndex]))
  return {
    id: text(source.id || source.layoutId, "split", 64),
    type: text(source.type, "split", 32).toLowerCase(),
    orientation: ["auto", "landscape", "portrait"].indexOf(text(source.orientation, "auto", 16).toLowerCase()) >= 0 ? text(source.orientation, "auto", 16).toLowerCase() : "auto",
    ratio: ratio(source.ratio || source.ratioName),
    slots: slots
  }
}

function policy(value, values, fallback) {
  var result = text(value, fallback, 32).toLowerCase()
  return values.indexOf(result) >= 0 ? result : fallback
}

function fromGroup(group, context, index) {
  var source = object(group)
  var preferences = object(source.preferences)
  var sourceLayout = object(source.layout)
  var apps = uniqueApps(list(source.apps).concat(list(sourceLayout.slots).map(function(item) { return item && item.appId })))
  if (apps.length === 0) return null
  var resultLayout = layout(sourceLayout, apps)
  return normalizeRecord({
    id: source.id,
    kind: source.type || "layout",
    name: source.name,
    apps: apps,
    layout: resultLayout,
    workspacePolicy: preferences.workspacePolicy,
    monitorPolicy: preferences.monitorPolicy,
    targetWorkspace: preferences.targetWorkspace,
    originalMonitor: preferences.originalMonitor,
    lastUsedAt: object(context).now,
    order: source.order === undefined ? index : source.order
  }, index)
}

function normalizeRecord(value, index) {
  var source = object(value)
  var sourceLayout = object(source.layout)
  var apps = uniqueApps(list(source.apps).concat(list(source.appIds)).concat(list(sourceLayout.slots).map(function(item) { return item && item.appId })))
  var normalizedLayout = layout(sourceLayout, apps)
  apps = uniqueApps(apps.concat(normalizedLayout.slots.map(function(item) { return item.appId })))
  if (apps.length === 0) return null
  var kind = text(source.kind || source.type, "layout", 32).toLowerCase()
  if (KINDS.indexOf(kind) < 0) kind = "layout"
  var id = text(source.id, "layout-" + (Number(index || 0) + 1), 96)
  var name = text(source.name, apps.join(" + "), MAX_TEXT)
  return {
    schemaVersion: SCHEMA_VERSION,
    id: id,
    kind: kind,
    name: name,
    apps: apps,
    layout: normalizedLayout,
    workspacePolicy: policy(source.workspacePolicy || source.workspace, WORKSPACE_POLICIES, "active"),
    monitorPolicy: policy(source.monitorPolicy || source.monitor, MONITOR_POLICIES, "active"),
    targetWorkspace: text(source.targetWorkspace || source.workspaceId, "", 64),
    originalMonitor: text(source.originalMonitor || source.monitorName, "", MAX_TEXT),
    lastUsedAt: boundedTime(source.lastUsedAt || source.updatedAt),
    order: Math.max(0, Math.min(MAX_SAVED - 1, Math.round(number(source.order, index || 0))))
  }
}

function normalizeRecords(values, limit) {
  var result = []
  var seen = {}
  var source = list(values)
  var maximum = Math.max(0, Number(limit === undefined || limit === null ? MAX_SAVED : limit))
  for (var i = 0; i < source.length && result.length < maximum; i++) {
    var item = normalizeRecord(source[i], i)
    if (!item || seen[item.id]) continue
    seen[item.id] = true
    result.push(item)
  }
  return result
}

function emptyState() {
  return { schemaVersion: SCHEMA_VERSION, enabled: true, recentEnabled: true, maxRecent: MAX_RECENT, maxSaved: MAX_SAVED, saved: [], recent: [] }
}

function restore(raw) {
  var parsed = raw
  if (typeof raw === "string") {
    try { parsed = JSON.parse(raw) } catch (error) { return { ok: false, reason: "invalid-json", state: emptyState() } }
  }
  if (!object(parsed)) return { ok: false, reason: "invalid-root", state: emptyState() }
  var version = Number(parsed.schemaVersion === undefined ? SCHEMA_VERSION : parsed.schemaVersion)
  if (!isFinite(version) || version < 1 || version > SCHEMA_VERSION)
    return { ok: false, reason: version > SCHEMA_VERSION ? "future-schema" : "invalid-schema-version", state: emptyState() }
  var state = {
    schemaVersion: SCHEMA_VERSION,
    enabled: parsed.enabled !== false,
    recentEnabled: parsed.recentEnabled !== false,
    maxRecent: Math.max(0, Math.min(MAX_RECENT, Math.floor(number(parsed.maxRecent, MAX_RECENT)))),
    maxSaved: Math.max(0, Math.min(MAX_SAVED, Math.floor(number(parsed.maxSaved, MAX_SAVED)))),
    saved: [],
    recent: []
  }
  state.saved = normalizeRecords(parsed.saved, state.maxSaved)
  state.recent = normalizeRecords(parsed.recent, state.maxRecent)
  return { ok: true, schemaVersion: SCHEMA_VERSION, state: state, discarded: Math.max(0, list(parsed.saved).length - state.saved.length) }
}

function persistable(state) {
  var restored = restore(state)
  var source = restored.state
  return {
    schemaVersion: SCHEMA_VERSION,
    enabled: source.enabled !== false,
    recentEnabled: source.recentEnabled !== false,
    maxRecent: source.maxRecent,
    maxSaved: source.maxSaved,
    saved: normalizeRecords(source.saved, source.maxSaved),
    recent: normalizeRecords(source.recent, source.maxRecent)
  }
}

function signature(value) {
  var item = normalizeRecord(value, 0)
  if (!item) return ""
  return JSON.stringify({ apps: item.apps, layout: item.layout, workspacePolicy: item.workspacePolicy, monitorPolicy: item.monitorPolicy, targetWorkspace: item.targetWorkspace, originalMonitor: item.originalMonitor })
}

function replaceBySignature(values, item, limit) {
  var result = []
  var wanted = signature(item)
  var source = list(values)
  for (var i = 0; i < source.length; i++) if (signature(source[i]) !== wanted) result.push(source[i])
  result.unshift(item)
  return normalizeRecords(result, limit)
}

function rememberRecent(state, group, context) {
  var restored = restore(state).state
  if (restored.enabled === false || restored.recentEnabled === false) return restored
  var record = fromGroup(group, { now: object(context).now || Date.now() }, restored.recent.length)
  if (!record) return restored
  restored.recent = replaceBySignature(restored.recent, record, restored.maxRecent)
  return restored
}

function save(state, group, context) {
  var restored = restore(state).state
  if (restored.enabled === false) return restored
  var record = fromGroup(group, { now: object(context).now || Date.now() }, restored.saved.length)
  if (!record) return restored
  restored.saved = replaceBySignature(restored.saved, record, restored.maxSaved)
  restored.recent = replaceBySignature(restored.recent, record, restored.maxRecent)
  return restored
}

function remove(state, id) {
  var restored = restore(state).state
  var key = text(id, "", 96)
  restored.saved = restored.saved.filter(function(item) { return item.id !== key })
  return restored
}

function summary(state) {
  var source = restore(state).state
  function row(item) {
    return { id: item.id, kind: item.kind, apps: item.apps.slice(0, MAX_SLOTS), ratio: item.layout.ratio, orientation: item.layout.orientation, workspacePolicy: item.workspacePolicy, monitorPolicy: item.monitorPolicy }
  }
  return {
    enabled: source.enabled === true,
    recentEnabled: source.recentEnabled === true,
    savedCount: source.saved.length,
    recentCount: source.recent.length,
    saved: source.saved.slice(0, MAX_SAVED).map(row),
    recent: source.recent.slice(0, MAX_RECENT).map(row)
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_SAVED: MAX_SAVED,
  MAX_RECENT: MAX_RECENT,
  MAX_SLOTS: MAX_SLOTS,
  emptyState: emptyState,
  restore: restore,
  persistable: persistable,
  fromGroup: fromGroup,
  normalizeRecord: normalizeRecord,
  signature: signature,
  rememberRecent: rememberRecent,
  save: save,
  remove: remove,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
