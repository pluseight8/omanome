// Local state for Calibration Center and multi-monitor mapping.
//
// This model deliberately has no compositor/process calls. It turns a
// sanitized Device Graph into explicit UI choices and never resolves an
// ambiguous display from a name alone.

var SCHEMA_VERSION = 1
var SAFE_ID = /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/
var INPUT_CATEGORIES = ["touchscreen", "stylus", "tablet-pad", "keyboard", "mouse", "touchpad"]
var CALIBRATION_CATEGORIES = ["touchscreen", "stylus"]

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function safeId(value) {
  var id = string(value).trim()
  return SAFE_ID.test(id) ? id : ""
}

function safeLabel(value, fallback) {
  var text = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!text || text.length > 96 || /[\\/\n\r]/.test(text)) return fallback
  return text
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function capabilities(node) {
  var source = object(node)
  var raw = object(source.capabilities)
  var result = []
  for (var key in raw) if (raw[key] === true && result.indexOf(key) < 0) result.push(key)
  return result.sort()
}

function outputRows(graph) {
  var source = object(graph)
  var outputs = array(source.outputs)
  var result = []
  var seen = {}
  for (var i = 0; i < outputs.length; i++) {
    var output = object(outputs[i])
    var id = safeId(output.id)
    if (!id || seen[id]) continue
    seen[id] = true
    result.push({
      id: id,
      number: result.length + 1,
      name: safeLabel(output.name, "Display " + String(result.length + 1)),
      label: "Display " + String(result.length + 1),
      role: token(output.role) || "unknown",
      connected: output.connected !== false,
      geometry: object(output.geometry),
      scale: Number(output.scale || 1),
      orientation: token(output.orientation || "normal") || "normal"
    })
  }
  return result
}

function inputRows(graph) {
  var source = object(graph)
  var nodes = array(source.nodes)
  var result = []
  var seen = {}
  for (var i = 0; i < nodes.length; i++) {
    var node = object(nodes[i])
    var id = safeId(node.id)
    var category = token(node.category)
    if (!id || INPUT_CATEGORIES.indexOf(category) < 0 || seen[id]) continue
    seen[id] = true
    result.push({
      id: id,
      label: safeLabel(node.label, category),
      category: category,
      connected: node.connected === true,
      transport: token(node.transport) || "unknown",
      capabilities: capabilities(node),
      mappedOutput: safeId(node.mappedOutput),
      confidence: token(node.confidence) || "unknown"
    })
  }
  return result
}

function calibrationRows(graph, profiles) {
  var rows = inputRows(graph)
  var configured = object(profiles)
  return rows.filter(function(row) { return CALIBRATION_CATEGORIES.indexOf(row.category) >= 0 }).map(function(row) {
    var profile = object(configured[row.id])
    var supported = {}
    for (var i = 0; i < row.capabilities.length; i++) supported[row.capabilities[i]] = true
    return {
      id: row.id,
      label: row.label,
      category: row.category,
      connected: row.connected,
      transport: row.transport,
      mappedOutput: row.mappedOutput,
      confidence: row.confidence,
      supported: supported,
      configured: Object.keys(profile).length > 0,
      calibrationId: row.category === "touchscreen" ? String(object(profile.touch).calibrationId || "") : String(object(profile.stylus).calibrationId || "")
    }
  })
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    phase: "idle",
    step: "select-input",
    inputs: [],
    outputs: [],
    selectedInputId: "",
    selectedOutputId: "",
    identifiedOutputId: "",
    identifiedBy: "",
    ambiguous: false,
    error: "",
    candidate: null
  }
}

function beginMapping(graph) {
  var state = emptyState()
  state.inputs = inputRows(graph)
  state.outputs = outputRows(graph)
  if (state.inputs.length === 0) { state.phase = "unavailable"; state.error = "no-mappable-input-devices" }
  else if (state.outputs.length === 0) { state.phase = "unavailable"; state.error = "no-display-output" }
  else state.phase = "select-input"
  return state
}

function selectInput(previous, id) {
  var old = Object.assign(emptyState(), object(previous))
  var selected = safeId(id)
  var row = old.inputs.find ? old.inputs.find(function(item) { return item.id === selected }) : null
  if (!row) {
    for (var i = 0; i < old.inputs.length; i++) if (old.inputs[i].id === selected) { row = old.inputs[i]; break }
  }
  if (!row) { old.error = "input-not-found"; return old }
  old.selectedInputId = row.id
  old.selectedOutputId = ""
  old.identifiedOutputId = ""
  old.identifiedBy = ""
  old.ambiguous = false
  old.candidate = null
  old.phase = "select-output"
  old.step = "select-output"
  old.error = ""
  return old
}

function selectOutput(previous, id) {
  var old = Object.assign(emptyState(), object(previous))
  var selected = safeId(id)
  var row = null
  for (var i = 0; i < old.outputs.length; i++) if (old.outputs[i].id === selected) { row = old.outputs[i]; break }
  if (!row) { old.error = "display-not-found"; return old }
  old.selectedOutputId = row.id
  old.identifiedOutputId = ""
  old.identifiedBy = ""
  old.ambiguous = false
  old.candidate = null
  old.phase = "identify-output"
  old.step = "identify-output"
  old.error = ""
  return old
}

function selectOutputByName(previous, name) {
  var old = Object.assign(emptyState(), object(previous))
  var wanted = safeLabel(name, "")
  var matches = old.outputs.filter(function(output) { return output.name === wanted })
  if (matches.length !== 1) {
    old.phase = "ambiguous"
    old.step = "select-output"
    old.ambiguous = matches.length > 1
    old.error = matches.length > 1 ? "identical-display-names" : "display-not-found"
    return old
  }
  return selectOutput(old, matches[0].id)
}

function identifyOutput(previous, observedId, method) {
  var old = Object.assign(emptyState(), object(previous))
  if (old.phase !== "identify-output") { old.error = "output-identification-not-ready"; return old }
  var observed = safeId(observedId)
  var kind = token(method || "number")
  if (["number", "touch", "touch-to-identify", "pointer", "keyboard"].indexOf(kind) < 0) { old.error = "unsupported-identification-method"; return old }
  var exists = old.outputs.some(function(output) { return output.id === observed })
  if (!exists) { old.error = "identified-display-not-found"; return old }
  if (observed !== old.selectedOutputId) {
    old.phase = "ambiguous"
    old.step = "select-output"
    old.ambiguous = true
    old.error = "identified-different-display"
    old.candidate = { outputId: observed, method: kind, confidence: "unknown" }
    return old
  }
  old.identifiedOutputId = observed
  old.identifiedBy = kind
  old.phase = "confirm"
  old.step = "confirm"
  old.ambiguous = false
  old.error = ""
  old.candidate = { deviceId: old.selectedInputId, outputId: observed, confidence: "confirmed", source: "user-identify", method: kind }
  return old
}

function confirm(previous) {
  var old = Object.assign(emptyState(), object(previous))
  if (old.phase !== "confirm" || !safeId(old.selectedInputId) || !safeId(old.identifiedOutputId)) { old.error = "mapping-confirmation-not-ready"; return old }
  old.phase = "complete"
  old.step = "complete"
  old.candidate = { deviceId: old.selectedInputId, outputId: old.identifiedOutputId, confidence: "confirmed", source: "user-identify", method: old.identifiedBy || "number" }
  old.error = ""
  return old
}

function cancel(previous, reason) {
  var old = Object.assign(emptyState(), object(previous))
  old.phase = "cancelled"
  old.step = "select-input"
  old.error = string(reason || "mapping-cancelled")
  old.selectedInputId = ""
  old.selectedOutputId = ""
  old.identifiedOutputId = ""
  old.candidate = null
  return old
}

function centerRows(graph, profileStore) {
  var source = object(graph)
  var profiles = object(profileStore && (profileStore.profiles || profileStore))
  var rows = inputRows(graph)
  return rows.map(function(row) {
    return {
      id: row.id,
      label: row.label,
      category: row.category,
      connection: row.transport,
      connected: row.connected,
      mappedOutput: row.mappedOutput,
      status: row.connected ? "ready" : "disconnected",
      advanced: true,
      configured: !!profiles[row.id],
      capabilities: row.capabilities
    }
  }).concat(outputRows(source).map(function(output) {
    return {
      id: output.id,
      label: output.name,
      category: "display",
      connection: "display",
      connected: output.connected,
      mappedOutput: output.id,
      status: output.connected ? "ready" : "disconnected",
      advanced: true,
      configured: !!profiles[output.id],
      capabilities: ["display"]
    }
  }))
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  INPUT_CATEGORIES: INPUT_CATEGORIES,
  emptyState: emptyState,
  inputs: inputRows,
  outputs: outputRows,
  calibrationRows: calibrationRows,
  beginMapping: beginMapping,
  selectInput: selectInput,
  selectOutput: selectOutput,
  selectOutputByName: selectOutputByName,
  identifyOutput: identifyOutput,
  confirm: confirm,
  cancel: cancel,
  centerRows: centerRows
}
if (typeof module !== "undefined") module.exports = api
