// Device Profiles 2.0.
//
// These profiles are intentionally separate from Adaptive profiles. Adaptive
// chooses a runtime UI mode; a device profile stores only user preferences for
// one stable Device Graph node. The whitelist below is the complete public
// surface, so a profile can never become an arbitrary compositor configuration.

var SCHEMA_VERSION = 2
var CALIBRATION_SCHEMA_VERSION = 1
var CATEGORIES = ["display", "touchscreen", "stylus", "tablet-pad", "keyboard", "mouse", "touchpad", "gamepad", "sensor", "dock", "battery", "audio"]
var GRAPH_ID = /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/
var MAX_PROFILES = 256
var MAX_RULES = 128
var MAX_CALIBRATIONS = 256
var SURFACE_VALUES = ["auto", "primary", "follow-output", "disabled"]
var OSK_TARGETS = ["focused-display", "primary-touch", "ask", "disabled"]
var RELATIONS = ["auto", "paired", "separate", "none"]
var ADAPTIVE_ROLES = ["auto", "primary", "secondary", "drawing", "presentation", "none"]
var ORIENTATIONS = ["auto", "normal", "90", "180", "270"]
var PRESSURE_CURVES = ["linear", "soft", "firm"]
var KEYBOARD_OSK_POLICIES = ["auto", "show", "hide", "ask"]
var KEYBOARD_RELATIONS = ["auto", "built-in", "detachable", "docked", "external", "unknown"]
var GESTURE_PROFILES = ["auto", "tablet", "desktop", "drawing", "disabled"]
var EDGE_SENSITIVITY = ["auto", "low", "medium", "high"]
var PALM_POLICIES = ["auto", "enabled", "disabled"]
var HANDEDNESS = ["auto", "left", "right"]
var CURSOR_POLICIES = ["auto", "show", "hide"]
var HANDWRITING_POLICIES = ["auto", "enabled", "disabled"]
var BUTTON_ACTIONS = ["none", "left-click", "right-click", "middle-click", "annotation", "eraser", "back", "overview", "workspace"]
var CALIBRATION_KINDS = ["touchscreen", "stylus"]
var CALIBRATION_STATUS = ["last-known-good", "confirmed"]

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function bool(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback === undefined ? false : fallback
  var normalized = string(value).toLowerCase()
  return value === true || value === 1 || normalized === "true" || normalized === "yes" || normalized === "1"
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function allowed(value, values, fallback) {
  var name = token(value)
  return values.indexOf(name) >= 0 ? name : fallback
}

function safeId(value) {
  var id = string(value).trim()
  return GRAPH_ID.test(id) ? id : ""
}

function safeName(value, fallback) {
  var result = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!result || result.length > 64 || /[\\/\n\r]/.test(result)) return fallback || ""
  return result
}

function category(value, fallback) {
  var name = token(value)
  return CATEGORIES.indexOf(name) >= 0 ? name : (fallback || "unknown")
}

function categoryFromId(id) {
  var value = safeId(id)
  if (value.indexOf("device:") !== 0) return "display"
  var parts = value.split(":")
  return category(parts[1], "unknown")
}

function defaultDisplay() {
  return {
    surfaces: { dock: "auto", overview: "auto", launcher: "auto", notifications: "auto", osk: "auto" },
    dock: "auto",
    oskTarget: "focused-display",
    touchStylusRelation: "auto",
    adaptiveRole: "auto",
    orientation: "auto"
  }
}

function defaultTouch() {
  return { enabled: true, mappingOutput: "auto", calibrationId: "", orientation: "auto", gestureProfile: "auto", edgeSensitivity: "auto", palmPolicy: "auto" }
}

function defaultStylus() {
  return { enabled: true, mappingOutput: "auto", calibrationId: "", pressureCurve: "linear", pressureMin: 0, pressureMax: 1, tiltEnabled: true, eraserEnabled: true, handedness: "auto", cursor: "auto", palmRejection: "auto", handwriting: "auto", buttonMap: { primary: "right-click", secondary: "middle-click", tertiary: "annotation", eraser: "eraser" }, buttonTest: false }
}

function defaultKeyboard() {
  return { enabled: true, layout: "auto", oskPolicy: "auto", adaptiveRole: "auto", relation: "auto" }
}

function defaultsFor(categoryName) {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: "",
    category: category(categoryName, "unknown"),
    name: "",
    enabled: true,
    display: defaultDisplay(),
    touch: defaultTouch(),
    stylus: defaultStylus(),
    keyboard: defaultKeyboard()
  }
}

function normalizeSurfaces(value) {
  var source = object(value)
  var result = {}
  var names = ["dock", "overview", "launcher", "notifications", "osk"]
  for (var i = 0; i < names.length; i++) result[names[i]] = allowed(source[names[i]], SURFACE_VALUES, "auto")
  return result
}

function normalizeCalibrationId(value) {
  var id = string(value).trim()
  if (!id || id === "auto" || id === "none") return ""
  return /^[a-zA-Z0-9_.:-]{1,80}$/.test(id) && !/event[0-9]+|\/dev\//i.test(id) ? id : ""
}

function safeNumber(value, fallback, minimum, maximum) {
  var result = Number(value)
  if (!isFinite(result)) result = fallback
  return Math.max(minimum, Math.min(maximum, result))
}

function normalizeButtonMap(value) {
  var source = object(value)
  var result = { primary: "right-click", secondary: "middle-click", tertiary: "annotation", eraser: "eraser" }
  var keys = Object.keys(result)
  for (var i = 0; i < keys.length; i++) result[keys[i]] = allowed(source[keys[i]], BUTTON_ACTIONS, result[keys[i]])
  return result
}

function normalizeCalibrationMapping(value) {
  var source = object(value)
  var outputId = safeId(source.outputId || source.output_id)
  var scale = object(source.scale)
  var offset = object(source.offset)
  var rotation = Math.round(Number(source.rotation))
  if ([0, 90, 180, 270].indexOf(rotation) < 0) rotation = 0
  var result = {
    outputId: outputId,
    offset: { x: safeNumber(offset.x, safeNumber(source.offsetX, 0, -0.5, 0.5), -0.5, 0.5), y: safeNumber(offset.y, safeNumber(source.offsetY, 0, -0.5, 0.5), -0.5, 0.5) },
    scale: { x: safeNumber(scale.x, safeNumber(source.scaleX, 1, 0.5, 2), 0.5, 2), y: safeNumber(scale.y, safeNumber(source.scaleY, 1, 0.5, 2), 0.5, 2) },
    rotation: rotation,
    axis: { swapped: bool(object(source.axis).swapped), invertX: bool(object(source.axis).invertX), invertY: bool(object(source.axis).invertY) }
  }
  return outputId ? result : null
}

function normalizeCalibrationEntry(raw, expectedId) {
  var source = object(raw)
  var id = normalizeCalibrationId(expectedId || source.id)
  var deviceId = safeId(source.deviceId || source.device_id)
  var kind = allowed(source.kind || source.category, CALIBRATION_KINDS, "")
  var mapping = normalizeCalibrationMapping(source.mapping || source)
  if (!id || !deviceId || !kind || !mapping) return null
  return {
    schemaVersion: CALIBRATION_SCHEMA_VERSION,
    id: id,
    kind: kind,
    deviceId: deviceId,
    outputId: mapping.outputId,
    mapping: mapping,
    status: allowed(source.status, CALIBRATION_STATUS, "last-known-good"),
    revision: Math.max(0, Math.floor(Number(source.revision) || 0)),
    updatedAt: Math.max(0, Math.floor(Number(source.updatedAt || source.updated_at) || 0))
  }
}

function normalizeProfile(raw, expectedId) {
  var source = object(raw)
  var id = safeId(expectedId || source.id)
  if (!id) return null
  var inferredCategory = categoryFromId(id)
  var result = defaultsFor(category(source.category, inferredCategory))
  result.id = id
  result.category = category(source.category, inferredCategory)
  result.schemaVersion = SCHEMA_VERSION
  result.name = safeName(source.name || source.label, "")
  result.enabled = bool(source.enabled, true)

  var display = object(source.display)
  result.display.surfaces = normalizeSurfaces(display.surfaces)
  result.display.dock = allowed(display.dock, SURFACE_VALUES, "auto")
  result.display.oskTarget = allowed(display.oskTarget, OSK_TARGETS, "focused-display")
  result.display.touchStylusRelation = allowed(display.touchStylusRelation || display.touch_stylus_relation, RELATIONS, "auto")
  result.display.adaptiveRole = allowed(display.adaptiveRole || display.adaptive_role, ADAPTIVE_ROLES, "auto")
  result.display.orientation = allowed(display.orientation, ORIENTATIONS, "auto")

  var touch = object(source.touch)
  result.touch.enabled = bool(touch.enabled, true)
  result.touch.mappingOutput = safeId(touch.mappingOutput || touch.mapping_output) || (token(touch.mappingOutput || touch.mapping_output) === "auto" ? "auto" : "")
  result.touch.calibrationId = normalizeCalibrationId(touch.calibrationId || touch.calibration_id)
  result.touch.orientation = allowed(touch.orientation, ORIENTATIONS, "auto")
  result.touch.gestureProfile = allowed(touch.gestureProfile || touch.gesture_profile, GESTURE_PROFILES, "auto")
  result.touch.edgeSensitivity = allowed(touch.edgeSensitivity || touch.edge_sensitivity, EDGE_SENSITIVITY, "auto")
  result.touch.palmPolicy = allowed(touch.palmPolicy || touch.palm_policy, PALM_POLICIES, "auto")

  var stylus = object(source.stylus)
  result.stylus.enabled = bool(stylus.enabled, true)
  result.stylus.mappingOutput = safeId(stylus.mappingOutput || stylus.mapping_output) || (token(stylus.mappingOutput || stylus.mapping_output) === "auto" ? "auto" : "")
  result.stylus.calibrationId = normalizeCalibrationId(stylus.calibrationId || stylus.calibration_id)
  result.stylus.pressureCurve = allowed(stylus.pressureCurve || stylus.pressure_curve, PRESSURE_CURVES, "linear")
  var pressureMin = Number(stylus.pressureMin)
  var pressureMax = Number(stylus.pressureMax)
  if (!isFinite(pressureMin)) pressureMin = 0
  if (!isFinite(pressureMax)) pressureMax = 1
  result.stylus.pressureMin = Math.max(0, Math.min(1, pressureMin))
  result.stylus.pressureMax = Math.max(result.stylus.pressureMin, Math.min(1, pressureMax))
  result.stylus.tiltEnabled = bool(stylus.tiltEnabled, true)
  result.stylus.eraserEnabled = bool(stylus.eraserEnabled, true)
  result.stylus.handedness = allowed(stylus.handedness, HANDEDNESS, "auto")
  result.stylus.cursor = allowed(stylus.cursor, CURSOR_POLICIES, "auto")
  result.stylus.palmRejection = allowed(stylus.palmRejection || stylus.palm_rejection, PALM_POLICIES, "auto")
  result.stylus.handwriting = allowed(stylus.handwriting, HANDWRITING_POLICIES, "auto")
  result.stylus.buttonMap = normalizeButtonMap(stylus.buttonMap || stylus.button_map)
  // A button test is always transient. Never persist a request to execute an
  // action; the UI can set this only for the current test interaction.
  result.stylus.buttonTest = false

  var keyboard = object(source.keyboard)
  result.keyboard.enabled = bool(keyboard.enabled, true)
  result.keyboard.layout = safeName(keyboard.layout, "auto") || "auto"
  result.keyboard.oskPolicy = allowed(keyboard.oskPolicy || keyboard.osk_policy, KEYBOARD_OSK_POLICIES, "auto")
  result.keyboard.adaptiveRole = allowed(keyboard.adaptiveRole || keyboard.adaptive_role, ADAPTIVE_ROLES, "auto")
  result.keyboard.relation = allowed(keyboard.relation, KEYBOARD_RELATIONS, "auto")
  return result
}

function normalizeRule(raw) {
  var source = object(raw)
  var match = object(source.match || source)
  var result = {
    enabled: bool(source.enabled, true),
    category: category(match.category, ""),
    transport: token(match.transport) || "",
    formFactorRole: allowed(match.formFactorRole || match.form_factor_role, ["built-in", "external", "detachable", "dock", "drawing", "portable", "convertible", "unknown"], ""),
    seat: /^[a-zA-Z0-9_.-]{1,48}$/.test(string(match.seat)) ? string(match.seat) : "",
    profileId: safeId(source.profileId || source.profile_id || source.templateId || source.template_id)
  }
  if (!result.category && !result.transport && !result.formFactorRole && !result.seat) return null
  if (!result.profileId) return null
  return result
}

function emptyCalibrationStore() {
  return { schemaVersion: CALIBRATION_SCHEMA_VERSION, entries: {}, revision: 0 }
}

function normalizeCalibrationStore(raw) {
  var source = object(raw)
  var result = emptyCalibrationStore()
  var entries = object(source.entries || source.calibrations)
  var count = 0
  for (var id in entries) {
    if (count >= MAX_CALIBRATIONS) break
    var entry = normalizeCalibrationEntry(entries[id], id)
    if (!entry) continue
    result.entries[entry.id] = entry
    count++
  }
  result.revision = Math.max(0, Math.floor(Number(source.revision) || 0))
  return result
}

function emptyStore() {
  return { schemaVersion: SCHEMA_VERSION, enabled: true, profiles: {}, rules: [], calibrations: emptyCalibrationStore(), revision: 0 }
}

function normalizeStore(raw) {
  var source = object(raw)
  var result = emptyStore()
  result.enabled = bool(source.enabled, true)
  var profiles = object(source.profiles || source.devices || source.entries)
  var profileCount = 0
  for (var id in profiles) {
    if (profileCount >= MAX_PROFILES) break
    var normalized = normalizeProfile(profiles[id], id)
    if (!normalized) continue
    result.profiles[normalized.id] = normalized
    profileCount++
  }
  var rules = array(source.rules)
  for (var i = 0; i < rules.length && result.rules.length < MAX_RULES; i++) {
    var rule = normalizeRule(rules[i])
    if (rule) result.rules.push(rule)
  }
  result.calibrations = normalizeCalibrationStore(source.calibrations)
  result.revision = Math.max(0, Math.floor(Number(source.revision) || 0))
  return result
}

function ruleScore(rule, node) {
  var source = object(rule)
  var item = object(node)
  if (source.enabled === false) return -1
  if (source.category && source.category !== category(item.category, "")) return -1
  if (source.transport && source.transport !== token(item.transport)) return -1
  if (source.formFactorRole && source.formFactorRole !== allowed(item.formFactorRole, ["built-in", "external", "detachable", "dock", "drawing", "portable", "convertible", "unknown"], "unknown")) return -1
  if (source.seat && source.seat !== string(item.seat)) return -1
  var score = 0
  if (source.category) score += 8
  if (source.transport) score += 4
  if (source.formFactorRole) score += 2
  if (source.seat) score += 1
  return score
}

function effective(node, store) {
  var item = object(node)
  var normalizedStore = normalizeStore(store)
  var id = safeId(item.id)
  var direct = id ? normalizedStore.profiles[id] : null
  if (direct) return { profile: clone(direct), source: "device", matchedRule: null }
  var best = null
  var bestScore = -1
  for (var i = 0; i < normalizedStore.rules.length; i++) {
    var score = ruleScore(normalizedStore.rules[i], item)
    if (score > bestScore) {
      best = normalizedStore.rules[i]
      bestScore = score
    }
  }
  if (best && normalizedStore.profiles[best.profileId]) return { profile: clone(normalizedStore.profiles[best.profileId]), source: "rule", matchedRule: clone(best) }
  var fallback = defaultsFor(category(item.category, "unknown"))
  fallback.id = id
  fallback.category = category(item.category, categoryFromId(id))
  return { profile: fallback, source: "default", matchedRule: null }
}

function setProfile(store, raw) {
  var result = normalizeStore(store)
  var profile = normalizeProfile(raw)
  if (!profile) return { ok: false, reason: "invalid-graph-id", store: result }
  if (!result.profiles[profile.id] && Object.keys(result.profiles).length >= MAX_PROFILES) return { ok: false, reason: "profile-limit", store: result }
  result.profiles[profile.id] = profile
  result.revision++
  return { ok: true, reason: "saved", store: result, profile: clone(profile) }
}

function calibrationIdFor(deviceId, kind) {
  var device = safeId(deviceId)
  var name = allowed(kind, CALIBRATION_KINDS, "")
  if (!device || !name) return ""
  // This ID is metadata only; it is deterministic, bounded, and contains no
  // raw hardware value. The graph ID itself remains the stable owner link.
  var hash = 2166136261
  var material = device + "|" + name
  for (var i = 0; i < material.length; i++) { hash ^= material.charCodeAt(i); hash = Math.imul(hash, 16777619) }
  return "calibration-" + name + "-" + (hash >>> 0).toString(16)
}

function setCalibration(store, raw) {
  var result = normalizeStore(store)
  var candidate = object(raw)
  if (!candidate.id) candidate = Object.assign({}, candidate, { id: calibrationIdFor(candidate.deviceId || candidate.device_id, candidate.kind || candidate.category) })
  var entry = normalizeCalibrationEntry(candidate)
  if (!entry) return { ok: false, reason: "invalid-calibration", store: result }
  if (!result.calibrations.entries[entry.id] && Object.keys(result.calibrations.entries).length >= MAX_CALIBRATIONS)
    return { ok: false, reason: "calibration-limit", store: result }
  entry.revision = Number(result.calibrations.revision || 0) + 1
  result.calibrations.entries[entry.id] = entry
  result.calibrations.revision = entry.revision
  result.revision++
  return { ok: true, reason: "calibration-saved", store: result, calibration: clone(entry) }
}

function calibrationFor(store, deviceId, kind) {
  var normalized = normalizeStore(store)
  var device = safeId(deviceId)
  var wanted = allowed(kind, CALIBRATION_KINDS, "")
  if (!device || !wanted) return null
  var entries = normalized.calibrations.entries
  for (var id in entries) if (entries[id].deviceId === device && entries[id].kind === wanted) return clone(entries[id])
  return null
}

function removeCalibration(store, id) {
  var result = normalizeStore(store)
  var safe = normalizeCalibrationId(id)
  if (!safe || !result.calibrations.entries[safe]) return { ok: false, reason: "calibration-not-found", store: result }
  delete result.calibrations.entries[safe]
  result.calibrations.revision++
  result.revision++
  return { ok: true, reason: "calibration-removed", store: result }
}

function removeCalibrationsForDevice(store, deviceId) {
  var result = normalizeStore(store)
  var safe = safeId(deviceId)
  if (!safe) return { ok: false, reason: "invalid-graph-id", store: result }
  var changed = false
  for (var id in result.calibrations.entries) {
    if (result.calibrations.entries[id].deviceId !== safe) continue
    delete result.calibrations.entries[id]
    changed = true
  }
  if (changed) { result.calibrations.revision++; result.revision++ }
  return { ok: true, reason: changed ? "calibrations-removed" : "no-calibration", store: result }
}

function rename(store, id, name) {
  var result = normalizeStore(store)
  var safe = safeId(id)
  if (!safe || !result.profiles[safe]) return { ok: false, reason: "profile-not-found", store: result }
  var nextName = safeName(name, "")
  if (!nextName) return { ok: false, reason: "invalid-name", store: result }
  result.profiles[safe].name = nextName
  result.revision++
  return { ok: true, reason: "renamed", store: result }
}

function forget(store, id) {
  var result = normalizeStore(store)
  var safe = safeId(id)
  if (!safe || !result.profiles[safe]) return { ok: false, reason: "profile-not-found", store: result }
  delete result.profiles[safe]
  result.rules = result.rules.filter(function(rule) { return rule.profileId !== safe })
  for (var calibrationId in result.calibrations.entries) if (result.calibrations.entries[calibrationId].deviceId === safe) delete result.calibrations.entries[calibrationId]
  result.calibrations.revision++
  result.revision++
  return { ok: true, reason: "forgotten", store: result }
}

function reset(store, id) {
  var result = normalizeStore(store)
  var safe = safeId(id)
  if (!safe || !result.profiles[safe]) return { ok: false, reason: "profile-not-found", store: result }
  delete result.profiles[safe]
  for (var calibrationId in result.calibrations.entries) if (result.calibrations.entries[calibrationId].deviceId === safe) delete result.calibrations.entries[calibrationId]
  result.calibrations.revision++
  result.revision++
  return { ok: true, reason: "reset", store: result }
}

function setRule(store, raw) {
  var result = normalizeStore(store)
  var rule = normalizeRule(raw)
  if (!rule) return { ok: false, reason: "invalid-rule", store: result }
  if (!result.profiles[rule.profileId]) return { ok: false, reason: "profile-not-found", store: result }
  if (result.rules.length >= MAX_RULES) return { ok: false, reason: "rule-limit", store: result }
  result.rules.push(rule)
  result.revision++
  return { ok: true, reason: "rule-saved", store: result }
}

function removeRule(store, index) {
  var result = normalizeStore(store)
  var position = Math.floor(Number(index))
  if (!isFinite(position) || position < 0 || position >= result.rules.length) return { ok: false, reason: "rule-not-found", store: result }
  result.rules.splice(position, 1)
  result.revision++
  return { ok: true, reason: "rule-removed", store: result }
}

function list(graph, store) {
  var source = object(graph)
  var nodes = array(source.nodes)
  var normalizedStore = normalizeStore(store)
  var result = []
  for (var i = 0; i < nodes.length; i++) {
    var node = object(nodes[i])
    var id = safeId(node.id)
    if (!id) continue
    var resolution = effective(node, normalizedStore)
    result.push({
      id: id,
      category: category(node.category, categoryFromId(id)),
      label: safeName(node.label, category(node.category, "device")),
      connected: node.connected === true,
      transport: token(node.transport) || "unknown",
      mappedOutput: safeId(node.mappedOutput),
      configured: !!normalizedStore.profiles[id],
      profile: resolution.profile,
      source: resolution.source
    })
  }
  return result
}

function summary(store) {
  var normalized = normalizeStore(store)
  var categories = {}
  for (var id in normalized.profiles) {
    var categoryName = normalized.profiles[id].category
    categories[categoryName] = Number(categories[categoryName] || 0) + 1
  }
  return { schemaVersion: SCHEMA_VERSION, enabled: normalized.enabled, profileCount: Object.keys(normalized.profiles).length, ruleCount: normalized.rules.length, calibrationCount: Object.keys(normalized.calibrations.entries).length, categories: categories, revision: normalized.revision }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  CATEGORIES: CATEGORIES,
  CALIBRATION_SCHEMA_VERSION: CALIBRATION_SCHEMA_VERSION,
  MAX_CALIBRATIONS: MAX_CALIBRATIONS,
  defaultsFor: defaultsFor,
  safeId: safeId,
  normalizeProfile: normalizeProfile,
  normalizeRule: normalizeRule,
  normalizeCalibrationEntry: normalizeCalibrationEntry,
  emptyCalibrationStore: emptyCalibrationStore,
  normalizeCalibrationStore: normalizeCalibrationStore,
  calibrationIdFor: calibrationIdFor,
  emptyStore: emptyStore,
  normalizeStore: normalizeStore,
  effective: effective,
  setProfile: setProfile,
  setCalibration: setCalibration,
  calibrationFor: calibrationFor,
  removeCalibration: removeCalibration,
  removeCalibrationsForDevice: removeCalibrationsForDevice,
  rename: rename,
  forget: forget,
  reset: reset,
  setRule: setRule,
  removeRule: removeRule,
  list: list,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
