// Hardware-facing policies built on top of the sanitized Device Graph.
//
// Display roles, OSK targeting, power policy, and setup presets are kept as
// explicit policy decisions. This module never identifies a monitor from its
// name, never guesses a touch-to-display relationship, and never executes a
// compositor or power command. It returns candidates and truthful reasons so
// the caller can show confirmation or an unavailable state.

var SCHEMA_VERSION = 1
var MAX_SETUP_PROFILES = 12
var MAX_DISPLAY_ROLES = 256
var MAX_SETUP_MATCHES = 32
var MAX_SETUP_DEVICES = 256
var MAX_SETUP_OUTPUTS = 32
var DISPLAY_ID = /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/
var DISPLAY_ROLES = ["auto", "internal", "external", "primary", "presentation", "unknown"]
var OSK_TARGETS = ["focused-display", "primary-touch", "ask", "disabled"]
var POWER_POLICIES = ["follow-system", "balanced", "performance", "power-saver"]
var DOCK_POLICIES = ["auto", "show", "hide", "follow-display"]
var ORIENTATIONS = ["auto", "normal", "90", "180", "270"]
var SURFACE_VALUES = ["auto", "primary", "follow-output", "disabled"]
var SETUP_IDS = ["auto", "tablet", "desk", "portable", "travel", "presentation", "drawing", "custom"]
var ADAPTIVE_PROFILES = ["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"]
var DOCK_TARGETS = ["auto", "active-display", "primary-display", "external-display", "disabled"]
var MATCH_MODES = ["ask", "auto-apply", "manual"]
var BATTERY_STATES = ["charging", "discharging", "fully-charged", "pending-charge", "unknown"]
var POWER_PROFILES = ["balanced", "performance", "power-saver", "unknown"]

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
  var name = string(value).toLowerCase()
  return value === true || value === 1 || name === "true" || name === "yes" || name === "1"
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function clamp(value, minimum, maximum, fallback) {
  return Math.max(minimum, Math.min(maximum, number(value, fallback)))
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function allowed(value, values, fallback) {
  var name = token(value)
  return values.indexOf(name) >= 0 ? name : fallback
}

function safeId(value) {
  var id = string(value).trim()
  return DISPLAY_ID.test(id) ? id : ""
}

function safeLabel(value, fallback) {
  var result = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!result || result.length > 96 || /[\\/\n\r]/.test(result) || /\/dev\/input\/event\d+/i.test(result) || /(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i.test(result)) return fallback
  return result
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function defaultDisplayPolicy() {
  return { schemaVersion: SCHEMA_VERSION, primaryDisplay: "", oskTarget: "focused-display", roles: {} }
}

function defaultSurfaces() {
  return { dock: "auto", overview: "auto", launcher: "auto", notifications: "auto", osk: "auto" }
}

function setupDefaults(id) {
  var name = SETUP_IDS.indexOf(token(id)) >= 0 ? token(id) : "auto"
  var preferred = name === "tablet" ? "tablet" : name === "desk" ? "desktop" : name === "portable" || name === "travel" ? "hybrid" : name === "presentation" ? "presentation" : name === "drawing" ? "tablet" : name === "custom" ? "custom" : "auto"
  var result = {
    id: name,
    label: name === "tablet" ? "Tablet" : name === "desk" ? "Desk" : name === "portable" ? "Portable" : name === "travel" ? "Travel" : name === "presentation" ? "Presentation" : name === "drawing" ? "Drawing" : name === "custom" ? "Custom" : "Automatic",
    preferredAdaptiveProfile: preferred,
    displayRole: name === "presentation" ? "presentation" : name === "desk" ? "external" : "auto",
    oskTarget: name === "drawing" ? "primary-touch" : name === "desk" || name === "presentation" ? "disabled" : "focused-display",
    dockTarget: name === "desk" || name === "presentation" ? "external-display" : "auto",
    powerPolicy: name === "travel" ? "power-saver" : "follow-system",
    dockPolicy: name === "presentation" ? "hide" : "auto",
    orientation: "auto",
    surfaces: defaultSurfaces(),
    inputMappings: {},
    deviceBehavior: {}
  }
  if (name === "tablet") result.surfaces.dock = "follow-output"
  if (name === "drawing") result.surfaces.osk = "primary"
  return result
}

function normalizeSurfaces(value) {
  var source = object(value)
  var result = defaultSurfaces()
  var names = Object.keys(result)
  for (var i = 0; i < names.length; i++) result[names[i]] = allowed(source[names[i]], SURFACE_VALUES, "auto")
  return result
}

function safeIdList(value, limit) {
  var list = array(value)
  var result = []
  var maximum = Math.max(0, Math.floor(Number(limit) || 0))
  for (var i = 0; i < list.length && result.length < maximum; i++) {
    var id = safeId(list[i])
    if (id && result.indexOf(id) < 0) result.push(id)
  }
  return result
}

function normalizeInputMappings(value) {
  var source = object(value)
  var result = {}
  var count = 0
  for (var deviceId in source) {
    if (count >= MAX_SETUP_DEVICES) break
    var device = safeId(deviceId)
    var output = safeId(source[deviceId])
    if (!device || !output) continue
    result[device] = output
    count++
  }
  return result
}

function normalizeDeviceBehavior(value) {
  var source = object(value)
  var result = {}
  var count = 0
  for (var deviceId in source) {
    if (count >= MAX_SETUP_DEVICES) break
    var device = safeId(deviceId)
    var policy = object(source[deviceId])
    if (!device) continue
    var row = {}
    if (policy.enabled !== undefined) row.enabled = bool(policy.enabled)
    if (policy.ignored !== undefined) row.ignored = bool(policy.ignored)
    if (policy.profileId !== undefined || policy.profile_id !== undefined) row.profileId = safeId(policy.profileId || policy.profile_id)
    if (policy.adaptiveRole !== undefined || policy.adaptive_role !== undefined) row.adaptiveRole = allowed(policy.adaptiveRole || policy.adaptive_role, ["auto", "primary", "secondary", "drawing", "presentation", "none"], "auto")
    if (policy.oskPolicy !== undefined || policy.osk_policy !== undefined) row.oskPolicy = allowed(policy.oskPolicy || policy.osk_policy, ["auto", "show", "hide", "ask"], "auto")
    result[device] = row
    count++
  }
  return result
}

function normalizeTopologyMatch(raw, expectedSetupId) {
  var source = object(raw)
  var setupId = token(expectedSetupId || source.setupId || source.setup_id)
  if (SETUP_IDS.indexOf(setupId) < 0) return null
  var required = object(source.required || source.requires)
  var devices = safeIdList(source.devices || source.deviceIds || required.devices || required.deviceIds, MAX_SETUP_DEVICES)
  var outputs = safeIdList(source.outputs || source.outputIds || required.outputs || required.outputIds, MAX_SETUP_OUTPUTS)
  var minimumDevicesValue = source.minimumDevices !== undefined ? source.minimumDevices : source.minimum_devices
  var minimumOutputsValue = source.minimumOutputs !== undefined ? source.minimumOutputs : source.minimum_outputs
  var minimumDevices = Math.max(0, Math.min(MAX_SETUP_DEVICES, Math.floor(number(minimumDevicesValue, devices.length))))
  var minimumOutputs = Math.max(0, Math.min(MAX_SETUP_OUTPUTS, Math.floor(number(minimumOutputsValue, outputs.length))))
  if (devices.length === 0 && outputs.length === 0 && minimumDevices === 0 && minimumOutputs === 0) return null
  return {
    schemaVersion: SCHEMA_VERSION,
    setupId: setupId,
    devices: devices,
    outputs: outputs,
    minimumDevices: minimumDevices,
    minimumOutputs: minimumOutputs,
    confidence: allowed(source.confidence, ["confirmed", "probable", "unknown"], "unknown"),
    source: "user"
  }
}

function normalizeMatchPolicy(value) {
  var source = object(value)
  return {
    schemaVersion: SCHEMA_VERSION,
    mode: allowed(source.mode, MATCH_MODES, "ask"),
    autoApply: bool(source.autoApply, false),
    promptOnce: source.promptOnce !== false
  }
}

function connectedIds(graph, field) {
  var source = object(graph)
  var rows = array(source[field])
  var result = {}
  for (var i = 0; i < rows.length; i++) {
    var id = safeId(rows[i] && rows[i].id)
    if (id && rows[i].connected !== false) result[id] = true
  }
  return result
}

function topologyMatch(graph, match) {
  var source = object(match)
  var devices = connectedIds(graph, "nodes")
  var outputs = connectedIds(graph, "outputs")
  var requiredDevices = safeIdList(source.devices, MAX_SETUP_DEVICES)
  var requiredOutputs = safeIdList(source.outputs, MAX_SETUP_OUTPUTS)
  var missingDevices = requiredDevices.filter(function(id) { return !devices[id] })
  var missingOutputs = requiredOutputs.filter(function(id) { return !outputs[id] })
  var deviceCount = Object.keys(devices).length
  var outputCount = Object.keys(outputs).length
  var minimumDevices = Math.max(requiredDevices.length, Math.floor(number(source.minimumDevices, requiredDevices.length)))
  var minimumOutputs = Math.max(requiredOutputs.length, Math.floor(number(source.minimumOutputs, requiredOutputs.length)))
  var complete = missingDevices.length === 0 && missingOutputs.length === 0 && deviceCount >= minimumDevices && outputCount >= minimumOutputs
  return {
    setupId: token(source.setupId),
    complete: complete,
    partial: !complete && (requiredDevices.length > 0 || requiredOutputs.length > 0),
    missingDevices: missingDevices,
    missingOutputs: missingOutputs,
    score: (requiredDevices.length - missingDevices.length) + (requiredOutputs.length - missingOutputs.length),
    confidence: allowed(source.confidence, ["confirmed", "probable", "unknown"], "unknown")
  }
}

function matchTopology(graph, store) {
  var normalized = normalizeStore(store)
  var candidates = []
  for (var i = 0; i < normalized.matches.length; i++) {
    var result = topologyMatch(graph, normalized.matches[i])
    result.source = "user"
    if (SETUP_IDS.indexOf(result.setupId) >= 0) candidates.push(result)
  }
  candidates.sort(function(a, b) { return Number(b.complete) - Number(a.complete) || b.score - a.score })
  var best = candidates.length > 0 ? candidates[0] : null
  return {
    status: best ? best.complete ? "matched" : "partial" : "unknown",
    setupId: best && best.complete ? best.setupId : "",
    suggestion: best && best.complete ? best.setupId : "",
    confidence: best ? best.confidence : "unknown",
    complete: best ? best.complete : false,
    partial: best ? best.partial : false,
    candidates: candidates.slice(0, MAX_SETUP_MATCHES)
  }
}

function normalizeDisplayPolicy(value) {
  var source = object(value)
  var result = defaultDisplayPolicy()
  result.primaryDisplay = safeId(source.primaryDisplay || source.primary_display)
  result.oskTarget = allowed(source.oskTarget || source.osk_target, OSK_TARGETS, result.oskTarget)
  var roles = object(source.roles)
  var count = 0
  for (var id in roles) {
    if (count >= MAX_DISPLAY_ROLES) break
    var safe = safeId(id)
    var role = allowed(roles[id], DISPLAY_ROLES, "")
    if (!safe || !role) continue
    result.roles[safe] = role
    count++
  }
  return result
}

function normalizeSetupProfile(raw, expectedId) {
  var source = object(raw)
  var id = token(expectedId || source.id)
  if (SETUP_IDS.indexOf(id) < 0) return null
  var result = setupDefaults(id)
  result.id = id
  result.label = safeLabel(source.label || source.name, result.label)
  result.preferredAdaptiveProfile = allowed(source.preferredAdaptiveProfile || source.preferred_adaptive_profile || source.adaptiveProfile || source.adaptive_profile, ADAPTIVE_PROFILES, result.preferredAdaptiveProfile)
  result.displayRole = allowed(source.displayRole || source.display_role, DISPLAY_ROLES, result.displayRole)
  result.oskTarget = allowed(source.oskTarget || source.osk_target, OSK_TARGETS, result.oskTarget)
  result.dockTarget = allowed(source.dockTarget || source.dock_target, DOCK_TARGETS, result.dockTarget)
  result.powerPolicy = allowed(source.powerPolicy || source.power_policy, POWER_POLICIES, result.powerPolicy)
  result.dockPolicy = allowed(source.dockPolicy || source.dock_policy, DOCK_POLICIES, result.dockPolicy)
  result.orientation = allowed(source.orientation, ORIENTATIONS, result.orientation)
  result.surfaces = normalizeSurfaces(source.surfaces)
  result.inputMappings = normalizeInputMappings(source.inputMappings || source.input_mappings)
  result.deviceBehavior = normalizeDeviceBehavior(source.deviceBehavior || source.device_behavior || source.devicePolicies || source.device_policies)
  return result
}

function emptyStore() {
  return { schemaVersion: SCHEMA_VERSION, selected: "auto", profiles: {}, displayPolicy: defaultDisplayPolicy(), matchPolicy: normalizeMatchPolicy({}), matches: [], revision: 0 }
}

function normalizeStore(raw) {
  var source = object(raw)
  var result = emptyStore()
  result.selected = SETUP_IDS.indexOf(token(source.selected || source.profile)) >= 0 ? token(source.selected || source.profile) : "auto"
  result.displayPolicy = normalizeDisplayPolicy(source.displayPolicy || source.display_policy)
  var profiles = object(source.profiles)
  var count = 0
  for (var id in profiles) {
    if (count >= MAX_SETUP_PROFILES) break
    var profile = normalizeSetupProfile(profiles[id], id)
    if (!profile) continue
    result.profiles[profile.id] = profile
    count++
  }
  result.matchPolicy = normalizeMatchPolicy(source.matchPolicy || source.match_policy)
  var matches = array(source.matches || source.topologyMatches || source.topology_matches)
  for (var m = 0; m < matches.length && result.matches.length < MAX_SETUP_MATCHES; m++) {
    var match = normalizeTopologyMatch(matches[m])
    if (match) result.matches.push(match)
  }
  result.revision = Math.max(0, Math.floor(number(source.revision, 0)))
  return result
}

function graphOutputs(graph) {
  var source = object(graph)
  var result = []
  var seen = {}
  var outputs = array(source.outputs)
  for (var i = 0; i < outputs.length; i++) {
    var output = object(outputs[i])
    var id = safeId(output.id)
    if (!id || seen[id]) continue
    seen[id] = true
    result.push({
      id: id,
      name: safeLabel(output.name || output.label, "Display " + String(result.length + 1)),
      role: allowed(output.role, DISPLAY_ROLES, "unknown"),
      confidence: allowed(output.confidence, ["confirmed", "probable", "unknown"], "unknown"),
      connected: output.connected !== false,
      geometry: object(output.geometry),
      scale: clamp(output.scale, 0.25, 8, 1),
      orientation: allowed(output.orientation, ORIENTATIONS, "auto")
    })
  }
  // A graph assembled by an older adapter may contain display nodes without
  // output records. They remain usable as an explicitly identified display,
  // but geometry/mapping stays unavailable until the output inventory arrives.
  var nodes = array(source.nodes)
  for (var n = 0; n < nodes.length; n++) {
    var node = object(nodes[n])
    if (safeCategory(node.category) !== "display") continue
    var nodeId = safeId(node.id)
    if (!nodeId || seen[nodeId]) continue
    seen[nodeId] = true
    result.push({ id: nodeId, name: safeLabel(node.label, "Display " + String(result.length + 1)), role: "unknown", confidence: "unknown", connected: node.connected === true, geometry: {}, scale: 1, orientation: "auto" })
  }
  return result
}

function safeCategory(value) {
  var name = token(value)
  return name === "monitor" || name === "output" ? "display" : name
}

function nodeById(graph, id) {
  var wanted = safeId(id)
  if (!wanted) return null
  var nodes = array(object(graph).nodes)
  for (var i = 0; i < nodes.length; i++) if (object(nodes[i]).id === wanted) return nodes[i]
  return null
}

function displayRows(graph, policy) {
  var settings = normalizeDisplayPolicy(policy)
  var outputs = graphOutputs(graph)
  var rows = []
  var primaryConfigured = safeId(settings.primaryDisplay)
  var primaryConnected = primaryConfigured !== "" && outputs.some(function(output) { return output.id === primaryConfigured && output.connected })
  var declaredPrimary = outputs.filter(function(output) { return output.role === "primary" && output.connected })
  var primaryId = primaryConnected ? primaryConfigured : declaredPrimary.length === 1 ? declaredPrimary[0].id : ""
  for (var i = 0; i < outputs.length; i++) {
    var output = outputs[i]
    var configuredRole = allowed(settings.roles[output.id], DISPLAY_ROLES, "")
    var baseRole = configuredRole && configuredRole !== "auto" ? configuredRole : output.role
    var role = baseRole || "unknown"
    var roleSource = configuredRole && configuredRole !== "auto" ? "user" : output.role !== "unknown" ? "compositor" : "unknown"
    var confidence = configuredRole && configuredRole !== "auto" ? "confirmed" : output.confidence
    if (output.id === primaryId) {
      role = "primary"
      roleSource = primaryConfigured === output.id ? "user" : "compositor"
      confidence = primaryConfigured === output.id ? "confirmed" : output.confidence
    }
    rows.push({
      id: output.id,
      name: output.name,
      role: role,
      baseRole: baseRole,
      roleSource: roleSource,
      confidence: confidence,
      connected: output.connected,
      geometry: output.geometry,
      scale: output.scale,
      orientation: output.orientation
    })
  }
  return { rows: rows, primaryDisplayId: primaryId, primaryDeclared: primaryId !== "", unknownCount: rows.filter(function(row) { return row.role === "unknown" && row.connected }).length }
}

function setDisplayRole(policy, id, role) {
  var result = normalizeDisplayPolicy(policy)
  var safe = safeId(id)
  var value = allowed(role, DISPLAY_ROLES, "")
  if (!safe || !value) return { ok: false, reason: "invalid-display-role", policy: result }
  if (value === "auto" || value === "unknown") delete result.roles[safe]
  else result.roles[safe] = value
  result.schemaVersion = SCHEMA_VERSION
  return { ok: true, reason: "display-role-saved", policy: result }
}

function resolveOskTarget(graph, input, policy, context) {
  var settings = normalizeDisplayPolicy(policy)
  var source = object(context)
  var requested = allowed(source.oskTarget || settings.oskTarget, OSK_TARGETS, "focused-display")
  var displays = displayRows(graph, settings)
  var connected = displays.rows.filter(function(row) { return row.connected })
  var inputNode = object(input)
  var mapped = safeId(inputNode.mappedOutput || inputNode.mappingOutput)
  var focused = safeId(source.focusedDisplayId || source.focused_display_id)
  var target = { requested: requested, status: "unavailable", outputId: "", reason: "no-verified-target", source: "none" }
  if (requested === "disabled") return { requested: requested, status: "disabled", outputId: "", reason: "policy-disabled", source: "policy" }
  if (requested === "ask") return { requested: requested, status: "ask", outputId: "", reason: "user-choice-required", source: "policy" }
  if (requested === "focused-display") {
    if (focused && connected.some(function(row) { return row.id === focused })) return { requested: requested, status: "resolved", outputId: focused, reason: "compositor-focus", source: "focused-display" }
    target.reason = "focused-display-unavailable"
  } else if (requested === "primary-touch") {
    if (mapped && connected.some(function(row) { return row.id === mapped })) return { requested: requested, status: "resolved", outputId: mapped, reason: "explicit-input-mapping", source: "device-profile" }
    if (displays.primaryDisplayId && connected.some(function(row) { return row.id === displays.primaryDisplayId })) {
      target.status = "resolved"
      target.outputId = displays.primaryDisplayId
      target.reason = "explicit-primary-display"
      target.source = "display-policy"
      return target
    }
    target.reason = "primary-touch-display-unavailable"
  }
  return target
}

function normalizePowerState(raw) {
  var source = object(raw)
  var state = allowed(source.batteryState || source.battery_state, BATTERY_STATES, "unknown")
  var profile = allowed(source.powerProfile || source.power_profile, POWER_PROFILES, "unknown")
  var percent = number(source.batteryPercent !== undefined ? source.batteryPercent : source.battery_percentage, -1)
  if (percent < 0 || percent > 100) percent = -1
  return {
    available: source.powerProfileAvailable === true || source.power_profile_available === true,
    batteryAvailable: source.batteryAvailable === true || source.battery_available === true || percent >= 0,
    batteryPercent: percent,
    batteryState: state,
    powerProfile: profile,
    onAc: source.onAc === true || source.on_ac === true || state === "charging" || state === "fully-charged",
    thermalPressure: allowed(source.thermalPressure || source.thermal_pressure, ["nominal", "fair", "serious", "critical", "unknown"], "unknown")
  }
}

function powerDecision(raw, setup, settings) {
  var power = normalizePowerState(raw)
  var profile = object(setup)
  var config = object(settings)
  var requested = allowed(profile.powerPolicy, POWER_POLICIES, "follow-system")
  var desired = requested === "follow-system" ? power.powerProfile === "unknown" ? "balanced" : power.powerProfile : requested
  var reason = requested === "follow-system" ? power.powerProfile === "unknown" ? "system-power-profile-unknown" : "follow-system" : "setup-profile"
  if (power.batteryState === "discharging" && power.batteryPercent >= 0 && power.batteryPercent <= clamp(config.criticalBatteryPercent, 5, 30, 15)) {
    desired = "power-saver"
    reason = "critical-battery"
  } else if (power.batteryState === "discharging" && desired === "performance" && config.disablePerformanceOnBattery !== false) {
    desired = "balanced"
    reason = "performance-disabled-on-battery"
  }
  return {
    available: power.available,
    requested: requested,
    desired: power.available ? desired : "",
    current: power.powerProfile,
    batteryAvailable: power.batteryAvailable,
    batteryPercent: power.batteryPercent,
    batteryState: power.batteryState,
    onAc: power.onAc,
    thermalPressure: power.thermalPressure,
    applyAllowed: power.available && desired !== "" && desired !== power.powerProfile,
    reason: power.available ? reason : "power-profile-backend-unavailable"
  }
}

function resolveSetup(graph, store, context) {
  var normalized = normalizeStore(store)
  var source = object(context)
  var requested = normalized.selected
  var mode = token(source.mode || "desktop")
  var matching = matchTopology(graph, normalized)
  var selected = requested
  var selectionSource = requested === "auto" ? "runtime-mode" : "user"
  if (selected === "auto") {
    if (matching.complete && (normalized.matchPolicy.autoApply === true || normalized.matchPolicy.mode === "auto-apply")) {
      selected = matching.setupId
      selectionSource = "topology-match"
    } else if (source.docked === true) selected = "desk"
    else if (mode === "tablet") selected = "tablet"
    else if (mode === "hybrid") selected = "travel"
    else if (mode === "presentation") selected = "presentation"
    else if (mode === "drawing") selected = "drawing"
    else selected = "desk"
  }
  var profile = normalized.profiles[selected] || setupDefaults(selected)
  var displays = displayRows(graph, normalized.displayPolicy)
  var primaryInput = nodeById(graph, source.primaryInputId)
  if (primaryInput && profile.inputMappings && profile.inputMappings[primaryInput.id]) primaryInput = Object.assign({}, primaryInput, { mappedOutput: profile.inputMappings[primaryInput.id] })
  var osk = resolveOskTarget(graph, primaryInput, normalized.displayPolicy, { oskTarget: profile.oskTarget, focusedDisplayId: source.focusedDisplayId })
  var power = powerDecision(source.system || source.power, profile, source)
  return {
    schemaVersion: SCHEMA_VERSION,
    selected: selected,
    requested: requested,
    source: selectionSource,
    profile: clone(profile),
    displays: displays,
    osk: osk,
    power: power,
    matching: matching,
    matchPolicy: normalized.matchPolicy,
    revision: normalized.revision,
    reason: selectionSource === "topology-match" ? "known-hardware-setup-matched" : osk.status === "unavailable" ? osk.reason : power.reason
  }
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    selected: "auto",
    source: "uninitialized",
    profile: setupDefaults("auto"),
    displays: { rows: [], primaryDisplayId: "", primaryDeclared: false, unknownCount: 0 },
    osk: { requested: "focused-display", status: "unavailable", outputId: "", reason: "no-device-graph", source: "none" },
    power: { available: false, requested: "follow-system", desired: "", current: "unknown", batteryAvailable: false, batteryPercent: -1, batteryState: "unknown", onAc: false, thermalPressure: "unknown", applyAllowed: false, reason: "no-power-state" },
    revision: 0,
    reason: "no-device-graph"
  }
}

function setSelected(store, id) {
  var result = normalizeStore(store)
  var selected = token(id)
  if (SETUP_IDS.indexOf(selected) < 0) return { ok: false, reason: "invalid-setup-profile", store: result }
  result.selected = selected
  result.revision++
  return { ok: true, reason: "setup-selected", store: result }
}

function setMatchPolicy(store, value) {
  var result = normalizeStore(store)
  result.matchPolicy = normalizeMatchPolicy(value)
  result.revision++
  return { ok: true, reason: "setup-match-policy-saved", store: result }
}

function saveTopologyMatch(store, raw) {
  var result = normalizeStore(store)
  var match = normalizeTopologyMatch(raw)
  if (!match) return { ok: false, reason: "invalid-topology-match", store: result }
  var replaced = false
  for (var i = 0; i < result.matches.length; i++) {
    if (result.matches[i].setupId !== match.setupId) continue
    result.matches[i] = match
    replaced = true
    break
  }
  if (!replaced && result.matches.length >= MAX_SETUP_MATCHES) return { ok: false, reason: "topology-match-limit", store: result }
  if (!replaced) result.matches.push(match)
  result.revision++
  return { ok: true, reason: "topology-match-saved", store: result, match: clone(match) }
}

function setProfile(store, raw) {
  var result = normalizeStore(store)
  var profile = normalizeSetupProfile(raw)
  if (!profile) return { ok: false, reason: "invalid-setup-profile", store: result }
  if (!result.profiles[profile.id] && Object.keys(result.profiles).length >= MAX_SETUP_PROFILES) return { ok: false, reason: "setup-profile-limit", store: result }
  result.profiles[profile.id] = profile
  result.revision++
  return { ok: true, reason: "setup-profile-saved", store: result, profile: clone(profile) }
}

function summary(resolved) {
  var source = object(resolved)
  var displays = object(source.displays)
  var power = object(source.power)
  var osk = object(source.osk)
  return {
    schemaVersion: Number(source.schemaVersion || SCHEMA_VERSION),
    selected: string(source.selected || "auto"),
    requested: string(source.requested || "auto"),
    source: string(source.source || "uninitialized"),
    displayCount: array(displays.rows).length,
    primaryDisplayId: safeId(displays.primaryDisplayId),
    unknownDisplayRoles: Number(displays.unknownCount || 0),
    osk: { requested: allowed(osk.requested, OSK_TARGETS, "focused-display"), status: string(osk.status || "unavailable"), outputId: safeId(osk.outputId), reason: string(osk.reason || "") },
    power: { available: power.available === true, requested: allowed(power.requested, POWER_POLICIES, "follow-system"), desired: allowed(power.desired, POWER_PROFILES, ""), current: allowed(power.current, POWER_PROFILES, "unknown"), batteryState: allowed(power.batteryState, BATTERY_STATES, "unknown"), batteryPercent: number(power.batteryPercent, -1), applyAllowed: power.applyAllowed === true, reason: string(power.reason || "") },
    preferredAdaptiveProfile: allowed(source.profile && source.profile.preferredAdaptiveProfile, ADAPTIVE_PROFILES, "auto"),
    revision: Number(source.revision || 0),
    reason: string(source.reason || "")
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  DISPLAY_ROLES: DISPLAY_ROLES,
  OSK_TARGETS: OSK_TARGETS,
  POWER_POLICIES: POWER_POLICIES,
  SETUP_IDS: SETUP_IDS,
  ADAPTIVE_PROFILES: ADAPTIVE_PROFILES,
  DOCK_TARGETS: DOCK_TARGETS,
  MATCH_MODES: MATCH_MODES,
  MAX_SETUP_MATCHES: MAX_SETUP_MATCHES,
  defaultDisplayPolicy: defaultDisplayPolicy,
  setupDefaults: setupDefaults,
  normalizeDisplayPolicy: normalizeDisplayPolicy,
  normalizeSetupProfile: normalizeSetupProfile,
  emptyStore: emptyStore,
  normalizeStore: normalizeStore,
  graphOutputs: graphOutputs,
  displayRows: displayRows,
  setDisplayRole: setDisplayRole,
  resolveOskTarget: resolveOskTarget,
  normalizePowerState: normalizePowerState,
  powerDecision: powerDecision,
  normalizeTopologyMatch: normalizeTopologyMatch,
  topologyMatch: topologyMatch,
  matchTopology: matchTopology,
  resolveSetup: resolveSetup,
  emptyState: emptyState,
  setSelected: setSelected,
  setMatchPolicy: setMatchPolicy,
  saveTopologyMatch: saveTopologyMatch,
  setProfile: setProfile,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
