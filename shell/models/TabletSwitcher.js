// Bounded, touch-first window switcher data.  Cards are a transient view of
// the compositor's current foreign-toplevel objects; no card state is saved.

var SCHEMA_VERSION = 1
var MAX_CARDS = 32
var MAX_TEXT = 128

function object(value) { return value && typeof value === "object" ? value : {} }
function list(value) { return Array.isArray(value) ? value : [] }
function text(value, fallback, limit) {
  return String(value === undefined || value === null ? (fallback || "") : value).trim().slice(0, Math.max(1, Number(limit || MAX_TEXT)))
}
function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}
function clamp(value, minimum, maximum) { return Math.max(Number(minimum), Math.min(Number(maximum), Number(value))) }

function foreign(window) {
  var item = object(window)
  return item.wayland || item.foreign || item
}

function appId(window) {
  var item = foreign(window)
  var value = item.appId || item.app_id || item.desktopId || item.desktopFile || item.class || item.initialClass || window && window.appId
  return text(value, "unknown", MAX_TEXT).replace(/\.desktop$/, "")
}

function caption(window) {
  var item = foreign(window)
  return text(item.title || window && window.title, appId(window), MAX_TEXT)
}

function identity(window) {
  var item = foreign(window)
  var address = text(item.address || window && window.address, "", MAX_TEXT)
  if (address.indexOf("address:") === 0) return address
  if (/^[0-9a-fA-Fx]+$/.test(address)) return "address:" + address
  var pid = Math.round(number(item.pid || window && window.pid, 0))
  return pid > 0 ? "pid:" + pid : ""
}

function workspaceId(window) {
  var item = foreign(window)
  var workspace = item.workspace || window && window.workspace
  if (workspace && typeof workspace === "object") workspace = workspace.id !== undefined ? workspace.id : workspace.name
  if (workspace === undefined || workspace === null || workspace === "") workspace = item.workspaceId || window && window.workspaceId
  return text(workspace, "", 64)
}

function monitorName(window) {
  var item = foreign(window)
  var monitor = item.monitorName || item.monitor || item.output || window && window.monitorName
  if (monitor && typeof monitor === "object") monitor = monitor.name || monitor.id
  return text(monitor, "", MAX_TEXT)
}

function minimized(window) { return foreign(window).minimized === true }

function normalize(config) {
  var source = object(config)
  var scope = ["current-workspace", "all-workspaces", "current-monitor"].indexOf(String(source.scope || "current-workspace")) >= 0
    ? String(source.scope || "current-workspace") : "current-workspace"
  return {
    enabled: source.enabled !== false,
    mode: ["automatic", "always", "never"].indexOf(String(source.mode || "automatic")) >= 0 ? String(source.mode || "automatic") : "automatic",
    scope: scope,
    maxCards: Math.max(1, Math.min(MAX_CARDS, Math.floor(number(source.maxCards, MAX_CARDS)))),
    closeOnSwipe: source.closeOnSwipe === true,
    touchSwipe: source.touchSwipe !== false,
    swipeThresholdPx: clamp(number(source.swipeThresholdPx, 96), 48, 320),
    swipeVelocity: clamp(number(source.swipeVelocity, 0.5), 0.1, 2.0),
    closeThresholdPx: clamp(number(source.closeThresholdPx, 120), 64, 360),
    selectedScale: clamp(number(source.selectedScale, 1.0), 1.0, 1.12),
    sideScale: clamp(number(source.sideScale, 0.92), 0.72, 1.0),
    sideOpacity: clamp(number(source.sideOpacity, 0.76), 0.2, 1.0)
  }
}

function cardKey(window, index) {
  var id = identity(window)
  if (id) return id
  return appId(window) + "\u0000" + Math.max(0, Number(index || 0))
}

function normalizeCard(window, index, context) {
  var item = foreign(window)
  var state = object(context)
  var id = identity(window)
  return {
    schemaVersion: SCHEMA_VERSION,
    key: cardKey(window, index),
    identity: id,
    appId: appId(window),
    caption: caption(window),
    workspaceId: workspaceId(window),
    monitorName: monitorName(window),
    minimized: minimized(window),
    focused: item.focused === true || state.activeIdentity === id,
    icon: text(item.icon || window && window.icon, "application-x-executable", MAX_TEXT),
    window: window
  }
}

function selectable(windows, config, context) {
  var options = normalize(config)
  var state = object(context)
  var values = list(windows)
  var result = []
  for (var i = 0; i < values.length && result.length < options.maxCards; i++) {
    var window = values[i]
    if (!window || minimized(window)) continue
    var workspace = workspaceId(window)
    var monitor = monitorName(window)
    if (options.scope === "current-workspace" && state.workspaceId !== undefined && String(workspace) !== String(state.workspaceId)) continue
    if (options.scope === "current-monitor" && state.monitorName && monitor !== String(state.monitorName)) continue
    result.push(normalizeCard(window, i, state))
  }
  return result
}

function windowOf(card) { return card && card.window ? card.window : card }

function emptyState() {
  return { schemaVersion: SCHEMA_VERSION, phase: "idle", index: 0, dx: 0, dy: 0, progress: 0, direction: "", reason: "idle" }
}

function begin(state, index, point, config, now) {
  var options = normalize(config)
  var location = object(point)
  var enabled = options.touchSwipe === true
  return {
    schemaVersion: SCHEMA_VERSION,
    phase: enabled ? "tracking" : "blocked",
    index: Math.max(0, Math.floor(number(index, 0))),
    startX: number(location.x, 0),
    startY: number(location.y, 0),
    x: number(location.x, 0),
    y: number(location.y, 0),
    dx: 0,
    dy: 0,
    progress: 0,
    direction: "",
    startedAt: Math.max(0, Math.round(number(now, Date.now()))),
    reason: enabled ? "tracking" : "touch-swipe-disabled",
    previous: null
  }
}

function update(state, point, config, now) {
  var source = object(state)
  if (source.phase !== "tracking") return source
  var options = normalize(config)
  var location = object(point)
  var dx = number(location.x, source.startX) - source.startX
  var dy = number(location.y, source.startY) - source.startY
  var horizontal = Math.abs(dx) >= Math.abs(dy)
  var distance = horizontal ? Math.abs(dx) : Math.abs(dy)
  var threshold = horizontal ? options.swipeThresholdPx : options.closeThresholdPx
  return Object.assign({}, source, {
    x: number(location.x, source.x),
    y: number(location.y, source.y),
    dx: dx,
    dy: dy,
    progress: clamp(distance / Math.max(1, threshold), 0, 1),
    direction: horizontal ? (dx < 0 ? "left" : "right") : (dy < 0 ? "up" : "down"),
    updatedAt: Math.max(0, Math.round(number(now, Date.now())))
  })
}

function decideSwipe(dx, dy, velocity, config) {
  var options = normalize(config)
  var horizontal = Math.abs(Number(dx || 0)) >= Math.abs(Number(dy || 0))
  var distance = horizontal ? Math.abs(Number(dx || 0)) : Math.abs(Number(dy || 0))
  var speed = Math.abs(number(velocity, 0))
  if (!horizontal && Number(dy || 0) < 0 && options.closeOnSwipe && (distance >= options.closeThresholdPx || speed >= options.swipeVelocity))
    return { ok: true, action: "close", delta: 0, direction: "up", progress: clamp(distance / options.closeThresholdPx, 0, 1) }
  if (horizontal && options.touchSwipe && (distance >= options.swipeThresholdPx || speed >= options.swipeVelocity)) {
    var direction = Number(dx || 0) < 0 ? "left" : "right"
    return { ok: true, action: "select", delta: direction === "left" ? 1 : -1, direction: direction, progress: clamp(distance / options.swipeThresholdPx, 0, 1) }
  }
  return { ok: false, action: "cancel", delta: 0, direction: horizontal ? "" : (Number(dy || 0) < 0 ? "up" : "down"), progress: clamp(distance / Math.max(1, horizontal ? options.swipeThresholdPx : options.closeThresholdPx), 0, 1), reason: "swipe-threshold-not-reached" }
}

function end(state, point, velocity, config, now) {
  var source = object(state)
  if (source.phase !== "tracking") return { state: source, decision: { ok: false, action: "cancel", reason: "swipe-not-active" } }
  var updated = update(source, point, config, now)
  var decision = decideSwipe(updated.dx, updated.dy, velocity, config)
  var next = Object.assign({}, updated, { phase: decision.ok ? "committed" : "cancelled", reason: decision.reason || decision.action, action: decision.action })
  return { state: next, decision: decision }
}

function visual(index, selectedIndex, count, config) {
  var options = normalize(config)
  var distance = Number(index) - Number(selectedIndex)
  var visible = Math.abs(distance) <= 2
  return {
    distance: distance,
    selected: distance === 0,
    visible: visible,
    scale: distance === 0 ? options.selectedScale : options.sideScale,
    opacity: distance === 0 ? 1.0 : (visible ? options.sideOpacity : 0),
    rotation: 0,
    z: 100 - Math.abs(distance)
  }
}

function moveIndex(index, delta, count) {
  var size = Math.max(0, Math.floor(Number(count || 0)))
  if (size === 0) return 0
  return (Math.floor(Number(index || 0)) + Math.floor(Number(delta || 0)) + size) % size
}

function summary(state) {
  var source = object(state)
  return {
    phase: text(source.phase, "idle", 32),
    index: Math.max(0, Math.min(MAX_CARDS - 1, Math.floor(number(source.index, 0)))),
    direction: text(source.direction, "", 16),
    progress: clamp(number(source.progress, 0), 0, 1),
    reason: text(source.reason, "idle", 64),
    action: text(source.action, "", 16)
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_CARDS: MAX_CARDS,
  normalize: normalize,
  foreign: foreign,
  appId: appId,
  identity: identity,
  selectable: selectable,
  normalizeCard: normalizeCard,
  windowOf: windowOf,
  emptyState: emptyState,
  begin: begin,
  update: update,
  decideSwipe: decideSwipe,
  end: end,
  visual: visual,
  moveIndex: moveIndex,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
