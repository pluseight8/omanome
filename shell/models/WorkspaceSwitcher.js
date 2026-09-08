// Transient workspace navigation state.  This model contains only the
// currently visible workspace metadata; it is never written to config or
// used as a screenshot/cache store.

var SCHEMA_VERSION = 1
var MAX_WORKSPACES = 32
var MAX_PREVIEW_WINDOWS = 4
var MAX_TEXT = 96

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {} }

function text(value, fallback, limit) {
  var result = String(value === undefined || value === null ? (fallback || "") : value).trim()
  return result.slice(0, Math.max(1, Number(limit || MAX_TEXT)))
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}

function workspaceId(value, fallback) {
  var source = object(value)
  var result = source.id !== undefined ? source.id : (source.name !== undefined ? source.name : value)
  if (result === undefined || result === null || result === "") result = fallback
  return text(result, String(fallback || "1"), 64)
}

function foreign(window) {
  var source = object(window)
  return source.wayland || source.foreign || source
}

function appId(window) {
  var source = foreign(window)
  return text(source.appId || source.app_id || source.desktopId || source.desktopFile || source.class || source.initialClass || "", "", 128).replace(/\.desktop$/, "")
}

function title(window) {
  var source = foreign(window)
  return text(source.title || source.name || appId(window) || "Window", "Window", MAX_TEXT)
}

function identity(window, index) {
  var source = foreign(window)
  var address = text(source.address, "", MAX_TEXT)
  if (/^[0-9a-fA-Fx]+$/.test(address)) return "address:" + address
  var pid = Math.round(number(source.pid, 0))
  if (pid > 0) return "pid:" + pid
  return appId(window) + "#" + String(Math.max(0, Number(index || 0)))
}

function windowList(workspace) {
  var source = object(workspace)
  if (source.toplevels && Array.isArray(source.toplevels.values)) return source.toplevels.values
  if (Array.isArray(source.windows)) return source.windows
  if (Array.isArray(source.clients)) return source.clients
  return []
}

function normalizeWorkspace(value, index) {
  var source = object(value)
  var id = workspaceId(value, index + 1)
  var sourceWindows = windowList(value)
  var windows = []
  for (var i = 0; i < sourceWindows.length && windows.length < MAX_PREVIEW_WINDOWS; i++) {
    if (!sourceWindows[i]) continue
    windows.push({ identity: identity(sourceWindows[i], i), appId: appId(sourceWindows[i]), title: title(sourceWindows[i]) })
  }
  var count = sourceWindows.length > 0 ? sourceWindows.length : Math.max(0, Math.round(number(source.toplevelCount !== undefined ? source.toplevelCount : source.windows, 0)))
  return {
    schemaVersion: SCHEMA_VERSION,
    id: id,
    name: text(source.name || source.description, "Workspace " + id, MAX_TEXT),
    occupied: count > 0 || source.occupied === true,
    windowCount: count,
    windows: windows
  }
}

function normalizeList(values, limit) {
  var source = Array.isArray(values) ? values : []
  var max = Math.max(1, Math.min(MAX_WORKSPACES, Math.floor(number(limit, MAX_WORKSPACES))))
  var result = []
  var seen = {}
  for (var i = 0; i < source.length && result.length < max; i++) {
    var item = normalizeWorkspace(source[i], i)
    if (!item.id || seen[item.id]) continue
    seen[item.id] = true
    result.push(item)
  }
  return result
}

function adjacentId(list, activeId, direction) {
  var values = Array.isArray(list) ? list : []
  if (values.length === 0) return ""
  var active = text(activeId, values[0].id, 64)
  var index = -1
  for (var i = 0; i < values.length; i++) if (String(values[i].id) === active) { index = i; break }
  if (index < 0) index = 0
  var step = String(direction || "next") === "previous" ? -1 : 1
  return String(values[Math.max(0, Math.min(values.length - 1, index + step))].id)
}

function cards(workspaces, options, context) {
  var settings = object(options)
  var state = object(context)
  var list = normalizeList(workspaces, settings.maxWorkspaces)
  var active = text(state.activeId || state.workspaceId, list.length > 0 ? list[0].id : "1", 64)
  if (list.length === 0) list = [normalizeWorkspace({ id: active, occupied: false }, 0)]
  var result = []
  for (var i = 0; i < list.length && result.length < Math.max(1, Math.min(MAX_WORKSPACES, Math.floor(number(settings.maxWorkspaces, MAX_WORKSPACES)))); i++) {
    var item = list[i]
    result.push({
      schemaVersion: SCHEMA_VERSION,
      id: item.id,
      label: item.name || "Workspace " + item.id,
      active: item.id === active,
      occupied: item.occupied === true,
      windowCount: item.windowCount,
      previewWindow: item.windows.length > 0 ? item.windows[0] : null,
      previewAvailable: state.livePreview === true,
      index: i
    })
  }
  return result
}

function emptyState() {
  return { schemaVersion: SCHEMA_VERSION, phase: "idle", activeId: "", targetId: "", direction: "", progress: 0, committed: false, reason: "idle" }
}

function begin(previous, activeId, direction, availableIds, now, options) {
  var settings = object(options)
  var list = normalizeList((Array.isArray(availableIds) ? availableIds : []).map(function(value) { return { id: value } }), settings.maxWorkspaces)
  var active = text(activeId, list.length > 0 ? list[0].id : "1", 64)
  var target = adjacentId(list, active, direction)
  return {
    schemaVersion: SCHEMA_VERSION,
    phase: target && target !== active ? "tracking" : "blocked",
    activeId: active,
    targetId: target,
    direction: String(direction || "next") === "previous" ? "previous" : "next",
    progress: 0,
    committed: false,
    startedAt: Math.max(0, Math.round(number(now, 0))),
    reason: target && target !== active ? "tracking" : "no-adjacent-workspace"
  }
}

function update(state, distance, width, now, options) {
  var source = object(state)
  if (source.phase !== "tracking") return source
  var settings = object(options)
  var viewport = Math.max(1, number(width, 1))
  var progress = Math.max(0, Math.min(1, Math.abs(number(distance, 0)) / viewport))
  var reduced = settings.reducedMotion === true
  return Object.assign({}, source, { progress: reduced ? (progress >= 0.5 ? 1 : 0) : progress, updatedAt: Math.max(0, Math.round(number(now, 0))) })
}

function end(state, distance, velocity, options, now) {
  var source = object(state)
  if (source.phase !== "tracking") return { state: Object.assign({}, source, { phase: "cancelled", reason: source.reason || "not-tracking" }), decision: { ok: false, action: "cancel", reason: source.reason || "not-tracking" } }
  var settings = object(options)
  var threshold = Math.max(1, number(settings.thresholdPx, 96))
  var speedThreshold = Math.max(0, number(settings.velocityThreshold, 0.35))
  var distanceValue = Math.abs(number(distance, 0))
  var speed = Math.abs(number(velocity, 0))
  var commit = distanceValue >= threshold || speed >= speedThreshold
  var next = Object.assign({}, source, { phase: commit ? "committed" : "cancelled", progress: commit ? 1 : 0, committed: commit, endedAt: Math.max(0, Math.round(number(now, 0))), reason: commit ? "threshold-reached" : "threshold-not-reached" })
  return {
    state: next,
    decision: commit
      ? { ok: true, action: "workspace-focus", workspaceId: source.targetId, direction: source.direction, reason: next.reason }
      : { ok: false, action: "cancel", workspaceId: source.targetId, direction: source.direction, reason: next.reason }
  }
}

function summary(state) {
  var source = object(state)
  return {
    schemaVersion: SCHEMA_VERSION,
    phase: String(source.phase || "idle"),
    activeId: text(source.activeId, "", 64),
    targetId: text(source.targetId, "", 64),
    direction: text(source.direction, "", 16),
    progress: Math.max(0, Math.min(1, number(source.progress, 0))),
    committed: source.committed === true,
    reason: text(source.reason, "idle", 64)
  }
}

var api = { SCHEMA_VERSION: SCHEMA_VERSION, MAX_WORKSPACES: MAX_WORKSPACES, MAX_PREVIEW_WINDOWS: MAX_PREVIEW_WINDOWS, normalizeWorkspace: normalizeWorkspace, normalizeList: normalizeList, cards: cards, emptyState: emptyState, begin: begin, update: update, end: end, summary: summary, adjacentId: adjacentId }
if (typeof module !== "undefined") module.exports = api
