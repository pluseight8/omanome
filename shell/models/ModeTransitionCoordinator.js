// Shared, local-only choreography for runtime mode changes.
//
// Components consume componentState() through the service. Progress is kept
// in QML memory and is advanced by one local timer; no compositor command or
// subprocess is involved in an animation frame. Starting a new transition
// while one is active reverses from the current progress when possible.

var PHASES = ["idle", "running", "completed", "cancelled"]
var PRESETS = ["instant", "fast", "smooth", "playful", "custom"]
var COMPONENTS = ["dock", "overview", "launcher", "quick-settings", "window-controls", "osk", "snap", "split", "notifications", "settings"]

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
  return Math.max(minimum, Math.min(maximum, result))
}

function normalizedPreset(value) {
  var name = token(value || "smooth")
  if (name === "default" || name === "standard") name = "smooth"
  if (name === "reduced" || name === "minimal") name = "fast"
  return PRESETS.indexOf(name) >= 0 ? name : "smooth"
}

function animationConfig(config, context) {
  var source = object(config)
  var adaptive = source.adaptive && typeof source.adaptive === "object" ? source.adaptive : source
  var transition = object(adaptive.transition)
  var animations = object(source.animations)
  var accessibility = object(source.accessibility)
  var runtime = object(context)
  var reduced = bool(runtime.reducedMotion) || bool(accessibility.reducedMotion) || bool(animations.reducedMotion) || bool(source.general && source.general.reduceMotion)
  var enabled = transition.enabled !== false && animations.enabled !== false && runtime.enabled !== false
  var preset = normalizedPreset(runtime.preset || animations.preset || transition.animationPreset || "smooth")
  var duration = transition.durationMs
  if (duration === undefined) duration = runtime.durationMs
  if (duration === undefined) duration = 260
  if (preset === "instant") duration = 0
  else if (preset === "fast") duration = 180
  else if (preset === "smooth") duration = 260
  else if (preset === "playful") duration = 320
  else duration = clamp(duration, 80, 350, 260)
  if (reduced) duration = enabled ? 1 : 0
  if (!enabled) duration = 0
  return { enabled: enabled, reducedMotion: reduced, preset: preset, durationMs: Math.max(0, Math.round(duration)) }
}

function safeMode(value, fallback) {
  var mode = token(value)
  return mode || fallback || "desktop"
}

function emptyState() {
  return {
    schemaVersion: 1,
    phase: "idle",
    active: false,
    fromMode: "desktop",
    toMode: "desktop",
    progress: 1,
    rawProgress: 1,
    reduceMotion: false,
    preset: "smooth",
    durationMs: 0,
    startedAt: 0,
    completedAt: 0,
    reason: "not-evaluated",
    revision: 0,
    interrupted: false,
    cancelReason: ""
  }
}

function copyState(source) {
  var result = {}
  var current = source && typeof source === "object" ? source : emptyState()
  for (var key in current) result[key] = current[key]
  return result
}

function eased(value, reduced) {
  var progress = Math.max(0, Math.min(1, Number(value) || 0))
  if (reduced) return progress
  // Smoothstep avoids a visually abrupt start/end without a spring overshoot.
  return progress * progress * (3 - 2 * progress)
}

function begin(previous, fromMode, toMode, reason, now, config, context) {
  var source = copyState(previous || emptyState())
  var from = safeMode(fromMode, source.toMode || "desktop")
  var to = safeMode(toMode, from)
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var settings = animationConfig(config, context)
  if (from === to) {
    source.phase = "completed"
    source.active = false
    source.fromMode = from
    source.toMode = to
    source.progress = 1
    source.rawProgress = 1
    source.durationMs = 0
    source.completedAt = timestamp
    source.reason = string(reason || "no-op")
    source.interrupted = false
    source.cancelReason = ""
    source.revision = Number(source.revision || 0) + 1
    return { changed: false, state: source }
  }

  var currentProgress = Number(source.progress)
  if (!isFinite(currentProgress)) currentProgress = 0
  currentProgress = Math.max(0, Math.min(1, currentProgress))
  var reversing = source.active === true && source.toMode === from && source.fromMode === to
  var state = copyState(source)
  if (source.active === true && reversing) {
    // Keep the visual position continuous while changing the semantic target.
    state.fromMode = from
    state.toMode = to
    state.progress = 1 - currentProgress
    state.rawProgress = state.progress
    state.interrupted = true
  } else if (source.active === true && source.toMode !== to) {
    // A third target starts from the currently visible side of the transition,
    // never from a stale mode that can cause a geometry jump.
    state.fromMode = currentProgress >= 0.5 ? source.toMode : source.fromMode
    state.toMode = to
    state.progress = 0
    state.rawProgress = 0
    state.interrupted = true
  } else {
    state.fromMode = from
    state.toMode = to
    state.progress = 0
    state.rawProgress = 0
    state.interrupted = false
  }
  var immediate = settings.durationMs <= 0 || settings.reducedMotion
  state.phase = immediate ? "completed" : "running"
  state.active = !immediate
  state.reduceMotion = settings.reducedMotion
  state.preset = settings.preset
  state.durationMs = settings.durationMs
  state.startedAt = timestamp
  state.completedAt = immediate ? timestamp : 0
  state.reason = string(reason || "mode-change")
  state.cancelReason = ""
  state.revision = Number(source.revision || 0) + 1
  if (immediate) {
    state.progress = 1
    state.rawProgress = 1
  }
  return { changed: true, state: state }
}

function tick(previous, now) {
  var source = copyState(previous || emptyState())
  if (source.active !== true || source.phase !== "running") return { changed: false, state: source }
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var duration = Math.max(1, Number(source.durationMs || 1))
  var startedAt = Number(source.startedAt)
  if (!isFinite(startedAt)) startedAt = timestamp
  var raw = Math.max(0, Math.min(1, (timestamp - startedAt) / duration))
  var next = copyState(source)
  next.rawProgress = raw
  next.progress = eased(raw, source.reduceMotion === true)
  next.revision = Number(source.revision || 0) + 1
  if (raw >= 1) {
    next.phase = "completed"
    next.active = false
    next.progress = 1
    next.rawProgress = 1
    next.completedAt = timestamp
  }
  return { changed: true, state: next }
}

function cancel(previous, reason, now) {
  var source = copyState(previous || emptyState())
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  source.phase = "cancelled"
  source.active = false
  source.cancelReason = string(reason || "cancelled")
  source.reason = source.cancelReason
  source.completedAt = timestamp
  source.revision = Number(source.revision || 0) + 1
  return { changed: true, state: source }
}

function componentState(state, component, componentPolicy) {
  var source = object(state)
  var policy = object(componentPolicy)
  var id = token(component)
  var progress = Number(source.progress)
  if (!isFinite(progress)) progress = 0
  progress = Math.max(0, Math.min(1, progress))
  var policyValue = policy[id]
  if (policyValue === undefined) {
    var aliases = { "quick-settings": "quickSettings", "window-controls": "windowControls", "snap": "snapAssist", "notifications": "notificationDensity" }
    policyValue = policy[aliases[id]]
  }
  return {
    component: id,
    fromMode: safeMode(source.fromMode, "desktop"),
    toMode: safeMode(source.toMode, "desktop"),
    progress: progress,
    rawProgress: Math.max(0, Math.min(1, Number(source.rawProgress === undefined ? progress : source.rawProgress))),
    reduceMotion: source.reduceMotion === true,
    reason: string(source.reason || "mode-change"),
    phase: string(source.phase || "idle"),
    active: source.active === true,
    policy: policyValue === undefined ? null : policyValue
  }
}

function allComponents(state, componentPolicy, names) {
  var list = array(names).length > 0 ? array(names) : COMPONENTS
  return list.slice(0, COMPONENTS.length).map(function(name) { return componentState(state, name, componentPolicy) })
}

function summary(state) {
  var source = object(state)
  return {
    phase: PHASES.indexOf(string(source.phase)) >= 0 ? string(source.phase) : "idle",
    active: source.active === true,
    fromMode: string(source.fromMode || "desktop"),
    toMode: string(source.toMode || "desktop"),
    progress: Math.max(0, Math.min(1, Number(source.progress) || 0)),
    reduceMotion: source.reduceMotion === true,
    preset: normalizedPreset(source.preset),
    durationMs: Math.max(0, Number(source.durationMs || 0)),
    reason: string(source.reason || "not-evaluated"),
    interrupted: source.interrupted === true,
    cancelReason: string(source.cancelReason || ""),
    revision: Number(source.revision || 0)
  }
}

var api = {
  PHASES: PHASES,
  PRESETS: PRESETS,
  COMPONENTS: COMPONENTS,
  animationConfig: animationConfig,
  emptyState: emptyState,
  begin: begin,
  tick: tick,
  cancel: cancel,
  componentState: componentState,
  allComponents: allComponents,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
