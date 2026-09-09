// Hardware Calibration Center math and rollback state machine.
//
// This module never emits synthetic input and never talks to a compositor.
// Samples must be explicitly marked real by the native/backend adapter. The
// output is a bounded candidate mapping that a later UI transaction can show,
// confirm, commit, or revert.

var SCHEMA_VERSION = 1
var SAFE_ID = /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/
var MAX_TOUCH_SAMPLES = 5
var MAX_STYLUS_SAMPLES = 256
var TOUCH_TARGETS = [
  { id: "top-left", x: 0.15, y: 0.15 },
  { id: "top-right", x: 0.85, y: 0.15 },
  { id: "center", x: 0.50, y: 0.50 },
  { id: "bottom-left", x: 0.15, y: 0.85 },
  { id: "bottom-right", x: 0.85, y: 0.85 }
]
var PRESSURE_CURVES = ["linear", "soft", "firm"]

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function bool(value) {
  var normalized = string(value).toLowerCase()
  return value === true || value === 1 || normalized === "true" || normalized === "yes" || normalized === "1"
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function finite(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function clamp(value, minimum, maximum, fallback) {
  var result = finite(value, fallback)
  return Math.max(minimum, Math.min(maximum, result))
}

function round(value) {
  return Math.round(Number(value) * 1000000) / 1000000
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function safeId(value) {
  var id = string(value).trim()
  return SAFE_ID.test(id) ? id : ""
}

function safeSource(value) {
  var name = token(value)
  if (["native", "libinput", "evdev", "udev", "wayland", "hardware", "fixture"].indexOf(name) >= 0) return name
  return "native"
}

function capabilityBag(value) {
  var source = object(value)
  var raw = source.capabilities || source.features || source.supported || source
  var result = {}
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length; i++) result[token(raw[i])] = true
  } else {
    for (var key in object(raw)) if (bool(raw[key])) result[token(key)] = true
  }
  for (var field in source) if (field !== "capabilities" && field !== "features" && field !== "supported" && bool(source[field])) result[token(field)] = true
  return result
}

function supportedCapabilities(kind, value) {
  var caps = capabilityBag(value)
  var result = {}
  if (kind === "touchscreen" || kind === "touch") {
    result.coordinate = true
    result.absolute = caps.absolute === true || caps.coordinate === true || caps.touch === true || caps.touchscreen === true
    result.multitouch = caps.multitouch === true || caps["multi-touch"] === true
    result.rotation = caps.rotation === true
  } else {
    result.coordinate = caps.stylus === true || caps.tablet === true || caps.pressure === true || caps.tilt === true || caps["tilt-x"] === true || caps["tilt-y"] === true || caps.proximity === true || caps.eraser === true || caps.buttons === true
    result.pressure = caps.pressure === true
    result.tilt = caps.tilt === true || caps["tilt-x"] === true || caps["tilt-y"] === true || caps.tiltx === true || caps.tilty === true
    result.proximity = caps.proximity === true
    result.eraser = caps.eraser === true
    result.buttons = caps.buttons === true || caps.button === true
    result.distance = caps.distance === true
    result.rotation = caps.rotation === true
  }
  return result
}

function touchTargets() {
  return clone(TOUCH_TARGETS)
}

function deviceBounds(value) {
  var source = object(value)
  var result = {
    minX: finite(source.minX, 0), minY: finite(source.minY, 0),
    maxX: finite(source.maxX, 1), maxY: finite(source.maxY, 1)
  }
  if (result.maxX <= result.minX) { result.minX = 0; result.maxX = 1 }
  if (result.maxY <= result.minY) { result.minY = 0; result.maxY = 1 }
  return result
}

function outputGeometry(value) {
  var source = object(value)
  return {
    x: finite(source.x, 0), y: finite(source.y, 0),
    width: Math.max(0, finite(source.width, 0)), height: Math.max(0, finite(source.height, 0)),
    scale: clamp(source.scale, 0.25, 8, 1)
  }
}

function emptyTouchState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    kind: "touchscreen",
    phase: "idle",
    deviceId: "",
    outputId: "",
    targetIndex: 0,
    targets: touchTargets(),
    samples: [],
    result: null,
    supported: {},
    deviceBounds: deviceBounds({}),
    outputGeometry: outputGeometry({}),
    realSamplesOnly: true,
    error: ""
  }
}

function beginTouch(deviceId, outputId, capabilities, options) {
  var device = safeId(deviceId)
  var output = safeId(outputId)
  var supported = supportedCapabilities("touchscreen", capabilities)
  if (!device || !output || supported.absolute !== true) {
    var unavailable = emptyTouchState()
    unavailable.phase = "unavailable"
    unavailable.error = !device || !output ? "invalid-device-or-output" : "absolute-touch-capability-unavailable"
    unavailable.deviceId = device
    unavailable.outputId = output
    unavailable.supported = supported
    return unavailable
  }
  var settings = object(options)
  var state = emptyTouchState()
  state.phase = "collecting"
  state.deviceId = device
  state.outputId = output
  state.supported = supported
  state.deviceBounds = deviceBounds(settings.deviceBounds || settings.bounds)
  state.outputGeometry = outputGeometry(settings.outputGeometry || settings.output)
  return state
}

function normalizedPoint(sample, state) {
  var item = object(sample)
  var bounds = object(state.deviceBounds)
  var x = finite(item.actualX, finite(item.deviceX, finite(item.x, NaN)))
  var y = finite(item.actualY, finite(item.deviceY, finite(item.y, NaN)))
  if (!isFinite(x) || !isFinite(y)) return null
  var coordinateSpace = token(item.coordinateSpace || item.coordinate_space || "normalized")
  if (coordinateSpace !== "normalized") {
    x = (x - finite(bounds.minX, 0)) / Math.max(0.000001, finite(bounds.maxX, 1) - finite(bounds.minX, 0))
    y = (y - finite(bounds.minY, 0)) / Math.max(0.000001, finite(bounds.maxY, 1) - finite(bounds.minY, 0))
  }
  return { x: x, y: y }
}

function transformTarget(target, rotation) {
  var x = target.x
  var y = target.y
  if (rotation === 90) return { x: 1 - y, y: x }
  if (rotation === 180) return { x: 1 - x, y: 1 - y }
  if (rotation === 270) return { x: y, y: 1 - x }
  return { x: x, y: y }
}

function fitAxis(expected, actual) {
  var count = Math.min(expected.length, actual.length)
  if (count < 2) return null
  var expectedMean = 0
  var actualMean = 0
  for (var i = 0; i < count; i++) { expectedMean += expected[i]; actualMean += actual[i] }
  expectedMean /= count
  actualMean /= count
  var variance = 0
  var covariance = 0
  for (var v = 0; v < count; v++) {
    variance += (expected[v] - expectedMean) * (expected[v] - expectedMean)
    covariance += (expected[v] - expectedMean) * (actual[v] - actualMean)
  }
  if (variance < 0.000001) return null
  var scale = covariance / variance
  var offset = actualMean - scale * expectedMean
  return { scale: scale, offset: offset }
}

function solveCandidate(samples, rotation, state) {
  var expectedX = []
  var expectedY = []
  var actualX = []
  var actualY = []
  for (var i = 0; i < samples.length; i++) {
    var point = normalizedPoint(samples[i], state)
    var target = transformTarget(TOUCH_TARGETS[i], rotation)
    if (!point) return null
    expectedX.push(target.x)
    expectedY.push(target.y)
    actualX.push(point.x)
    actualY.push(point.y)
  }
  var xFit = fitAxis(expectedX, actualX)
  var yFit = fitAxis(expectedY, actualY)
  if (!xFit || !yFit) return null
  var error = 0
  for (var p = 0; p < samples.length; p++) {
    var predictedX = xFit.scale * expectedX[p] + xFit.offset
    var predictedY = yFit.scale * expectedY[p] + yFit.offset
    var dx = predictedX - actualX[p]
    var dy = predictedY - actualY[p]
    error += dx * dx + dy * dy
  }
  return {
    rotation: rotation,
    scaleX: xFit.scale,
    scaleY: yFit.scale,
    offsetX: xFit.offset,
    offsetY: yFit.offset,
    rmsError: Math.sqrt(error / Math.max(1, samples.length * 2))
  }
}

function explicitWrongOutput(samples, outputId) {
  for (var i = 0; i < samples.length; i++) {
    var sampleOutput = safeId(samples[i] && (samples[i].outputId || samples[i].displayId || samples[i].display_id))
    if (sampleOutput && sampleOutput !== outputId) return true
  }
  return false
}

function solveTouch(samples, state) {
  var list = array(samples)
  if (list.length !== MAX_TOUCH_SAMPLES) return { status: "incomplete", safe: false, suggestion: "collect-all-five-targets" }
  var best = null
  var rotations = [0, 90, 180, 270]
  for (var i = 0; i < rotations.length; i++) {
    var candidate = solveCandidate(list, rotations[i], state)
    if (candidate && (!best || candidate.rmsError < best.rmsError)) best = candidate
  }
  if (!best) return { status: "invalid", safe: false, suggestion: "collect-valid-real-samples" }
  var scaleX = Math.abs(best.scaleX)
  var scaleY = Math.abs(best.scaleY)
  var wrongOutput = explicitWrongOutput(list, state.outputId)
  var outOfRange = scaleX < 0.5 || scaleX > 2 || scaleY < 0.5 || scaleY > 2 || Math.abs(best.offsetX) > 0.5 || Math.abs(best.offsetY) > 0.5
  var highError = best.rmsError > 0.08
  var safe = !wrongOutput && !outOfRange && !highError
  var status = safe ? "ready" : "needs-remap"
  var suggestion = wrongOutput || highError && best.rmsError > 0.18 ? "wrong-monitor-mapping" : outOfRange ? "calibration-out-of-range" : "collect-more-stable-samples"
  return {
    status: status,
    safe: safe,
    outputId: state.outputId,
    offset: { x: round(best.offsetX), y: round(best.offsetY) },
    scale: { x: round(scaleX), y: round(scaleY) },
    axis: { swapped: best.rotation === 90 || best.rotation === 270, invertX: best.scaleX < 0, invertY: best.scaleY < 0 },
    rotation: best.rotation,
    rmsError: round(best.rmsError),
    suggestion: suggestion,
    matrix: safe ? {
      scaleX: round(best.scaleX), scaleY: round(best.scaleY), offsetX: round(best.offsetX), offsetY: round(best.offsetY), rotation: best.rotation
    } : null
  }
}

function recordTouchSample(previous, sample) {
  var old = Object.assign(emptyTouchState(), object(previous))
  if (old.phase !== "collecting") return { accepted: false, reason: "touch-calibration-not-collecting", state: old }
  var item = object(sample)
  if (item.real !== true || item.synthetic === true || safeSource(item.source) === "fixture") return { accepted: false, reason: "real-sample-required", state: old }
  if (old.samples.length >= MAX_TOUCH_SAMPLES) return { accepted: false, reason: "sample-limit", state: old }
  var expected = TOUCH_TARGETS[old.targetIndex]
  var targetId = string(item.targetId || item.target_id || expected.id)
  if (!expected || targetId !== expected.id) return { accepted: false, reason: "unexpected-target", state: old }
  if (old.samples.some(function(row) { return row.targetId === targetId })) return { accepted: false, reason: "duplicate-target", state: old }
  if (!normalizedPoint(item, old)) return { accepted: false, reason: "invalid-coordinate", state: old }
  var sampleOutput = safeId(item.outputId || item.displayId || item.display_id)
  var captured = {
    targetId: targetId,
    actualX: round(finite(item.actualX, finite(item.deviceX, item.x))),
    actualY: round(finite(item.actualY, finite(item.deviceY, item.y))),
    coordinateSpace: token(item.coordinateSpace || item.coordinate_space || "normalized") === "normalized" ? "normalized" : "device",
    outputId: sampleOutput,
    real: true,
    source: safeSource(item.source),
    timestamp: finite(item.timestamp, 0)
  }
  var samples = old.samples.slice()
  samples.push(captured)
  var next = Object.assign({}, old, { samples: samples, targetIndex: samples.length, error: "" })
  if (samples.length === MAX_TOUCH_SAMPLES) {
    next.phase = "analyzed"
    next.result = solveTouch(samples, next)
  }
  return { accepted: true, reason: "sample-recorded", state: next }
}

function cancelCalibration(previous, reason) {
  var old = Object.assign(emptyTouchState(), object(previous))
  old.phase = "cancelled"
  old.error = string(reason || "calibration-cancelled")
  old.result = null
  return old
}

function normalizeStylusSample(sample, supported) {
  var item = object(sample)
  var result = { real: true, source: safeSource(item.source), timestamp: finite(item.timestamp, 0) }
  var fields = ["x", "y", "pressure", "tiltX", "tiltY", "distance", "rotation"]
  for (var i = 0; i < fields.length; i++) {
    var name = fields[i]
    var accepted = name === "x" || name === "y" || name === "pressure" && supported.pressure || (name === "tiltX" || name === "tiltY") && supported.tilt || name === "distance" && supported.distance || name === "rotation" && supported.rotation
    if (accepted && isFinite(Number(item[name]))) {
      var value = Number(item[name])
      if (name === "pressure") value = clamp(value, 0, 1, 0)
      else if (name === "tiltX" || name === "tiltY") value = clamp(value, -1, 1, 0)
      else if (name === "distance") value = Math.max(0, value)
      else if (name === "rotation") value = clamp(value, 0, 360, 0)
      result[name] = round(value)
    }
  }
  if (supported.proximity && item.proximity !== undefined) result.proximity = bool(item.proximity)
  if (supported.eraser && item.eraser !== undefined) result.eraser = bool(item.eraser)
  if (supported.buttons && isFinite(Number(item.buttons))) result.buttons = Math.max(0, Math.min(32, Math.floor(Number(item.buttons))))
  return result
}

function emptyStylusState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    kind: "stylus",
    phase: "idle",
    deviceId: "",
    samples: [],
    supported: {},
    observed: {},
    analysis: null,
    realSamplesOnly: true,
    error: ""
  }
}

function beginStylus(deviceId, capabilities) {
  var device = safeId(deviceId)
  var supported = supportedCapabilities("stylus", capabilities)
  if (!device || supported.coordinate !== true) {
    var unavailable = emptyStylusState()
    unavailable.phase = "unavailable"
    unavailable.deviceId = device
    unavailable.supported = supported
    unavailable.error = !device ? "invalid-device" : "stylus-capability-unavailable"
    return unavailable
  }
  var state = emptyStylusState()
  state.phase = "collecting"
  state.deviceId = device
  state.supported = supported
  return state
}

function pressureSuggestion(values) {
  var list = array(values).filter(function(value) { return isFinite(Number(value)) }).map(Number).sort(function(a, b) { return a - b })
  if (list.length < 3) return { curve: "linear", reason: "not-enough-pressure-samples", sampleCount: list.length }
  var median = list[Math.floor(list.length / 2)]
  if (median > 0.65) return { curve: "soft", reason: "most-pressure-values-are-high", sampleCount: list.length }
  if (median < 0.30) return { curve: "firm", reason: "most-pressure-values-are-low", sampleCount: list.length }
  return { curve: "linear", reason: "balanced-pressure-range", sampleCount: list.length }
}

function stylusAnalysis(samples, supported) {
  var list = array(samples)
  var observed = {}
  var numeric = ["pressure", "tiltX", "tiltY", "distance", "rotation"]
  for (var i = 0; i < numeric.length; i++) observed[numeric[i]] = list.some(function(row) { return row[numeric[i]] !== undefined })
  observed.proximity = list.some(function(row) { return row.proximity !== undefined })
  observed.eraser = list.some(function(row) { return row.eraser !== undefined })
  observed.buttons = list.some(function(row) { return row.buttons !== undefined })
  var pressures = list.map(function(row) { return row.pressure }).filter(function(value) { return value !== undefined })
  var pressure = pressureSuggestion(pressures)
  return {
    sampleCount: list.length,
    supported: clone(supported),
    observed: observed,
    pressure: pressure,
    defaultCurve: "linear",
    nativeInterference: false,
    realSamplesOnly: true
  }
}

function recordStylusSample(previous, sample) {
  var old = Object.assign(emptyStylusState(), object(previous))
  if (old.phase !== "collecting") return { accepted: false, reason: "stylus-calibration-not-collecting", state: old }
  if (object(sample).real !== true || object(sample).synthetic === true || safeSource(object(sample).source) === "fixture") return { accepted: false, reason: "real-sample-required", state: old }
  if (old.samples.length >= MAX_STYLUS_SAMPLES) return { accepted: false, reason: "sample-limit", state: old }
  var normalized = normalizeStylusSample(sample, old.supported)
  if (Object.keys(normalized).length <= 3) return { accepted: false, reason: "no-supported-sample-fields", state: old }
  var samples = old.samples.concat([normalized])
  var next = Object.assign({}, old, { samples: samples, observed: stylusAnalysis(samples, old.supported).observed, analysis: stylusAnalysis(samples, old.supported), error: "" })
  return { accepted: true, reason: "sample-recorded", state: next }
}

function cancelStylusCalibration(previous, reason) {
  var old = Object.assign(emptyStylusState(), object(previous))
  old.phase = "cancelled"
  old.error = string(reason || "calibration-cancelled")
  old.analysis = null
  return old
}

function curvePoints(preset, custom) {
  var name = token(preset || "linear")
  if (name === "linear") return [{ x: 0, y: 0 }, { x: 1, y: 1 }]
  if (name === "soft") return [{ x: 0, y: 0 }, { x: 0.25, y: 0.50 }, { x: 0.65, y: 0.82 }, { x: 1, y: 1 }]
  if (name === "firm") return [{ x: 0, y: 0 }, { x: 0.35, y: 0.16 }, { x: 0.75, y: 0.58 }, { x: 1, y: 1 }]
  var points = array(custom).slice(0, 16).map(function(row) { return { x: clamp(row && row.x, 0, 1, 0), y: clamp(row && row.y, 0, 1, 0) } })
  if (points.length < 2) return curvePoints("linear")
  points.sort(function(a, b) { return a.x - b.x })
  var result = []
  var lastY = 0
  for (var i = 0; i < points.length; i++) {
    var point = { x: round(points[i].x), y: round(Math.max(lastY, points[i].y)) }
    if (i === 0) point.x = 0
    if (i === points.length - 1) { point.x = 1; point.y = 1 }
    result.push(point)
    lastY = point.y
  }
  return result
}

function safeMapping(value) {
  var source = object(value)
  var outputId = safeId(source.outputId || source.output_id)
  var rotation = Math.round(finite(source.rotation, 0))
  var scale = object(source.scale)
  var offset = object(source.offset)
  var scaleX = finite(scale.x, finite(source.scaleX, 1))
  var scaleY = finite(scale.y, finite(source.scaleY, 1))
  var offsetX = finite(offset.x, finite(source.offsetX, 0))
  var offsetY = finite(offset.y, finite(source.offsetY, 0))
  if ((outputId && !SAFE_ID.test(outputId)) || rotation % 90 !== 0 || rotation < 0 || rotation > 270 || scaleX < 0.5 || scaleX > 2 || scaleY < 0.5 || scaleY > 2 || Math.abs(offsetX) > 0.5 || Math.abs(offsetY) > 0.5) return null
  return {
    outputId: outputId,
    offset: { x: round(offsetX), y: round(offsetY) },
    scale: { x: round(scaleX), y: round(scaleY) },
    rotation: rotation,
    axis: { swapped: bool(object(source.axis).swapped), invertX: bool(object(source.axis).invertX), invertY: bool(object(source.axis).invertY) }
  }
}

function transactionConfirmation(kind) {
  var name = token(kind)
  if (name === "keyboard") return { kind: "keyboard", instruction: "Press the requested confirmation key", nonExecuting: true }
  if (name === "mouse") return { kind: "mouse", instruction: "Move and click the confirmation control", nonExecuting: true }
  if (name === "stylus") return { kind: "stylus", instruction: "Draw a short real test stroke", nonExecuting: true }
  return { kind: "touchscreen", instruction: "Touch the confirmation target", nonExecuting: true }
}

function emptyTransaction() {
  return {
    schemaVersion: SCHEMA_VERSION,
    phase: "idle",
    kind: "",
    targetId: "",
    previous: null,
    requested: null,
    startedAt: 0,
    deadline: 0,
    remainingMs: 0,
    confirmationRequired: false,
    confirmation: null,
    rollbackAvailable: false,
    error: ""
  }
}

function prepareTransaction(kind, targetId, previous, requested, now, options) {
  var state = emptyTransaction()
  var device = safeId(targetId)
  var desired = safeMapping(requested)
  var old = requested && requested.mapping ? safeMapping(requested.mapping) : safeMapping(previous)
  if (!device || (requested && desired === null) || (previous && old === null)) {
    state.phase = "rejected"
    state.kind = token(kind)
    state.targetId = device
    state.error = "unsafe-calibration-mapping"
    return state
  }
  var settings = object(options)
  var timestamp = finite(now, 0)
  var countdown = clamp(settings.countdownMs, 1000, 15000, 8000)
  state.phase = "prepared"
  state.kind = token(kind) || "touchscreen"
  state.targetId = device
  state.previous = old || (previous && clone(previous)) || null
  state.requested = desired || (requested && clone(requested)) || null
  state.startedAt = timestamp
  state.deadline = timestamp + countdown
  state.remainingMs = countdown
  state.confirmationRequired = true
  state.confirmation = transactionConfirmation(state.kind)
  state.rollbackAvailable = true
  return state
}

function applyTransaction(previous, applied, now, error) {
  var old = Object.assign(emptyTransaction(), object(previous))
  if (old.phase !== "prepared") return old
  if (applied !== true) {
    old.phase = "rollback-required"
    old.error = string(error || "calibration-apply-failed")
    return old
  }
  var timestamp = finite(now, old.startedAt)
  old.phase = "awaiting-confirmation"
  old.appliedAt = timestamp
  old.remainingMs = Math.max(0, old.deadline - timestamp)
  return old
}

function confirmTransaction(previous, confirmed, now) {
  var old = Object.assign(emptyTransaction(), object(previous))
  if (old.phase !== "awaiting-confirmation") return old
  if (confirmed !== true) return rollbackTransaction(old, "confirmation-rejected")
  old.phase = "committed"
  old.confirmedAt = finite(now, old.appliedAt)
  old.remainingMs = 0
  old.rollbackAvailable = false
  old.confirmationRequired = false
  old.error = ""
  return old
}

function rollbackTransaction(previous, reason) {
  var old = Object.assign(emptyTransaction(), object(previous))
  old.phase = "rolled-back"
  old.requested = old.previous ? clone(old.previous) : null
  old.remainingMs = 0
  old.rollbackAvailable = false
  old.confirmationRequired = false
  old.error = string(reason || "calibration-rolled-back")
  return old
}

function tickTransaction(previous, now) {
  var old = Object.assign(emptyTransaction(), object(previous))
  if (old.phase !== "awaiting-confirmation") return old
  var timestamp = finite(now, old.appliedAt)
  old.remainingMs = Math.max(0, old.deadline - timestamp)
  if (old.remainingMs === 0) return rollbackTransaction(old, "confirmation-timeout")
  return old
}

function disconnectTransaction(previous) {
  var old = Object.assign(emptyTransaction(), object(previous))
  if (["prepared", "awaiting-confirmation", "rollback-required"].indexOf(old.phase) < 0) return old
  return rollbackTransaction(old, "device-disconnected")
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  TOUCH_TARGETS: touchTargets,
  PRESSURE_CURVES: PRESSURE_CURVES,
  safeId: safeId,
  supportedCapabilities: supportedCapabilities,
  emptyTouchState: emptyTouchState,
  beginTouch: beginTouch,
  solveTouch: solveTouch,
  recordTouchSample: recordTouchSample,
  cancelCalibration: cancelCalibration,
  emptyStylusState: emptyStylusState,
  beginStylus: beginStylus,
  recordStylusSample: recordStylusSample,
  cancelStylusCalibration: cancelStylusCalibration,
  pressureSuggestion: pressureSuggestion,
  stylusAnalysis: stylusAnalysis,
  curvePoints: curvePoints,
  safeMapping: safeMapping,
  emptyTransaction: emptyTransaction,
  prepareTransaction: prepareTransaction,
  applyTransaction: applyTransaction,
  confirmTransaction: confirmTransaction,
  rollbackTransaction: rollbackTransaction,
  tickTransaction: tickTransaction,
  disconnectTransaction: disconnectTransaction
}
if (typeof module !== "undefined") module.exports = api
