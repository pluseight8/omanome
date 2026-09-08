// Transactional Split View state. Geometry is calculated locally and returned
// to the caller; the compositor apply/rollback belongs to the service layer.

var Layout = typeof require === "function" ? require("./LayoutEngine.js") : null
var SPLIT_SCHEMA_VERSION = 1
var PRESETS = ["50/50", "40/60", "60/40", "33/67", "67/33"]

function engine() {
  if (Layout) return Layout
  if (typeof LayoutEngine !== "undefined") return LayoutEngine
  return null
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function text(value) {
  return String(value === undefined || value === null ? "" : value).trim().toLowerCase()
}

function number(value, fallback) {
  var result = Number(value)
  if (isFinite(result)) return result
  return fallback === undefined ? 0 : Number(fallback)
}

function clamp(value, minimum, maximum) {
  return Math.max(Number(minimum), Math.min(Number(maximum), Number(value)))
}

function normalizedRatio(value) {
  var layout = engine()
  if (layout && typeof layout.ratioValue === "function") return layout.ratioValue(value)
  var name = text(value).replace(/\s+/g, "")
  var known = { "50/50": 0.5, "40/60": 0.4, "60/40": 0.6, "33/67": 1 / 3, "67/33": 2 / 3 }
  if (known[name] !== undefined) return known[name]
  return clamp(number(value, 0.5), 0.05, 0.95)
}

function ratioName(value) {
  var ratio = normalizedRatio(value)
  var names = ["50/50", "40/60", "60/40", "33/67", "67/33"]
  var values = [0.5, 0.4, 0.6, 1 / 3, 2 / 3]
  var nearest = ""
  var distance = Infinity
  for (var i = 0; i < values.length; i++) {
    var candidateDistance = Math.abs(values[i] - ratio)
    if (candidateDistance < distance) {
      distance = candidateDistance
      nearest = names[i]
    }
  }
  return distance < 0.0001 ? nearest : String(Math.round(ratio * 1000) / 1000)
}

function monitorFor(value, options) {
  var layout = engine()
  if (layout && typeof layout.normalizeMonitor === "function") return layout.normalizeMonitor(value, options || {})
  var source = value || {}
  return {
    name: String(source.name || "active"),
    x: number(source.x, 0), y: number(source.y, 0),
    width: Math.max(1, number(source.width, 1)), height: Math.max(1, number(source.height, 1)),
    scale: Math.max(0.5, number(source.scale, 1)),
    orientation: number(source.width, 1) < number(source.height, 1) ? "portrait" : "landscape",
    usable: { x: number(source.x, 0), y: number(source.y, 0), width: Math.max(1, number(source.width, 1)), height: Math.max(1, number(source.height, 1)) }
  }
}

function orientation(monitor, options) {
  var layout = engine()
  if (layout && typeof layout.orientation === "function")
    return layout.orientation(options && options.orientation || monitor.orientation, monitor.width, monitor.height)
  return monitor.width < monitor.height ? "portrait" : "landscape"
}

function axisFor(monitor, options) {
  return orientation(monitor, options) === "portrait" ? "horizontal" : "vertical"
}

function windowIds(value) {
  var source = Array.isArray(value) ? value : []
  return [String(source[0] || ""), String(source[1] || "")]
}

function gapFor(options) {
  var value = options && options.gap !== undefined ? Number(options.gap) : 12
  return clamp(isFinite(value) ? value : 12, 0, 160)
}

function minimumAlongAxis(monitor, options) {
  var minimum = options && (options.minimumSize || options.minSize)
  if (Array.isArray(minimum)) minimum = minimum[0]
  minimum = minimum && typeof minimum === "object" ? minimum : {}
  return Math.max(1, number(monitor && monitor.orientation === "portrait" ? minimum.height : minimum.width, 1))
}

function ratioBounds(stateOrMonitor, options) {
  var monitor = stateOrMonitor && stateOrMonitor.monitor ? stateOrMonitor.monitor : stateOrMonitor
  var settings = options || (stateOrMonitor && stateOrMonitor.options) || {}
  var normalized = monitorFor(monitor || {}, settings)
  var direction = orientation(normalized, settings)
  var length = direction === "portrait" ? normalized.usable.height : normalized.usable.width
  var available = Math.max(1, length - gapFor(settings))
  var minimum = minimumAlongAxis(Object.assign({}, normalized, { orientation: direction }), settings)
  var minimumRatio = clamp(minimum / available, 0.05, 0.95)
  var configuredMinimum = clamp(number(settings.minRatio, 0.05), 0.05, 0.95)
  var configuredMaximum = clamp(number(settings.maxRatio, 0.95), 0.05, 0.95)
  var lower = Math.min(configuredMaximum, Math.max(configuredMinimum, minimumRatio))
  var upper = Math.max(lower, Math.min(configuredMaximum, 1 - minimumRatio))
  return { min: lower, max: upper, minimumSize: minimum, available: available }
}

function buildPair(monitor, ratio, options, windows) {
  var layout = engine()
  var settings = clone(options || {})
  settings.orientation = orientation(monitor, settings)
  settings.gap = gapFor(settings)
  if (layout && typeof layout.splitPair === "function")
    return layout.splitPair(monitor, ratio, settings, windowIds(windows))
  return { schemaVersion: SPLIT_SCHEMA_VERSION, type: "split-pair", orientation: settings.orientation, axis: axisFor(monitor, settings), ratio: normalizedRatio(ratio), ratioName: ratioName(ratio), monitor: { name: monitor.name, scale: monitor.scale }, usable: clone(monitor.usable), slots: [] }
}

function dividerGeometry(pair, options) {
  if (!pair || !pair.usable || !Array.isArray(pair.slots) || pair.slots.length < 2) return null
  var first = pair.slots[0].rect
  var second = pair.slots[1].rect
  var handle = Math.max(1, number(options && options.dividerHandleSize, 48))
  var visual = Math.max(1, number(options && options.dividerVisualSize, 2))
  if (pair.axis === "horizontal") {
    var top = first.y + first.height
    var bottom = second.y
    return {
      axis: "horizontal",
      center: (top + bottom) / 2,
      rect: { x: pair.usable.x, y: Math.round((top + bottom - handle) / 2), width: pair.usable.width, height: handle },
      visualRect: { x: pair.usable.x, y: Math.round((top + bottom - visual) / 2), width: pair.usable.width, height: visual }
    }
  }
  var left = first.x + first.width
  var right = second.x
  return {
    axis: "vertical",
    center: (left + right) / 2,
    rect: { x: Math.round((left + right - handle) / 2), y: pair.usable.y, width: handle, height: pair.usable.height },
    visualRect: { x: Math.round((left + right - visual) / 2), y: pair.usable.y, width: visual, height: pair.usable.height }
  }
}

function emptyTransaction(pair) {
  return { status: "idle", baseline: clone(pair), candidate: null, reason: "" }
}

function createState(monitorValue, windows, options) {
  var settings = clone(options || {})
  var monitor = monitorFor(monitorValue || {}, settings)
  var ids = windowIds(windows)
  var ratio = normalizedRatio(settings.ratio || settings.defaultRatio || "50/50")
  var bounds = ratioBounds(monitor, settings)
  ratio = clamp(ratio, bounds.min, bounds.max)
  var pair = buildPair(monitor, ratio, settings, ids)
  return {
    schemaVersion: SPLIT_SCHEMA_VERSION,
    phase: "idle",
    monitor: clone(monitor),
    windows: ids,
    options: settings,
    pair: pair,
    committedPair: clone(pair),
    ratio: ratio,
    ratioName: ratioName(ratio),
    divider: {
      enabled: settings.dividerEnabled !== false,
      autoHide: settings.dividerAutoHide !== false,
      visible: true,
      opacity: 1,
      active: false,
      near: false,
      lastInteractionAt: null
    },
    transaction: emptyTransaction(pair),
    error: ""
  }
}

function withRatio(state, ratio, options) {
  var source = clone(state || {})
  var settings = Object.assign({}, source.options || {}, options || {})
  var monitor = monitorFor(source.monitor || {}, settings)
  var bounds = ratioBounds(monitor, settings)
  var value = clamp(normalizedRatio(ratio), bounds.min, bounds.max)
  var pair = buildPair(monitor, value, settings, source.windows)
  source.monitor = clone(monitor)
  source.options = settings
  source.pair = pair
  source.ratio = value
  source.ratioName = ratioName(value)
  return source
}

function beginDividerDrag(state, point, options) {
  var source = clone(state || {})
  if (!source.pair || !source.pair.slots || source.pair.slots.length < 2)
    return Object.assign(source, { phase: "blocked", error: "split-pair-required" })
  if (source.divider && source.divider.enabled === false)
    return Object.assign(source, { phase: "blocked", error: "divider-disabled" })
  var settings = Object.assign({}, source.options || {}, options || {})
  var divider = dividerGeometry(source.pair, settings)
  if (!divider) return Object.assign(source, { phase: "blocked", error: "divider-unavailable" })
  var coordinate = divider.axis === "horizontal" ? number(point && point.y, NaN) : number(point && point.x, NaN)
  if (!isFinite(coordinate)) return Object.assign(source, { phase: "blocked", error: "invalid-pointer" })
  source.phase = "dragging"
  source.error = ""
  source.options = settings
  source.transaction = { status: "active", baseline: clone(source.committedPair || source.pair), candidate: clone(source.pair), reason: "" }
  source.divider = Object.assign(source.divider || {}, { active: true, visible: true, opacity: 1, near: true, lastInteractionAt: number(options && options.now, 0) || null })
  source.drag = { axis: divider.axis, startCoordinate: coordinate, startRatio: source.ratio, lastCoordinate: coordinate }
  return source
}

function updateDividerDrag(state, point, options) {
  var source = clone(state || {})
  if (!source.drag || source.phase !== "dragging") return source
  var settings = Object.assign({}, source.options || {}, options || {})
  var coordinate = source.drag.axis === "horizontal" ? number(point && point.y, NaN) : number(point && point.x, NaN)
  if (!isFinite(coordinate)) return Object.assign(source, { error: "invalid-pointer" })
  var area = source.pair.usable
  var start = source.drag.axis === "horizontal" ? area.y : area.x
  var ratio = (coordinate - start - gapFor(settings) / 2) / Math.max(1, source.drag.axis === "horizontal" ? area.height - gapFor(settings) : area.width - gapFor(settings))
  var bounds = ratioBounds(source.monitor, settings)
  ratio = clamp(ratio, bounds.min, bounds.max)
  source = withRatio(source, ratio, settings)
  source.drag.lastCoordinate = coordinate
  source.transaction = { status: "active", baseline: clone(source.transaction.baseline), candidate: clone(source.pair), reason: "" }
  source.divider = Object.assign(source.divider || {}, { active: true, visible: true, opacity: 1, near: true, lastInteractionAt: number(settings.now, 0) || source.divider.lastInteractionAt || null })
  return source
}

function begin(state) { return beginDividerDrag.apply(null, arguments) }
function update(state) { return updateDividerDrag.apply(null, arguments) }

function commit(state, result) {
  var source = clone(state || {})
  if (source.phase !== "dragging" || !source.transaction || source.transaction.status !== "active")
    return { ok: false, reason: "no-active-transaction", state: source }
  if (result === false || (result && result.ok === false)) return rollback(source, result && result.reason || "apply-failed")
  source.phase = "committed"
  source.committedPair = clone(source.pair)
  source.transaction = { status: "committed", baseline: clone(source.transaction.baseline), candidate: clone(source.pair), reason: "" }
  source.divider = Object.assign(source.divider || {}, { active: false, visible: true, opacity: 1 })
  delete source.drag
  return { ok: true, pair: clone(source.pair), state: source }
}

function rollback(state, reason) {
  var source = clone(state || {})
  var baseline = source.transaction && source.transaction.baseline ? clone(source.transaction.baseline) : clone(source.committedPair || source.pair)
  source.pair = baseline
  source.committedPair = clone(baseline)
  source.ratio = normalizedRatio(baseline.ratio)
  source.ratioName = ratioName(source.ratio)
  source.phase = "rolled-back"
  source.error = String(reason || "apply-failed")
  source.transaction = { status: "rolled-back", baseline: baseline, candidate: null, reason: source.error }
  source.divider = Object.assign(source.divider || {}, { active: false, visible: true, opacity: 1 })
  delete source.drag
  return { ok: false, rolledBack: true, reason: source.error, pair: clone(baseline), state: source }
}

function cancel(state, reason) {
  return rollback(state, reason || "cancelled")
}

function chooseRatio(state, ratio, options) {
  var source = clone(state || {})
  var updated = withRatio(source, ratio, options)
  if (source.phase === "dragging") {
    updated.phase = "dragging"
    updated.drag = source.drag
    updated.transaction = { status: "active", baseline: clone(source.transaction.baseline), candidate: clone(updated.pair), reason: "" }
    return updated
  }
  updated.phase = "preview"
  updated.transaction = { status: "preview", baseline: clone(source.committedPair || source.pair), candidate: clone(updated.pair), reason: "" }
  return updated
}

function rotate(state, monitorValue, options) {
  var source = clone(state || {})
  var settings = Object.assign({}, source.options || {}, options || {})
  var monitor = monitorFor(monitorValue || source.monitor || {}, settings)
  var ratio = source.ratio === undefined ? settings.defaultRatio || "50/50" : source.ratio
  var next = createState(monitor, source.windows, Object.assign({}, settings, { ratio: ratio }))
  next.divider.lastInteractionAt = source.divider && source.divider.lastInteractionAt || null
  return next
}

function notifyDividerInteraction(state, kind, now) {
  var source = clone(state || {})
  var eventKind = text(kind || "pointer")
  source.divider = Object.assign(source.divider || {}, {
    visible: true,
    opacity: 1,
    near: true,
    lastInteractionAt: number(now, 0) || null,
    lastInputKind: eventKind
  })
  return source
}

function dividerVisibility(state, now, options) {
  var source = clone(state || {})
  var settings = Object.assign({}, source.options || {}, options || {})
  var divider = source.divider || {}
  if (!divider.autoHide || divider.active || divider.near || divider.lastInteractionAt === null || divider.lastInteractionAt === undefined) {
    source.divider = Object.assign(divider, { visible: true, opacity: 1 })
    return source
  }
  var delay = Math.max(0, number(settings.dividerAutoHideMs, 1800))
  var elapsed = Math.max(0, number(now, divider.lastInteractionAt) - number(divider.lastInteractionAt, 0))
  var hidden = elapsed >= delay
  source.divider = Object.assign(divider, { visible: !hidden, opacity: hidden ? 0.16 : 1 })
  return source
}

function setDividerProximity(state, near, now) {
  var source = clone(state || {})
  source.divider = Object.assign(source.divider || {}, {
    near: !!near,
    lastInteractionAt: near ? (number(now, 0) || source.divider.lastInteractionAt || null) : source.divider.lastInteractionAt
  })
  return source
}

function dividerHit(state, point, options) {
  var source = state || {}
  var divider = dividerGeometry(source.pair, options || source.options || {})
  if (!divider) return false
  var pointValue = point || {}
  var rect = divider.rect
  return number(pointValue.x, NaN) >= rect.x && number(pointValue.x, NaN) < rect.x + rect.width && number(pointValue.y, NaN) >= rect.y && number(pointValue.y, NaN) < rect.y + rect.height
}

var api = {
  SPLIT_SCHEMA_VERSION: SPLIT_SCHEMA_VERSION,
  PRESETS: PRESETS,
  normalizedRatio: normalizedRatio,
  ratioName: ratioName,
  ratioBounds: ratioBounds,
  dividerGeometry: dividerGeometry,
  createState: createState,
  beginDividerDrag: beginDividerDrag,
  updateDividerDrag: updateDividerDrag,
  begin: begin,
  update: update,
  chooseRatio: chooseRatio,
  commit: commit,
  rollback: rollback,
  cancel: cancel,
  rotate: rotate,
  notifyDividerInteraction: notifyDividerInteraction,
  dividerVisibility: dividerVisibility,
  setDividerProximity: setDividerProximity,
  dividerHit: dividerHit
}
if (typeof module !== "undefined") module.exports = api
