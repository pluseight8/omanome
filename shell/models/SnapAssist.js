// Snap Assist state is intentionally pure data.  Pointer/touch motion updates
// this model locally; only commit() should be connected to a compositor
// operation.  No window screenshot or subprocess is involved in preview.

var Layout = typeof require === "function" ? require("./LayoutEngine.js") : null

function engine() {
  if (Layout) return Layout
  return typeof LayoutEngine !== "undefined" ? LayoutEngine : {}
}

function text(value) { return String(value === undefined || value === null ? "" : value).trim().toLowerCase() }
function number(value, fallback) { var result = Number(value); return isFinite(result) ? result : Number(fallback || 0) }
function clone(value) { return JSON.parse(JSON.stringify(value)) }

function point(value) {
  var item = value && typeof value === "object" ? value : {}
  return { x: number(item.x, 0), y: number(item.y, 0) }
}

function distance(start, end) {
  var a = point(start)
  var b = point(end)
  return Math.sqrt(Math.pow(b.x - a.x, 2) + Math.pow(b.y - a.y, 2))
}

function inputKind(value) {
  var kind = text(value || "mouse")
  if (["touch", "touchscreen", "finger"].indexOf(kind) >= 0) return "touch"
  if (["stylus", "pen", "tablet"].indexOf(kind) >= 0) return "stylus"
  return "mouse"
}

function windowIdentity(window) {
  var item = window && typeof window === "object" ? window : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  var address = String(foreign.address || item.address || "")
  var pid = number(foreign.pid !== undefined ? foreign.pid : item.pid, 0)
  var appId = String(foreign.appId || item.appId || foreign.class || item.class || foreign.initialClass || "").replace(/\.desktop$/, "")
  if (address) return "address:" + address
  if (pid > 0 && appId) return "pid:" + Math.floor(pid) + ":" + appId
  if (pid > 0) return "pid:" + Math.floor(pid)
  return appId ? "app:" + appId : ""
}

function emptyState() {
  return {
    active: false,
    eligible: false,
    phase: "idle",
    reason: "idle",
    windowId: "",
    inputKind: "mouse",
    startPoint: null,
    lastPoint: null,
    movedDistance: 0,
    monitorName: "",
    candidateId: "",
    candidateSince: 0,
    readyAt: 0,
    preview: null,
    layout: null,
    availableZones: [],
    committed: false
  }
}

function monitorRect(monitor) {
  var item = monitor || {}
  return engine().rect(number(item.x, 0), number(item.y, 0), number(item.width || item.logicalWidth, 1), number(item.height || item.logicalHeight, 1))
}

function monitorContains(monitor, value) {
  return engine().contains(monitorRect(monitor), value)
}

function findMonitor(monitors, value) {
  var list = Array.isArray(monitors) ? monitors : []
  for (var i = 0; i < list.length; i++) if (monitorContains(list[i], value)) return list[i]
  return list.length === 1 ? list[0] : null
}

function optionsFor(options) {
  var source = options && typeof options === "object" ? options : {}
  var result = {}
  for (var field in source) {
    if (["now", "point", "proximity", "contact", "dragging", "button", "monitors", "monitor", "windowId"].indexOf(field) >= 0) continue
    result[field] = source[field]
  }
  return result
}

function zoneList(monitor, options, kind) {
  var settings = optionsFor(options)
  var zones = engine().zones(monitor, settings)
  return zones.map(function(zone) {
    var activation = engine().activationRect(zone, monitor, kind, settings)
    return {
      id: zone.id,
      labelKey: zone.labelKey,
      orientation: zone.orientation,
      axis: zone.axis,
      custom: zone.custom === true,
      rect: zone.slots[0] ? clone(zone.slots[0].rect) : null,
      activation: activation,
      slots: clone(zone.slots)
    }
  })
}

function area(zone) {
  var value = zone && zone.rect ? zone.rect : {}
  return Math.max(1, number(value.width, 1) * number(value.height, 1))
}

function zoneRank(zone) {
  var id = String(zone && zone.id || "")
  if (id.indexOf("quarter-") === 0) return 1
  if (id.indexOf("third-") === 0) return 2
  if (id.indexOf("two-thirds-") === 0) return 3
  if (id.indexOf("half-") === 0) return 4
  if (id === "maximized") return 6
  return 0
}

function zoneAt(zones, value) {
  var candidate = point(value)
  var actual = []
  var expanded = []
  var list = Array.isArray(zones) ? zones : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].rect && engine().contains(list[i].rect, candidate)) actual.push(list[i])
    else if (list[i].activation && list[i].activation.rect && engine().contains(list[i].activation.rect, candidate)) expanded.push(list[i])
  }
  var choices = actual.length > 0 ? actual : expanded
  choices.sort(function(left, right) {
    var rank = zoneRank(left) - zoneRank(right)
    if (rank !== 0) return rank
    return area(left) - area(right)
  })
  return choices.length > 0 ? choices[0] : null
}

function previewFor(zone, monitor, options, windowId) {
  if (!zone) return null
  var settings = optionsFor(options)
  var layout = engine().layoutForZone(monitor, zone.id, settings, windowId)
  if (!layout) return null
  return {
    zoneId: zone.id,
    labelKey: zone.labelKey,
    orientation: zone.orientation,
    axis: zone.axis,
    rect: clone(zone.rect),
    layout: layout
  }
}

function beginDrag(window, kind, start, options) {
  var settings = options && typeof options === "object" ? options : {}
  var state = emptyState()
  var id = typeof window === "string" ? String(window) : windowIdentity(window)
  var input = inputKind(kind)
  state.windowId = id
  state.inputKind = input
  state.startPoint = point(start)
  state.lastPoint = point(start)
  state.eligible = Boolean(id)
  state.active = state.eligible
  state.phase = state.active ? "dragging" : "blocked"
  state.reason = state.active ? "waiting-for-movement" : "window-identity-unavailable"
  if (input === "stylus" && settings.proximity === true && settings.contact !== true && settings.dragging !== true) {
    state.active = false
    state.eligible = false
    state.phase = "blocked"
    state.reason = "stylus-proximity-is-not-a-drag"
  }
  return state
}

function updateDrag(previous, nextPoint, monitors, options) {
  var old = Object.assign(emptyState(), clone(previous || {}))
  if (!old.active || !old.eligible) return old
  var settings = options && typeof options === "object" ? options : {}
  var now = number(settings.now, Date.now())
  var current = point(nextPoint)
  old.lastPoint = current
  old.movedDistance = distance(old.startPoint, current)
  if (old.inputKind === "stylus" && settings.proximity === true && settings.contact !== true && settings.dragging !== true) {
    old.phase = "blocked"
    old.reason = "stylus-proximity-is-not-a-drag"
    old.preview = null
    old.layout = null
    old.candidateId = ""
    return old
  }
  var monitor = findMonitor(monitors, current)
  if (!monitor) {
    old.phase = "waiting-for-monitor"
    old.reason = "pointer-is-outside-known-monitors"
    old.preview = null
    old.layout = null
    old.candidateId = ""
    return old
  }
  old.monitorName = String(monitor.name || monitor.monitor || "active")
  var list = zoneList(monitor, settings, old.inputKind)
  old.availableZones = list
  var selected = zoneAt(list, current)
  var threshold = selected && selected.activation ? Number(selected.activation.movementThreshold || 0) : (old.inputKind === "touch" ? 18 : 8)
  if (old.movedDistance < threshold) {
    old.phase = "waiting-for-movement"
    old.reason = "movement-threshold"
    old.preview = null
    old.layout = null
    old.candidateId = ""
    return old
  }
  if (!selected) {
    old.phase = "dragging"
    old.reason = "outside-snap-zones"
    old.preview = null
    old.layout = null
    old.candidateId = ""
    old.candidateSince = 0
    old.readyAt = 0
    return old
  }
  var dwell = selected.activation ? Number(selected.activation.dwellMs || 0) : 0
  if (old.candidateId !== selected.id) {
    old.candidateId = selected.id
    old.candidateSince = now
    old.readyAt = now + Math.max(0, dwell)
  }
  old.preview = previewFor(selected, monitor, settings, old.windowId)
  old.layout = old.preview ? old.preview.layout : null
  if (now < old.readyAt) {
    old.phase = "previewing"
    old.reason = "dwell-pending"
  } else {
    old.phase = "ready"
    old.reason = "drop-to-commit"
  }
  return old
}

function selectZone(previous, zoneId, monitor, options) {
  var old = Object.assign(emptyState(), clone(previous || {}))
  if (!old.active || !old.eligible || !monitor) return old
  var list = zoneList(monitor, options || {}, old.inputKind)
  var wanted = String(engine().canonicalZoneId(zoneId) || "")
  var selected = null
  for (var i = 0; i < list.length; i++) if (list[i].id === wanted) { selected = list[i]; break }
  if (!selected) {
    old.phase = "dragging"
    old.reason = "unknown-snap-zone"
    return old
  }
  old.monitorName = String(monitor.name || monitor.monitor || "active")
  old.availableZones = list
  old.candidateId = selected.id
  old.candidateSince = number((options || {}).now, Date.now())
  old.readyAt = old.candidateSince
  old.preview = previewFor(selected, monitor, options || {}, old.windowId)
  old.layout = old.preview ? old.preview.layout : null
  old.phase = old.preview ? "ready" : "dragging"
  old.reason = old.preview ? "layout-selected" : "layout-unavailable"
  return old
}

function cancel(previous, reason) {
  var result = Object.assign(emptyState(), clone(previous || {}))
  result.active = false
  result.phase = "cancelled"
  result.reason = String(reason || "cancelled")
  result.preview = null
  result.layout = null
  result.candidateId = ""
  result.availableZones = []
  return result
}

function commit(previous) {
  var old = Object.assign(emptyState(), clone(previous || {}))
  if (!old.active || !old.eligible) return { ok: false, reason: old.reason || "inactive", state: old }
  if (old.phase !== "ready" || !old.preview || !old.layout) return { ok: false, reason: "snap-dwell-not-complete", state: old }
  var state = Object.assign(emptyState(), old)
  state.active = false
  state.phase = "committed"
  state.reason = "layout-commit-requested"
  state.committed = true
  return {
    ok: true,
    reason: "ready",
    action: { type: "apply-layout", windowId: old.windowId, zoneId: old.candidateId, layout: clone(old.layout) },
    state: state
  }
}

function availableZones(monitors, kind, options) {
  var list = Array.isArray(monitors) ? monitors : []
  var result = []
  for (var i = 0; i < list.length; i++) {
    var monitor = list[i]
    var zones = zoneList(monitor, options || {}, inputKind(kind))
    for (var j = 0; j < zones.length; j++) {
      zones[j].monitorName = String(monitor.name || monitor.monitor || "active")
      result.push(zones[j])
    }
  }
  return result
}

var api = {
  emptyState: emptyState,
  inputKind: inputKind,
  windowIdentity: windowIdentity,
  distance: distance,
  findMonitor: findMonitor,
  zoneAt: zoneAt,
  beginDrag: beginDrag,
  updateDrag: updateDrag,
  selectZone: selectZone,
  cancel: cancel,
  commit: commit,
  availableZones: availableZones
}
if (typeof module !== "undefined") module.exports = api
