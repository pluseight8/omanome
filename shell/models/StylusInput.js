// Native tablet state is intentionally a small, bounded model. It accepts
// capability events from omanome-input but never stores hardware serials,
// typed text, or an unbounded event history.

var MAX_STROKES = 64
var MAX_POINTS_PER_STROKE = 2048
var MAX_TOTAL_POINTS = 8192
var TABLET_EVENT_KINDS = [
  "tablet-added", "tablet-ready", "tablet-removed", "tool-added", "tool-ready", "tool-removed",
  "tool-type", "tool-capability", "pad-added", "proximity-in", "proximity-out", "tip-down", "tip-up",
  "motion", "pressure", "tilt", "distance", "rotation", "slider", "wheel", "button", "frame"
]

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function bool(value) {
  return value === true || value === 1 || String(value).toLowerCase() === "true"
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}

function clamp(value, minimum, maximum, fallback) {
  var result = number(value, fallback)
  if (!isFinite(result)) result = Number(fallback || 0)
  return Math.max(minimum, Math.min(maximum, result))
}

function timestamp(value, fallback) {
  var result = number(value, fallback)
  return result > 0 ? Math.floor(result) : Math.floor(number(fallback, 0))
}

function normalizeEvent(event, fallbackNow) {
  var source = object(event)
  var kind = String(source.event || source.action || "").toLowerCase()
  var fallback = number(fallbackNow, Date.now())
  if (fallback <= 0) fallback = Date.now()
  var sequence = number(source.sequence, 0)
  return {
    kind: kind,
    x: clamp(source.x, -1000000, 1000000, 0),
    y: clamp(source.y, -1000000, 1000000, 0),
    pressure: clamp(source.pressure, 0, 65535, 0) / 65535,
    distance: clamp(source.distance, 0, 65535, 0) / 65535,
    tiltX: clamp(source.tiltX !== undefined ? source.tiltX : source.tilt_x, -90, 90, 0),
    tiltY: clamp(source.tiltY !== undefined ? source.tiltY : source.tilt_y, -90, 90, 0),
    rotation: clamp(source.rotation !== undefined ? source.rotation : source.degrees, -360, 360, 0),
    proximity: bool(source.proximity),
    contact: bool(source.contact),
    eraser: bool(source.eraser),
    button: clamp(source.button, 0, 65535, 0),
    pressed: bool(source.pressed),
    time: timestamp(source.time !== undefined ? source.time : source.timestamp, fallback),
    sequence: sequence > 0 ? Math.floor(sequence) : 0,
    session: String(source.session || "").slice(0, 128)
  }
}

function knownEvent(kind) {
  return TABLET_EVENT_KINDS.indexOf(String(kind || "")) >= 0
}

function clearInteraction(state) {
  state.proximity = false
  state.contact = false
  state.eraser = false
  state.lastSample = null
  state.currentStroke = []
  state.lastButton = 0
  state.buttonPressed = false
  return state
}

function emptyState() {
  return {
    schemaVersion: 1,
    backend: "unavailable",
    available: false,
    tabletCount: 0,
    toolCount: 0,
    proximity: false,
    contact: false,
    eraser: false,
    capabilities: { pressure: false, tilt: false, distance: false, rotation: false, buttons: false },
    lastEvent: "",
    lastSample: null,
    session: "",
    eventSequence: 0,
    lastButton: 0,
    buttonPressed: false,
    strokes: [],
    currentStroke: [],
    totalPoints: 0,
    revision: 0,
    palm: { mode: "automatic", active: false, until: 0, reason: "no-stylus-proximity" }
  }
}

function point(sample) {
  return {
    x: sample.x,
    y: sample.y,
    pressure: sample.pressure,
    distance: sample.distance,
    tiltX: sample.tiltX,
    tiltY: sample.tiltY,
    rotation: sample.rotation,
    eraser: sample.eraser,
    timestamp: sample.time
  }
}

function countPoints(strokes, current) {
  var total = Array.isArray(current) ? current.length : 0
  var list = Array.isArray(strokes) ? strokes : []
  for (var i = 0; i < list.length; i++) total += Array.isArray(list[i]) ? list[i].length : 0
  return total
}

function trimStrokes(strokes, current) {
  var list = Array.isArray(strokes) ? strokes.slice() : []
  while (list.length > MAX_STROKES) list.shift()
  var total = countPoints(list, current)
  while (total > MAX_TOTAL_POINTS && list.length > 0) {
    total -= Array.isArray(list[0]) ? list[0].length : 0
    list.shift()
  }
  var active = Array.isArray(current) ? current.slice(-MAX_POINTS_PER_STROKE) : []
  if (active.length > MAX_POINTS_PER_STROKE) active = active.slice(-MAX_POINTS_PER_STROKE)
  return { strokes: list, currentStroke: active, totalPoints: countPoints(list, active) }
}

function capabilityState(capabilities, previous) {
  var old = object(previous)
  var source = object(capabilities)
  return {
    pressure: bool(source.pressure) || old.pressure === true,
    tilt: bool(source.tilt) || old.tilt === true,
    distance: bool(source.distance) || old.distance === true,
    rotation: bool(source.rotation) || old.rotation === true,
    buttons: bool(source.buttons) || old.buttons === true
  }
}

function applyEvent(previous, rawEvent, now) {
  var old = Object.assign(emptyState(), object(previous))
  old.capabilities = capabilityState(old.capabilities, {})
  old.strokes = Array.isArray(old.strokes) ? old.strokes : []
  old.currentStroke = Array.isArray(old.currentStroke) ? old.currentStroke : []
  var event = object(rawEvent)
  if (String(event.type || "") !== "tablet.event") return old

  var sample = normalizeEvent(event, now)
  if (!knownEvent(sample.kind)) return old
  if (sample.session && old.session && sample.session !== old.session) {
    var fresh = emptyState()
    fresh.backend = old.backend
    fresh.available = old.available
    fresh.capabilities = old.capabilities
    old = fresh
  }
  if (sample.sequence > 0 && Number(old.eventSequence || 0) > 0 && sample.sequence <= Number(old.eventSequence || 0)) return old

  var interaction = ["proximity-in", "proximity-out", "tip-down", "tip-up", "motion", "pressure", "tilt", "distance", "rotation"].indexOf(sample.kind) >= 0
  if (sample.kind === "proximity-in" && old.proximity === true) return old
  if (sample.kind === "proximity-out" && old.proximity !== true && old.contact !== true) return old
  if (sample.kind === "tip-down" && old.contact === true) return old
  if (sample.kind === "tip-up" && old.contact !== true) return old
  if (interaction && ["motion", "pressure", "tilt", "distance", "rotation"].indexOf(sample.kind) >= 0 && old.proximity !== true && old.contact !== true && event.proximity === undefined && event.contact === undefined) return old

  var next = Object.assign({}, old)
  next.backend = "native-wayland-tablet-v2"
  next.available = true
  next.revision = Number(old.revision || 0) + 1
  next.lastEvent = sample.kind
  next.session = sample.session || old.session || ""
  next.eventSequence = sample.sequence > 0 ? sample.sequence : Number(old.eventSequence || 0)
  next.capabilities = capabilityState({
    pressure: event.pressure !== undefined || sample.kind === "pressure" || event.pressure === true || (sample.kind === "tool-capability" && Number(event.capability) === 2),
    tilt: sample.kind === "tilt" || event.tilt === true,
    distance: sample.kind === "distance" || event.distance === true || (sample.kind === "tool-capability" && Number(event.capability) === 3),
    rotation: sample.kind === "rotation" || event.rotation === true,
    buttons: sample.kind === "button" || event.buttons === true
  }, old.capabilities)
  if (sample.kind === "tool-capability") {
    var capability = Number(event.capability)
    next.capabilities.tilt = next.capabilities.tilt || capability === 1
    next.capabilities.pressure = next.capabilities.pressure || capability === 2
    next.capabilities.distance = next.capabilities.distance || capability === 3
    next.capabilities.rotation = next.capabilities.rotation || capability === 4
  }

  if (sample.kind === "tablet-added") {
    next.tabletCount = Math.max(0, Number(event.tabletCount !== undefined ? event.tabletCount : old.tabletCount + 1))
    next.available = true
  }
  if (sample.kind === "tablet-removed") {
    next.tabletCount = Math.max(0, Number(event.tabletCount !== undefined ? event.tabletCount : 0))
    next.toolCount = 0
    next.available = false
    clearInteraction(next)
  }
  if (sample.kind === "tool-added") {
    next.toolCount = Math.max(0, Number(event.toolCount !== undefined ? event.toolCount : old.toolCount + 1))
    next.available = true
  }
  if (sample.kind === "tool-removed") {
    next.toolCount = Math.max(0, Number(event.toolCount !== undefined ? event.toolCount : 0))
    next.available = next.tabletCount > 0 || next.toolCount > 0
    clearInteraction(next)
  }
  if (sample.kind === "proximity-in") {
    next.proximity = true
    next.eraser = sample.eraser
  } else if (sample.kind === "proximity-out") {
    next.proximity = false
    next.contact = false
    next.currentStroke = []
  } else if (sample.kind === "tip-down") {
    next.proximity = true
    next.contact = true
    next.eraser = sample.eraser
    next.currentStroke = []
  } else if (sample.kind === "tip-up") {
    next.contact = false
    if (next.currentStroke.length > 0) next.strokes = next.strokes.concat([next.currentStroke])
    next.currentStroke = []
  } else if (sample.kind === "motion" || sample.kind === "pressure" || sample.kind === "tilt" || sample.kind === "distance" || sample.kind === "rotation") {
    if (event.proximity !== undefined) next.proximity = sample.proximity
    if (event.contact !== undefined) next.contact = sample.contact
    if (next.contact || next.currentStroke.length > 0) {
      var active = next.currentStroke.concat([point(sample)])
      next.currentStroke = active.slice(-MAX_POINTS_PER_STROKE)
    }
  }
  if (sample.kind === "tool-type") next.eraser = sample.eraser
  if (sample.kind === "button") {
    next.lastButton = sample.button
    next.buttonPressed = sample.pressed
  }
  if (sample.kind === "proximity-out") next.lastButton = 0
  if (sample.kind === "frame") next.lastSample = old.lastSample
  else if (["motion", "pressure", "tilt", "distance", "rotation", "tip-down", "tip-up"].indexOf(sample.kind) >= 0)
    next.lastSample = point(sample)
  var bounded = trimStrokes(next.strokes, next.currentStroke)
  next.strokes = bounded.strokes
  next.currentStroke = bounded.currentStroke
  next.totalPoints = bounded.totalPoints
  return next
}

function normalizePalmMode(value) {
  var mode = String(value || "automatic").toLowerCase()
  return ["automatic", "balanced", "aggressive", "off"].indexOf(mode) >= 0 ? mode : "automatic"
}

function palmTransition(previous, signals, now, config) {
  var old = object(previous)
  var source = object(signals)
  var settings = object(config)
  var mode = normalizePalmMode(settings.mode || settings.palmRejection)
  var timestampNow = timestamp(now, Date.now())
  var proximity = bool(source.stylusProximity) || bool(source.stylusContact)
  var touchCount = Math.max(0, Number(source.touchCount || source.touchContacts || 0))
  var hold = mode === "aggressive" ? 900 : (mode === "balanced" ? 520 : 320)
  if (mode === "off" || !proximity) return { mode: mode, active: false, until: 0, reason: mode === "off" ? "disabled" : "no-stylus-proximity" }
  var until = Number(old.until || 0)
  if (touchCount > 0 || bool(source.stylusContact)) until = Math.max(until, timestampNow + hold)
  var active = until > timestampNow
  return { mode: mode, active: active, until: active ? until : 0, reason: active ? "stylus-proximity-window" : "window-expired" }
}

function shouldSuppressTouch(palm, signals, now) {
  var state = palmTransition(palm, signals, now, { mode: object(palm).mode || "automatic" })
  return state.active === true
}

function providerState(config, nativeState) {
  var settings = object(config)
  var native = object(nativeState)
  var enabled = settings.enabled !== false
  var available = native.available === true && native.backend === "native-wayland-tablet-v2"
  return {
    enabled: enabled,
    ink: enabled && available ? "native-wayland-tablet-v2" : "unavailable",
    recognition: "unavailable",
    candidates: false,
    languages: [],
    cloud: false,
    reason: enabled && available ? "local ink captured; recognizer not installed" : "native tablet events unavailable"
  }
}

function recognitionResult(provider) {
  var state = object(provider)
  return {
    available: state.recognition !== "unavailable",
    text: "",
    candidates: [],
    reason: state.reason || "recognizer-unavailable"
  }
}

var api = {
  MAX_STROKES: MAX_STROKES,
  MAX_POINTS_PER_STROKE: MAX_POINTS_PER_STROKE,
  MAX_TOTAL_POINTS: MAX_TOTAL_POINTS,
  normalizeEvent: normalizeEvent,
  emptyState: emptyState,
  applyEvent: applyEvent,
  normalizePalmMode: normalizePalmMode,
  palmTransition: palmTransition,
  shouldSuppressTouch: shouldSuppressTouch,
  providerState: providerState,
  recognitionResult: recognitionResult
}
if (typeof module !== "undefined") module.exports = api
