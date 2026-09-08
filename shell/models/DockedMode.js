// Pure docking trigger model for external-display workflows.
//
// Docking is a runtime overlay on Auto mode. It never writes configuration,
// moves ordinary windows, or assumes a particular machine model. Monitor
// names are used only as capability evidence and are never returned by the
// summary API (never returned by the summary API as raw device identity).

var PHASES = ["undocked", "docking", "docked", "undocking", "disabled"]
var MODES = ["desktop", "tablet", "hybrid"]
var TRIGGERS = ["external-monitor-and-keyboard", "external-monitor"]

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

function clamp(value, minimum, maximum, fallback) {
  var result = Number(value)
  if (!isFinite(result)) result = fallback
  return Math.max(minimum, Math.min(maximum, Math.round(result)))
}

function mode(value, fallback) {
  var name = token(value)
  if (name === "computer" || name === "laptop") name = "desktop"
  return MODES.indexOf(name) >= 0 ? name : (fallback || "")
}

function adaptiveConfig(config) {
  var source = object(config)
  return object(source.adaptive && typeof source.adaptive === "object" ? source.adaptive : source)
}

function normalizeConfig(config) {
  var adaptive = adaptiveConfig(config)
  var source = object(adaptive.dockedMode)
  var trigger = token(source.trigger || "external-monitor-and-keyboard")
  if (TRIGGERS.indexOf(trigger) < 0) trigger = "external-monitor-and-keyboard"
  var rotation = token(source.rotation || source.rotationPolicy || "preserve")
  if (["preserve", "auto", "locked", "unchanged"].indexOf(rotation) < 0) rotation = "preserve"
  return {
    enabled: source.enabled !== false,
    trigger: trigger,
    profile: mode(source.profile, "desktop") || "desktop",
    keepTouch: source.keepTouch !== false,
    restoreAutoState: source.restoreAutoState !== false,
    rotation: rotation,
    debounceMs: clamp(source.debounceMs, 80, 1500, 180),
    stabilityMs: clamp(source.stabilityMs, 0, 1500, 260)
  }
}

function connectorName(monitor) {
  var source = object(monitor)
  var fields = [source.name, source.monitor, source.output, source.connector, source.port]
  for (var i = 0; i < fields.length; i++) {
    var value = token(fields[i])
    if (value) return value
  }
  return ""
}

function monitorClass(monitor, index, monitors) {
  var source = object(monitor)
  if (bool(source.external) || bool(source.isExternal) || token(source.outputRole) === "external") return "external"
  if (bool(source.internal) || bool(source.builtin) || bool(source.builtIn) || token(source.outputRole) === "internal") return "internal"

  var fields = [connectorName(source), token(source.description), token(source.make), token(source.model)]
  var joined = fields.join(" ")
  if (/(^|[-_ ])(edp|lvds|dsi|panel|internal|builtin|built-in)([-_ ]|$)/.test(joined)) return "internal"
  if (/(^|[-_ ])(hdmi|dp|displayport|usb-c|usbc|thunderbolt|vga|dvi)([-_ ]|$)/.test(joined)) return "external"

  // When an internal panel is explicitly known, an otherwise unnamed second
  // output is safe to treat as external. If no evidence exists, stay unknown
  // and do not activate a desktop profile aggressively.
  if (index > 0 && array(monitors).some(function(item) { return monitorClass(item, -1, []) === "internal" })) return "external"
  return "unknown"
}

function inventory(monitors) {
  var list = array(monitors)
  var internalCount = 0
  var externalCount = 0
  var unknownCount = 0
  for (var i = 0; i < list.length; i++) {
    var kind = monitorClass(list[i], i, list)
    if (kind === "internal") internalCount++
    else if (kind === "external") externalCount++
    else unknownCount++
  }
  return {
    monitorCount: list.length,
    internalCount: internalCount,
    externalCount: externalCount,
    externalMonitorCount: externalCount,
    unknownCount: unknownCount,
    externalMonitor: externalCount > 0,
    evidence: externalCount > 0 ? "connector-or-capability" : list.length > 1 ? "insufficient-output-evidence" : "single-or-no-output"
  }
}

function signalState(signals) {
  var source = object(signals)
  var info = object(source.monitorInventory)
  if (Object.keys(info).length === 0) info = inventory(source.monitors)
  var externalMonitor = source.externalMonitor === true || info.externalMonitor === true || Number(source.externalMonitorCount || 0) > 0
  var keyboardCount = Math.max(0, Number(source.keyboardCount || source.activeKeyboardCount || 0))
  var keyboard = source.physicalKeyboard === true || keyboardCount > 0
  var keyboardStable = source.keyboardStable !== false && source.keyboardPending !== true
  return {
    externalMonitor: externalMonitor,
    externalMonitorCount: Math.max(0, Number(info.externalCount || source.externalMonitorCount || (externalMonitor ? 1 : 0))),
    monitorCount: Math.max(0, Number(info.monitorCount || source.monitorCount || 0)),
    internalMonitorCount: Math.max(0, Number(info.internalCount || 0)),
    unknownMonitorCount: Math.max(0, Number(info.unknownCount || 0)),
    keyboard: keyboard,
    keyboardCount: keyboardCount,
    keyboardStable: keyboardStable
  }
}

function resolve(signals, config, context) {
  var cfg = normalizeConfig(config)
  var source = object(context)
  var state = signalState(signals)
  var automatic = source.selectedProfile === undefined || token(source.selectedProfile) === "auto"
  automatic = automatic && source.adaptiveEnabled !== false && source.automaticTransitions !== false
  var triggerMatched = cfg.trigger === "external-monitor" ? state.externalMonitor : state.externalMonitor && state.keyboard
  var eligible = cfg.enabled && triggerMatched && state.keyboardStable
  var active = eligible && automatic
  var suppressed = triggerMatched && state.keyboardStable && !automatic
  var targetMode = active ? cfg.profile : ""
  var reason = ""
  if (!cfg.enabled) reason = "docked mode disabled"
  else if (!state.externalMonitor) reason = "no external monitor"
  else if (cfg.trigger === "external-monitor-and-keyboard" && !state.keyboard) reason = "no stable physical keyboard"
  else if (!state.keyboardStable) reason = "waiting for stable keyboard state"
  else if (!automatic) reason = "manual profile owns mode"
  else reason = "external monitor and keyboard"
  return {
    config: cfg,
    signals: state,
    automatic: automatic,
    triggerMatched: triggerMatched,
    eligible: eligible,
    active: active,
    suppressed: suppressed,
    targetMode: targetMode,
    reason: reason,
    signature: [cfg.enabled, cfg.trigger, cfg.profile, state.externalMonitor, state.externalMonitorCount, state.keyboard, state.keyboardCount, state.keyboardStable, automatic].join("|")
  }
}

function emptyState() {
  return {
    schemaVersion: 1,
    initialized: false,
    phase: "undocked",
    active: false,
    eligible: false,
    suppressed: false,
    pending: false,
    stableSignature: "",
    candidateSignature: "",
    candidateSince: 0,
    candidateReadyAt: 0,
    monitorCount: 0,
    externalMonitorCount: 0,
    internalMonitorCount: 0,
    unknownMonitorCount: 0,
    externalMonitor: false,
    keyboardConnected: false,
    keyboardStable: true,
    keyboardCount: 0,
    targetMode: "",
    previousAutoMode: "",
    restoredMode: "",
    keepTouch: true,
    rotationPolicy: "preserve",
    reason: "not-evaluated",
    event: { type: "none", reason: "not-evaluated" },
    revision: 0
  }
}

function copyState(source) {
  var result = {}
  var current = source && typeof source === "object" ? source : emptyState()
  for (var key in current) result[key] = current[key]
  return result
}

function setResolved(state, resolved, timestamp, context, eventType) {
  var next = copyState(state)
  var previousActive = next.active === true
  next.active = resolved.active === true
  next.eligible = resolved.eligible === true
  next.suppressed = resolved.suppressed === true
  next.pending = false
  next.stableSignature = resolved.signature
  next.candidateSignature = ""
  next.candidateSince = 0
  next.candidateReadyAt = 0
  next.monitorCount = resolved.signals.monitorCount
  next.externalMonitorCount = resolved.signals.externalMonitorCount
  next.internalMonitorCount = resolved.signals.internalMonitorCount
  next.unknownMonitorCount = resolved.signals.unknownMonitorCount
  next.externalMonitor = resolved.signals.externalMonitor
  next.keyboardConnected = resolved.signals.keyboard
  next.keyboardStable = resolved.signals.keyboardStable
  next.keyboardCount = resolved.signals.keyboardCount
  next.targetMode = resolved.targetMode
  next.keepTouch = resolved.config.keepTouch
  next.rotationPolicy = resolved.config.rotation
  next.phase = !resolved.config.enabled ? "disabled" : resolved.active ? "docked" : "undocked"
  next.reason = resolved.reason
  if (resolved.active && !previousActive) {
    next.previousAutoMode = mode(object(context).autoMode, "desktop")
    next.restoredMode = ""
  } else if (!resolved.active && previousActive) {
    next.restoredMode = resolved.config.restoreAutoState ? next.previousAutoMode : ""
  }
  next.event = eventType ? { type: eventType, reason: resolved.reason } : next.event
  next.revision = Number(next.revision || 0) + 1
  return next
}

function observe(previous, signals, config, context, now) {
  var source = copyState(previous || emptyState())
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var resolved = resolve(signals, config, context)
  var cfg = resolved.config
  if (!source.initialized) {
    var initial = setResolved(Object.assign({}, source, { initialized: true }), resolved, timestamp, context, null)
    initial.event = { type: "initial", reason: resolved.reason }
    return { changed: false, pending: false, delayMs: 0, resolved: resolved, state: initial }
  }

  if (resolved.signature === string(source.stableSignature) && !source.pending) {
    var steady = setResolved(source, resolved, timestamp, context, null)
    steady.event = source.event || steady.event
    return { changed: false, pending: false, delayMs: 0, resolved: resolved, state: steady }
  }

  var candidate = copyState(source)
  if (candidate.candidateSignature !== resolved.signature || !candidate.candidateSince) {
    candidate.pending = true
    candidate.candidateSignature = resolved.signature
    candidate.candidateSince = timestamp
    candidate.candidateReadyAt = timestamp + cfg.debounceMs + cfg.stabilityMs
    candidate.phase = !cfg.enabled ? "disabled" : resolved.active ? "docking" : source.active ? "undocking" : "undocked"
    candidate.reason = resolved.reason
    candidate.monitorCount = resolved.signals.monitorCount
    candidate.externalMonitorCount = resolved.signals.externalMonitorCount
    candidate.internalMonitorCount = resolved.signals.internalMonitorCount
    candidate.unknownMonitorCount = resolved.signals.unknownMonitorCount
    candidate.externalMonitor = resolved.signals.externalMonitor
    candidate.keyboardConnected = resolved.signals.keyboard
    candidate.keyboardStable = resolved.signals.keyboardStable
    candidate.keyboardCount = resolved.signals.keyboardCount
    candidate.revision = Number(candidate.revision || 0) + 1
    return { changed: false, pending: true, delayMs: cfg.debounceMs + cfg.stabilityMs, resolved: resolved, state: candidate }
  }

  var remaining = Math.max(0, Number(candidate.candidateReadyAt || 0) - timestamp)
  if (remaining > 0) {
    candidate.pending = true
    candidate.phase = !cfg.enabled ? "disabled" : resolved.active ? "docking" : source.active ? "undocking" : "undocked"
    candidate.reason = resolved.reason
    candidate.revision = Number(candidate.revision || 0) + 1
    return { changed: false, pending: true, delayMs: remaining, resolved: resolved, state: candidate }
  }

  var eventType = resolved.active ? "docked" : source.active ? "undocked" : "docking-unchanged"
  var committed = setResolved(candidate, resolved, timestamp, context, eventType)
  return { changed: true, pending: false, delayMs: 0, resolved: resolved, state: committed }
}

function modeOverride(state) {
  var source = object(state)
  return source.active === true ? mode(source.targetMode, "") : ""
}

function summary(state) {
  var source = object(state)
  return {
    phase: PHASES.indexOf(string(source.phase)) >= 0 ? string(source.phase) : "undocked",
    active: source.active === true,
    eligible: source.eligible === true,
    suppressed: source.suppressed === true,
    pending: source.pending === true,
    externalMonitor: source.externalMonitor === true,
    monitorCount: Number(source.monitorCount || 0),
    externalMonitorCount: Number(source.externalMonitorCount || 0),
    internalMonitorCount: Number(source.internalMonitorCount || 0),
    unknownMonitorCount: Number(source.unknownMonitorCount || 0),
    keyboardConnected: source.keyboardConnected === true,
    keyboardStable: source.keyboardStable !== false,
    keyboardCount: Number(source.keyboardCount || 0),
    targetMode: string(source.targetMode),
    previousAutoMode: string(source.previousAutoMode),
    restoredMode: string(source.restoredMode),
    keepTouch: source.keepTouch !== false,
    rotationPolicy: string(source.rotationPolicy || "preserve"),
    reason: string(source.reason || "not-evaluated"),
    event: source.event || { type: "none", reason: "not-evaluated" },
    revision: Number(source.revision || 0)
  }
}

var api = {
  PHASES: PHASES,
  MODES: MODES,
  TRIGGERS: TRIGGERS,
  normalizeConfig: normalizeConfig,
  monitorClass: monitorClass,
  inventory: inventory,
  signalState: signalState,
  resolve: resolve,
  emptyState: emptyState,
  observe: observe,
  modeOverride: modeOverride,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
