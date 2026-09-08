// Debounced keyboard lifecycle and per-device policy model.
//
// This model owns runtime state only. Device add/remove events are observed
// in memory and never write the user's configuration. The service can use the
// resulting stable snapshot to coordinate one mode transition for the whole
// keyboard set instead of reacting to every USB/Bluetooth flap.

var PHASES = ["Disconnected", "Connecting", "Connected", "Disconnecting"]
var BEHAVIORS = ["nothing", "hide-osk", "hybrid", "desktop", "tablet", "ask", "ignore"]
var PROFILES = ["auto", "desktop", "tablet", "hybrid"]
var MAX_RULES = 128

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
  var name = string(value).toLowerCase()
  return value === true || value === 1 || name === "true" || name === "yes"
}

function token(value) {
  return string(value).trim().toLowerCase().replace(/[\s_]+/g, "-")
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function clamp(value, minimum, maximum, fallback) {
  var result = Number(value)
  if (!isFinite(result)) result = fallback
  return Math.max(minimum, Math.min(maximum, Math.round(result)))
}

function normalizeBehavior(value, fallback) {
  var name = token(value)
  if (name === "default" || name === "automatic" || name === "auto") return fallback === undefined ? "nothing" : fallback
  if (name === "hide-osk-only" || name === "hide-keyboard") name = "hide-osk"
  if (name === "ignore-device") name = "ignore"
  if (BEHAVIORS.indexOf(name) < 0) return fallback === undefined ? "nothing" : fallback
  return name
}

function normalizeProfile(value) {
  var name = token(value)
  if (name === "automatic" || name === "default") name = "auto"
  return PROFILES.indexOf(name) >= 0 ? name : ""
}

function adaptiveConfig(config) {
  var source = object(config)
  return source.adaptive && typeof source.adaptive === "object" ? source.adaptive : source
}

function normalizeConfig(config) {
  var adaptive = adaptiveConfig(config)
  var transition = object(adaptive.transition)
  var external = normalizeBehavior(adaptive.externalKeyboardPolicy, "hybrid")
  var unknown = normalizeBehavior(adaptive.unknownKeyboardPolicy, "hybrid")
  if (["nothing", "hide-osk", "hybrid", "desktop", "ask"].indexOf(external) < 0) external = "hybrid"
  if (["ignore", "nothing", "hide-osk", "hybrid", "desktop", "ask"].indexOf(unknown) < 0) unknown = "hybrid"
  return {
    enabled: adaptive.enabled !== false,
    automaticTransitions: adaptive.automaticTransitions !== false,
    profile: normalizeProfile(adaptive.profile || "auto") || "auto",
    externalKeyboardPolicy: external,
    unknownKeyboardPolicy: unknown,
    debounceMs: clamp(transition.debounceMs, 80, 1500, 260),
    stabilityMs: clamp(transition.stabilityMs, 0, 2000, 420),
    transitionEnabled: transition.enabled !== false,
    oskPolicy: normalizeBehavior(transition.oskPolicy, "hide-osk")
  }
}

function rules(config) {
  var adaptive = adaptiveConfig(config)
  var source = array(adaptive.deviceRules)
  var result = []
  for (var i = 0; i < source.length && result.length < MAX_RULES; i++) {
    var item = object(source[i])
    var id = string(item.id || item.deviceId || item.device_id).trim()
    if (!id || id.length > 240) continue
    var behavior = normalizeBehavior(item.behavior || item.policy, "")
    var preferred = normalizeProfile(item.preferredProfile || item.preferred_profile || item.profile)
    var ignored = bool(item.ignore) || behavior === "ignore"
    result.push({
      id: id,
      behavior: ignored ? "ignore" : behavior,
      preferredProfile: preferred,
      ignore: ignored,
      remember: item.remember !== false
    })
  }
  return result
}

function ruleFor(device, configuredRules) {
  var id = string(object(device).id)
  if (!id) return null
  var list = array(configuredRules)
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return list[i]
  return null
}

function safeDevice(device) {
  var source = object(device)
  var caps = object(source.capabilities)
  return {
    id: string(source.id),
    name: string(source.name || "Unnamed keyboard"),
    category: string(source.category || "external"),
    classification: string(source.classification || source.formFactorRelation || "unknown"),
    formFactorRelation: string(source.formFactorRelation || source.classification || "unknown"),
    transport: string(source.transport || "unknown"),
    connected: source.connected === true,
    seat: string(source.seat || "default"),
    behavior: string(source.behavior || "generic"),
    ignored: source.ignored === true,
    capabilityEvidence: string(source.capabilityEvidence || "none"),
    capabilities: {
      normalKeyboard: caps.normalKeyboard === true,
      functionRow: caps.functionRow === true,
      numberRow: caps.numberRow === true,
      modifiers: caps.modifiers === true,
      navigation: caps.navigation === true
    }
  }
}

function modeForBehavior(behavior) {
  if (["desktop", "tablet", "hybrid"].indexOf(behavior) >= 0) return behavior
  return ""
}

function behaviorForDevice(device, config, configuredRules) {
  var source = object(device)
  var relation = token(source.formFactorRelation || source.classification)
  var transport = token(source.transport)
  var rule = ruleFor(source, configuredRules)
  var explicit = rule !== null
  var behavior = explicit ? normalizeBehavior(rule.behavior, "") : ""
  var preferredProfile = explicit ? normalizeProfile(rule.preferredProfile) : normalizeProfile(source.preferredProfile)
  if (rule && rule.ignore) behavior = "ignore"
  if (!behavior && preferredProfile && preferredProfile !== "auto") behavior = preferredProfile

  // A built-in keyboard is a capability signal, not an external attach
  // request. Laptop/convertible posture remains responsible for its mode.
  if (!explicit && relation === "built-in") behavior = "nothing"
  if (!behavior && relation === "unknown") behavior = normalizeConfig(config).unknownKeyboardPolicy
  if (!behavior) behavior = normalizeConfig(config).externalKeyboardPolicy
  if (!behavior) behavior = "hybrid"

  var ignored = source.ignored === true || behavior === "ignore"
  var mode = ignored ? "" : modeForBehavior(behavior)
  return {
    id: string(source.id),
    relation: relation || "unknown",
    transport: transport || "unknown",
    behavior: behavior,
    preferredProfile: preferredProfile,
    mode: mode,
    ignored: ignored,
    explicit: explicit,
    ruleId: rule ? rule.id : "",
    reason: explicit ? "remembered device rule" : relation === "built-in" ? "built-in keyboard" : behavior === "ask" ? "new keyboard requires choice" : "adaptive keyboard policy",
    oskAction: behavior === "hide-osk" ? "hide" : "preserve"
  }
}

function modeChoice(policies) {
  var chosen = ""
  var priority = { tablet: 1, hybrid: 2, desktop: 3 }
  var reason = ""
  for (var i = 0; i < policies.length; i++) {
    var item = policies[i]
    if (!item || item.ignored || !item.mode) continue
    if (!chosen || priority[item.mode] > priority[chosen]) {
      chosen = item.mode
      reason = item.reason
    }
  }
  return { mode: chosen, reason: reason }
}

function sortedUnique(values) {
  var result = []
  var seen = {}
  var list = array(values)
  for (var i = 0; i < list.length; i++) {
    var value = string(list[i])
    if (value && !seen[value]) {
      seen[value] = true
      result.push(value)
    }
  }
  return result.sort()
}

function resolve(devices, config, context) {
  var source = object(context)
  var list = array(devices)
  var configuredRules = rules(config)
  var all = []
  var active = []
  var policies = []
  var builtInCount = 0
  var externalCount = 0
  var detachableCount = 0
  var bluetoothCount = 0
  var ignoredCount = 0
  for (var i = 0; i < list.length; i++) {
    var safe = safeDevice(list[i])
    if (!safe.id || safe.connected !== true) continue
    var policy = behaviorForDevice(list[i], config, configuredRules)
    all.push(safe)
    policies.push(policy)
    if (policy.ignored) {
      ignoredCount++
      continue
    }
    active.push(safe)
    if (policy.relation === "built-in") builtInCount++
    else externalCount++
    if (policy.relation === "detachable") detachableCount++
    if (policy.transport === "bluetooth") bluetoothCount++
  }
  var choice = modeChoice(policies)
  var ids = sortedUnique(active.map(function(item) { return item.id }))
  var modePolicy = normalizeConfig(config)
  var automatic = modePolicy.enabled && modePolicy.automaticTransitions && modePolicy.profile === "auto"
  var externalActive = externalCount > 0
  var targetMode = automatic ? choice.mode : ""
  var ask = policies.some(function(item) { return item && !item.ignored && item.behavior === "ask" })
  var oskAction = policies.some(function(item) { return item && !item.ignored && item.oskAction === "hide" }) ? "hide" : "preserve"
  var signature = ids.join(",") + "|" + targetMode + "|" + oskAction
  var stableSignals = {
    physicalKeyboard: active.length > 0,
    externalKeyboard: externalActive,
    detachableKeyboard: detachableCount > 0,
    bluetoothKeyboard: bluetoothCount > 0,
    activeCount: active.length,
    externalCount: externalCount,
    builtInCount: builtInCount,
    detachableCount: detachableCount,
    bluetoothCount: bluetoothCount,
    targetMode: targetMode,
    modeReason: choice.reason,
    oskAction: oskAction,
    ask: ask,
    automatic: automatic,
    touchscreen: source.touchscreen === true
  }
  return {
    signature: signature,
    ids: ids,
    devices: all,
    policies: policies,
    activeCount: active.length,
    externalCount: externalCount,
    builtInCount: builtInCount,
    detachableCount: detachableCount,
    bluetoothCount: bluetoothCount,
    ignoredCount: ignoredCount,
    connected: active.length > 0,
    externalActive: externalActive,
    targetMode: targetMode,
    modeReason: choice.reason || (automatic ? "no external keyboard policy" : "manual adaptive profile"),
    oskAction: oskAction,
    ask: ask,
    automatic: automatic,
    stableSignals: stableSignals
  }
}

function emptyState() {
  return {
    schemaVersion: 1,
    initialized: false,
    phase: "Disconnected",
    modeReady: true,
    pending: false,
    stableConnected: false,
    stableIds: [],
    stableSignature: "",
    stableSince: 0,
    candidateSignature: "",
    candidateConnected: false,
    candidateSince: 0,
    candidateReadyAt: 0,
    connectedCount: 0,
    externalCount: 0,
    builtInCount: 0,
    detachableCount: 0,
    bluetoothCount: 0,
    ignoredCount: 0,
    targetMode: "",
    modeReason: "not-evaluated",
    oskAction: "preserve",
    stableSignals: { physicalKeyboard: false, externalKeyboard: false, detachableKeyboard: false, bluetoothKeyboard: false, activeCount: 0, externalCount: 0, targetMode: "", oskAction: "preserve" },
    event: { type: "none", reason: "not-evaluated", deviceIds: [] },
    lastEvent: { action: "", subsystem: "", at: 0 },
    eventCount: 0,
    revision: 0
  }
}

function copyState(source) {
  var result = {}
  var current = source && typeof source === "object" ? source : emptyState()
  for (var key in current) result[key] = current[key]
  return result
}

function phaseFor(previousIds, nextIds, nextConnected) {
  var before = {}
  var after = {}
  var oldIds = array(previousIds)
  var newIds = array(nextIds)
  for (var i = 0; i < oldIds.length; i++) before[oldIds[i]] = true
  for (var j = 0; j < newIds.length; j++) after[newIds[j]] = true
  var added = newIds.some(function(id) { return !before[id] })
  var removed = oldIds.some(function(id) { return !after[id] })
  if (removed && !added) return "Disconnecting"
  if (added || removed) return "Connecting"
  return nextConnected ? "Connecting" : "Disconnecting"
}

function transitionEvent(previousIds, nextIds, connected, resolution) {
  var before = {}
  var after = {}
  var oldIds = array(previousIds)
  var newIds = array(nextIds)
  for (var i = 0; i < oldIds.length; i++) before[oldIds[i]] = true
  for (var j = 0; j < newIds.length; j++) after[newIds[j]] = true
  var added = newIds.filter(function(id) { return !before[id] })
  var removed = oldIds.filter(function(id) { return !after[id] })
  var type = connected ? "keyboard-attached" : "keyboard-detached"
  if (added.length > 0 && removed.length > 0) type = "keyboard-changed"
  if (!connected && added.length === 0 && removed.length === 0) type = "keyboard-detached"
  return { type: type, reason: resolution.modeReason, deviceIds: sortedUnique(added.concat(removed)) }
}

function observe(previous, devices, config, context, now) {
  var source = copyState(previous || emptyState())
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var cfg = normalizeConfig(config)
  var resolution = resolve(devices, config, context)
  if (!source.initialized) {
    var initial = copyState(source)
    initial.initialized = true
    initial.phase = resolution.connected ? "Connected" : "Disconnected"
    initial.modeReady = true
    initial.pending = false
    initial.stableConnected = resolution.connected
    initial.stableIds = resolution.ids
    initial.stableSignature = resolution.signature
    initial.stableSince = timestamp
    initial.candidateSignature = ""
    initial.candidateSince = 0
    initial.candidateReadyAt = 0
    initial.connectedCount = resolution.activeCount
    initial.externalCount = resolution.externalCount
    initial.builtInCount = resolution.builtInCount
    initial.detachableCount = resolution.detachableCount
    initial.bluetoothCount = resolution.bluetoothCount
    initial.ignoredCount = resolution.ignoredCount
    initial.targetMode = resolution.targetMode
    initial.modeReason = resolution.modeReason
    initial.oskAction = resolution.oskAction
    initial.stableSignals = resolution.stableSignals
    initial.event = { type: "initial", reason: resolution.modeReason, deviceIds: resolution.ids }
    initial.revision = Number(initial.revision || 0) + 1
    return { changed: false, pending: false, delayMs: 0, event: initial.event, resolution: resolution, state: initial }
  }

  var same = resolution.signature === string(source.stableSignature)
  if (same) {
    var steady = copyState(source)
    steady.phase = steady.stableConnected ? "Connected" : "Disconnected"
    steady.modeReady = true
    steady.pending = false
    steady.candidateSignature = ""
    steady.candidateSince = 0
    steady.candidateReadyAt = 0
    steady.connectedCount = resolution.activeCount
    steady.externalCount = resolution.externalCount
    steady.builtInCount = resolution.builtInCount
    steady.detachableCount = resolution.detachableCount
    steady.bluetoothCount = resolution.bluetoothCount
    steady.ignoredCount = resolution.ignoredCount
    steady.targetMode = resolution.targetMode
    steady.modeReason = resolution.modeReason
    steady.oskAction = resolution.oskAction
    steady.stableSignals = resolution.stableSignals
    steady.revision = Number(steady.revision || 0) + 1
    return { changed: false, pending: false, delayMs: 0, event: { type: "none", reason: "stable", deviceIds: [] }, resolution: resolution, state: steady }
  }

  var candidate = copyState(source)
  if (candidate.candidateSignature !== resolution.signature || !candidate.candidateSince) {
    candidate.phase = phaseFor(source.stableIds, resolution.ids, resolution.connected)
    candidate.modeReady = false
    candidate.pending = true
    candidate.candidateSignature = resolution.signature
    candidate.candidateConnected = resolution.connected
    candidate.candidateSince = timestamp
    candidate.candidateReadyAt = timestamp + cfg.debounceMs + cfg.stabilityMs
    candidate.connectedCount = resolution.activeCount
    candidate.externalCount = resolution.externalCount
    candidate.builtInCount = resolution.builtInCount
    candidate.detachableCount = resolution.detachableCount
    candidate.bluetoothCount = resolution.bluetoothCount
    candidate.ignoredCount = resolution.ignoredCount
    candidate.targetMode = resolution.targetMode
    candidate.modeReason = resolution.modeReason
    candidate.oskAction = resolution.oskAction
    candidate.revision = Number(candidate.revision || 0) + 1
    return { changed: false, pending: true, delayMs: Math.max(1, cfg.debounceMs + cfg.stabilityMs), event: { type: "pending", reason: "keyboard stability window", deviceIds: resolution.ids }, resolution: resolution, state: candidate }
  }

  var remaining = Math.max(0, Number(candidate.candidateReadyAt || 0) - timestamp)
  if (remaining > 0) {
    candidate.phase = phaseFor(source.stableIds, resolution.ids, resolution.connected)
    candidate.modeReady = false
    candidate.pending = true
    candidate.connectedCount = resolution.activeCount
    candidate.externalCount = resolution.externalCount
    candidate.builtInCount = resolution.builtInCount
    candidate.detachableCount = resolution.detachableCount
    candidate.bluetoothCount = resolution.bluetoothCount
    candidate.ignoredCount = resolution.ignoredCount
    candidate.targetMode = resolution.targetMode
    candidate.modeReason = resolution.modeReason
    candidate.oskAction = resolution.oskAction
    candidate.revision = Number(candidate.revision || 0) + 1
    return { changed: false, pending: true, delayMs: remaining, event: { type: "pending", reason: "keyboard stability window", deviceIds: resolution.ids }, resolution: resolution, state: candidate }
  }

  var committed = copyState(candidate)
  committed.phase = resolution.connected ? "Connected" : "Disconnected"
  committed.modeReady = true
  committed.pending = false
  committed.stableConnected = resolution.connected
  committed.stableIds = resolution.ids
  committed.stableSignature = resolution.signature
  committed.stableSince = timestamp
  committed.candidateSignature = ""
  committed.candidateConnected = false
  committed.candidateSince = 0
  committed.candidateReadyAt = 0
  committed.connectedCount = resolution.activeCount
  committed.externalCount = resolution.externalCount
  committed.builtInCount = resolution.builtInCount
  committed.detachableCount = resolution.detachableCount
  committed.bluetoothCount = resolution.bluetoothCount
  committed.ignoredCount = resolution.ignoredCount
  committed.targetMode = resolution.targetMode
  committed.modeReason = resolution.modeReason
  committed.oskAction = resolution.oskAction
  committed.stableSignals = resolution.stableSignals
  committed.event = transitionEvent(source.stableIds, resolution.ids, resolution.connected, resolution)
  committed.revision = Number(committed.revision || 0) + 1
  return { changed: true, pending: false, delayMs: 0, event: committed.event, resolution: resolution, state: committed }
}

function noteEvent(previous, event, now) {
  var source = copyState(previous || emptyState())
  var item = object(event)
  var action = token(item.action || item.event)
  var next = copyState(source)
  next.lastEvent = { action: action, subsystem: string(item.subsystem || "input"), at: Number(now) || Date.now() }
  next.eventCount = Number(source.eventCount || 0) + 1
  return next
}

function summary(state) {
  var source = object(state)
  return {
    phase: PHASES.indexOf(string(source.phase)) >= 0 ? string(source.phase) : "Disconnected",
    pending: source.pending === true,
    modeReady: source.modeReady !== false,
    stableConnected: source.stableConnected === true,
    connectedCount: Number(source.connectedCount || 0),
    externalCount: Number(source.externalCount || 0),
    builtInCount: Number(source.builtInCount || 0),
    detachableCount: Number(source.detachableCount || 0),
    bluetoothCount: Number(source.bluetoothCount || 0),
    ignoredCount: Number(source.ignoredCount || 0),
    targetMode: string(source.targetMode),
    modeReason: string(source.modeReason),
    oskAction: string(source.oskAction || "preserve"),
    event: source.event || { type: "none", reason: "not-evaluated", deviceIds: [] },
    lastEvent: source.lastEvent || { action: "", subsystem: "", at: 0 },
    eventCount: Number(source.eventCount || 0),
    revision: Number(source.revision || 0)
  }
}

var api = {
  PHASES: PHASES,
  BEHAVIORS: BEHAVIORS,
  MAX_RULES: MAX_RULES,
  normalizeConfig: normalizeConfig,
  normalizeRule: function(rule) { return rules({ adaptive: { deviceRules: [rule] } })[0] || null },
  rules: rules,
  ruleFor: ruleFor,
  behaviorForDevice: behaviorForDevice,
  resolve: resolve,
  emptyState: emptyState,
  observe: observe,
  noteEvent: noteEvent,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
