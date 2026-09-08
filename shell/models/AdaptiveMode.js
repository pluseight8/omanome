// Pure adaptive profile and component-policy model.
//
// A profile is a policy overlay, not a second configuration store. The model
// keeps the selected profile, the posture-derived source mode and the
// effective mode separate so a temporary profile can never overwrite a
// user's permanent feature settings.

var PROFILE_IDS = ["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"]
var MODE_IDS = ["desktop", "tablet", "hybrid"]

var PROFILE_DEFINITIONS = [
  { id: "auto", label: "Auto", description: "Follow posture and input capabilities" },
  { id: "desktop", label: "Desktop", description: "Compact pointer-first layout" },
  { id: "tablet", label: "Tablet", description: "Touch-first layout with larger targets" },
  { id: "hybrid", label: "Hybrid", description: "Touch-friendly controls with a keyboard present" },
  { id: "presentation", label: "Presentation", description: "Quiet, conservative presentation behavior" },
  { id: "gaming", label: "Gaming", description: "Low-interference gaming behavior" },
  { id: "custom", label: "Custom", description: "User-defined component policies" }
]

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function bool(value) {
  return value === true || value === 1 || string(value).toLowerCase() === "true" || string(value).toLowerCase() === "yes"
}

function token(value) {
  return string(value).trim().toLowerCase().replace(/[\s_]+/g, "-")
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function normalizedProfile(value) {
  var name = token(value || "auto")
  if (name === "automatic" || name === "default") name = "auto"
  if (name === "presentation-mode") name = "presentation"
  if (PROFILE_IDS.indexOf(name) < 0) return "auto"
  return name
}

function normalizedMode(value) {
  var name = token(value)
  if (name === "computer" || name === "laptop") name = "desktop"
  if (name === "automatic" || name === "auto") return ""
  return MODE_IDS.indexOf(name) >= 0 ? name : ""
}

function profiles() {
  return clone(PROFILE_DEFINITIONS)
}

function adaptiveConfig(config) {
  var source = object(config)
  return isAdaptiveConfig(source) ? source : object(source.adaptive)
}

function isAdaptiveConfig(source) {
  return source.profile !== undefined || source.automaticTransitions !== undefined || source.profiles !== undefined || source.dockedMode !== undefined
}

function normalizeSignals(context) {
  var source = object(context)
  var raw = object(source.signals)
  function value(name, fallback) {
    return raw[name] !== undefined ? raw[name] : (source[name] !== undefined ? source[name] : fallback)
  }
  return {
    touchscreen: bool(value("touchscreen", false)),
    stylus: bool(value("stylus", false)),
    stylusProximity: bool(value("stylusProximity", false)),
    physicalKeyboard: bool(value("physicalKeyboard", false)),
    detachableKeyboard: bool(value("detachableKeyboard", false)),
    bluetoothKeyboard: bool(value("bluetoothKeyboard", false)),
    externalKeyboard: bool(value("externalKeyboard", false)),
    tabletSwitchAvailable: bool(value("tabletSwitchAvailable", false)),
    tabletSwitchActive: bool(value("tabletSwitchActive", false)),
    posture: token(value("posture", "")),
    lidState: token(value("lidState", "")),
    orientation: token(value("orientation", "landscape")) || "landscape",
    lastInput: token(value("lastInput", "keyboard")) || "keyboard",
    externalMonitor: bool(value("externalMonitor", false)),
    externalMonitorCount: Math.max(0, Number(value("externalMonitorCount", 0) || 0)),
    monitorCount: Math.max(0, Number(value("monitorCount", 0) || 0)),
    keyboardCount: Math.max(0, Number(value("keyboardCount", 0) || 0)),
    keyboardStable: value("keyboardStable", true) !== false
  }
}

// This fallback keeps the model useful to the headless CLI and tests. The
// service normally supplies the stronger, debounced TabletMode decision as
// context.baseMode.
function inferMode(signals) {
  var s = normalizeSignals({ signals: signals })
  if (s.tabletSwitchAvailable && s.tabletSwitchActive && s.touchscreen) return "tablet"
  if (s.posture === "tablet" && s.touchscreen) return "tablet"
  if ((s.posture === "tent" || s.posture === "stand") && s.touchscreen) return "hybrid"
  if (s.posture === "laptop") return s.touchscreen ? "hybrid" : "desktop"
  if ((s.lastInput === "touch" || s.lastInput === "stylus" || s.stylusProximity) && s.touchscreen) return "tablet"
  if (s.touchscreen && !s.physicalKeyboard) return "tablet"
  if (s.touchscreen) return "hybrid"
  return "desktop"
}

function sourceMode(context) {
  var source = object(context)
  return normalizedMode(source.baseMode || source.detectedMode) || inferMode(source.signals || source)
}

function currentMode(context, fallback) {
  var source = object(context)
  return normalizedMode(source.currentMode || source.effectiveMode) || fallback
}

function dockedModeOverride(context) {
  var source = object(context)
  var docked = object(source.dockedState)
  if (source.adaptiveEnabled === false || source.automaticTransitions === false || docked.active !== true) return ""
  return normalizedMode(docked.targetMode)
}

function customProfile(config) {
  var adaptive = adaptiveConfig(config)
  var profilesConfig = object(adaptive.profiles)
  var custom = object(profilesConfig.custom)
  var behavior = object(custom.componentBehavior || custom.components)
  return { config: custom, behavior: behavior }
}

function mode(profile, context) {
  var name = normalizedProfile(profile)
  var source = object(context)
  var base = sourceMode(source)
  var previous = currentMode(source, base)
  var followAuto = source.adaptiveEnabled !== false && source.automaticTransitions !== false
  if (name === "desktop" || name === "tablet" || name === "hybrid") return name
  if (name === "custom") {
    var custom = customProfile(source.config || {})
    var customMode = normalizedMode(custom.config.mode)
    if (!customMode) customMode = normalizedMode(custom.behavior.mode || custom.behavior.effectiveMode)
    if (customMode) return customMode
  }
  var docked = dockedModeOverride(source)
  if (name === "auto" && docked) return docked
  return followAuto ? base : previous
}

function modePolicy(effectiveMode) {
  var current = normalizedMode(effectiveMode) || "desktop"
  if (current === "tablet") {
    return {
      mode: current,
      density: "large",
      touchTargetSize: 52,
      osk: "auto",
      oskAutoShow: true,
      dock: "tablet",
      dockReveal: true,
      gestures: "enabled",
      windowControls: "touch",
      snapAssist: true,
      splitView: true,
      rotation: "auto",
      quickSettings: "large",
      overview: "spacious",
      launcher: "comfortable",
      notificationPopups: true,
      notificationDensity: "comfortable",
      effects: "normal",
      previews: true,
      backgroundWork: "normal",
      animations: "enabled",
      animationPreset: "smooth",
      reason: "tablet mode"
    }
  }
  if (current === "hybrid") {
    return {
      mode: current,
      density: "comfortable",
      touchTargetSize: 48,
      osk: "manual",
      oskAutoShow: false,
      dock: "adaptive",
      dockReveal: true,
      gestures: "enabled",
      windowControls: "touch",
      snapAssist: true,
      splitView: true,
      rotation: "auto",
      quickSettings: "comfortable",
      overview: "comfortable",
      launcher: "comfortable",
      notificationPopups: true,
      notificationDensity: "comfortable",
      effects: "normal",
      previews: true,
      backgroundWork: "normal",
      animations: "enabled",
      animationPreset: "smooth",
      reason: "hybrid mode"
    }
  }
  return {
    mode: "desktop",
    density: "compact",
    touchTargetSize: 40,
    osk: "suppressed",
    oskAutoShow: false,
    dock: "desktop",
    dockReveal: true,
    gestures: "conservative",
    windowControls: "optional",
    snapAssist: true,
    splitView: true,
    rotation: "preserve",
    quickSettings: "compact",
    overview: "compact",
    launcher: "compact",
    notificationPopups: true,
    notificationDensity: "compact",
    effects: "normal",
    previews: true,
    backgroundWork: "normal",
    animations: "enabled",
    animationPreset: "smooth",
    reason: "desktop mode"
  }
}

function customValue(behavior, names) {
  for (var i = 0; i < names.length; i++) if (behavior[names[i]] !== undefined) return behavior[names[i]]
  return undefined
}

function normalizeTarget(value, fallback) {
  if (typeof value === "number" && isFinite(value)) return Math.max(40, Math.min(64, Math.round(value)))
  var name = token(value)
  if (name === "small" || name === "compact") return 40
  if (name === "medium" || name === "comfortable") return 48
  if (name === "large" || name === "tablet") return 52
  if (name === "extra-large" || name === "extra-large-touch") return 60
  return fallback
}

function applyBehaviorPolicy(policy, behavior) {
  var source = object(behavior)
  var value
  value = customValue(source, ["density"])
  if (value !== undefined && ["compact", "comfortable", "large"].indexOf(token(value)) >= 0) policy.density = token(value)
  value = customValue(source, ["touchTargetSize", "touchTargets", "targetSize", "touchTarget"])
  if (value !== undefined) policy.touchTargetSize = normalizeTarget(value, policy.touchTargetSize)
  value = customValue(source, ["touchControls", "touchPolicy", "touch"])
  if (value !== undefined) policy.touch = token(typeof value === "object" ? value.mode || value.policy : value) || policy.touch
  value = customValue(source, ["osk", "oskPolicy", "keyboard"])
  if (value !== undefined) {
    if (typeof value === "object") {
      policy.osk = token(value.mode || value.policy || policy.osk)
      if (value.autoShow !== undefined) policy.oskAutoShow = value.autoShow === true
    } else policy.osk = token(value) || policy.osk
  }
  value = customValue(source, ["dock", "dockBehavior"])
  if (value !== undefined) policy.dock = token(typeof value === "object" ? value.mode || value.behavior : value) || policy.dock
  value = customValue(source, ["dockReveal", "revealDock"])
  if (value !== undefined) policy.dockReveal = value === true
  value = customValue(source, ["gestures", "gesturePolicy"])
  if (value !== undefined) policy.gestures = token(value) || policy.gestures
  value = customValue(source, ["windowControls", "windowControlPolicy"])
  if (value !== undefined) policy.windowControls = token(typeof value === "object" ? value.mode || value.policy : value) || policy.windowControls
  value = customValue(source, ["snapAssist", "snap"])
  if (value !== undefined) policy.snapAssist = value === true
  value = customValue(source, ["splitView", "split"])
  if (value !== undefined) policy.splitView = value === true
  value = customValue(source, ["rotation", "rotationPolicy"])
  if (value !== undefined) policy.rotation = token(value) || policy.rotation
  value = customValue(source, ["quickSettings", "quickSettingsDensity"])
  if (value !== undefined) policy.quickSettings = token(value) || policy.quickSettings
  value = customValue(source, ["overview", "overviewDensity"])
  if (value !== undefined) policy.overview = token(value) || policy.overview
  value = customValue(source, ["launcher", "launcherDensity"])
  if (value !== undefined) policy.launcher = token(value) || policy.launcher
  value = customValue(source, ["notificationPopups", "notifications"])
  if (value !== undefined) {
    if (typeof value === "object") {
      if (value.popups !== undefined) policy.notificationPopups = value.popups === true
      if (value.density !== undefined) policy.notificationDensity = token(value.density)
    } else policy.notificationPopups = value === true
  }
  value = customValue(source, ["effects", "effectsPolicy"])
  if (value !== undefined) policy.effects = token(value) || policy.effects
  value = customValue(source, ["previews", "preview"])
  if (value !== undefined) policy.previews = value === true
  value = customValue(source, ["backgroundWork", "work"])
  if (value !== undefined) policy.backgroundWork = token(value) || policy.backgroundWork
  value = customValue(source, ["animations", "animationPolicy"])
  if (value !== undefined) {
    if (typeof value === "boolean") policy.animations = value ? "enabled" : "disabled"
    else policy.animations = token(value) || policy.animations
  }
  value = customValue(source, ["animationPreset", "animationStyle"])
  if (value !== undefined) policy.animationPreset = token(value) || policy.animationPreset
  return policy
}

function applyCustomPolicy(policy, config) {
  return applyBehaviorPolicy(policy, customProfile(config).behavior)
}

function profileBehavior(config, profile) {
  var adaptive = adaptiveConfig(config)
  var profilesConfig = object(adaptive.profiles)
  var profileConfig = object(profilesConfig[normalizedProfile(profile)])
  return object(profileConfig.componentBehavior || profileConfig.components)
}

function applyDockedPolicy(policy, dockedState) {
  var docked = object(dockedState)
  if (docked.active !== true) return policy
  var keepTouch = docked.keepTouch !== false
  policy.docked = true
  policy.dockedProfile = normalizedMode(docked.targetMode) || "desktop"
  policy.dockedKeepTouch = keepTouch
  policy.touch = keepTouch ? "preserve" : "conservative"
  policy.osk = "suppressed"
  policy.oskAutoShow = false
  policy.rotation = token(docked.rotationPolicy || policy.rotation || "preserve")
  policy.reason = "docked mode"
  return policy
}

function accessibilityTarget(config) {
  var source = object(config)
  var accessibility = object(source.accessibility)
  var general = object(source.general)
  var value = accessibility.touchTargetSize
  var target = 0
  if (typeof value === "number" && isFinite(value)) target = value
  else if (["large", "extra-large", "extra-large-touch"].indexOf(token(value)) >= 0) target = token(value) === "large" ? 52 : 60
  else if (token(value) === "comfortable" || token(value) === "medium") target = 48
  if (accessibility.largeUi === true || general.largeUi === true) target = Math.max(target, 48)
  return Math.max(0, Math.min(64, Math.round(target)))
}

function componentPolicy(profile, effectiveMode, config, context) {
  var name = normalizedProfile(profile)
  var current = effectiveMode
  var source = context
  if (effectiveMode && typeof effectiveMode === "object") {
    source = effectiveMode
    current = mode(name, source)
    config = source.config || config
  }
  var policy = modePolicy(current)
  policy.docked = false
  policy.dockedProfile = ""
  policy.dockedKeepTouch = false
  policy.touch = "adaptive"
  if (name === "presentation") {
    policy.gestures = "disabled"
    policy.dockReveal = false
    policy.notificationPopups = false
    policy.effects = "conservative"
    policy.previews = false
    policy.backgroundWork = "minimal"
    policy.reason = "presentation profile"
  } else if (name === "gaming") {
    policy.gestures = "disabled"
    policy.snapAssist = false
    policy.splitView = false
    policy.dockReveal = false
    policy.notificationPopups = false
    policy.effects = "off"
    policy.previews = false
    policy.backgroundWork = "minimal"
    policy.reason = "gaming profile"
  } else if (name === "custom") {
    policy = applyCustomPolicy(policy, config || {})
    policy.reason = "custom profile"
  }
  if (name !== "custom") policy = applyBehaviorPolicy(policy, profileBehavior(config || {}, name))
  var reducedMotion = object(source).reducedMotion === true
  if (reducedMotion) {
    policy.animations = "reduced"
    policy.animationPreset = "minimal"
  }
  policy.mode = normalizedMode(current) || "desktop"
  policy.touchTargetSize = Math.max(normalizeTarget(policy.touchTargetSize, policy.mode === "tablet" ? 52 : policy.mode === "hybrid" ? 48 : 40), accessibilityTarget(config || {}))
  policy.oskAutoShow = policy.osk === "auto" && policy.oskAutoShow !== false
  if (name === "auto") policy = applyDockedPolicy(policy, object(source).dockedState)
  return policy
}

function autoOverrides(profile, effectiveMode, config, context) {
  if (normalizedProfile(profile) !== "auto") return {}
  var source = object(context)
  if (source.adaptiveEnabled === false || source.automaticTransitions === false) return {}
  if (effectiveMode === "desktop") return { "tablet-ui": { enabled: false, reason: object(source).dockedState.active === true ? "Docked mode" : "Automatic desktop mode" } }
  return { "tablet-ui": { enabled: true, reason: "Automatic " + effectiveMode + " mode" } }
}

function effective(profile, config, context) {
  var adaptive = adaptiveConfig(config)
  var source = object(context)
  var selected = normalizedProfile(profile === undefined ? adaptive.profile : profile)
  var enriched = {}
  Object.keys(source).forEach(function(key) { enriched[key] = source[key] })
  enriched.config = config || {}
  enriched.adaptiveEnabled = source.adaptiveEnabled !== undefined ? source.adaptiveEnabled === true : adaptive.enabled !== false
  enriched.automaticTransitions = source.automaticTransitions !== undefined ? source.automaticTransitions === true : adaptive.automaticTransitions !== false
  var base = sourceMode(enriched)
  var previous = currentMode(enriched, base)
  var resolved = mode(selected, enriched)
  var policy = componentPolicy(selected, resolved, config || {}, enriched)
  var docked = object(enriched.dockedState)
  var dockedActive = selected === "auto" && docked.active === true
  return {
    profile: selected,
    sourceMode: base,
    effectiveMode: resolved,
    mode: resolved,
    previousMode: previous,
    changed: previous !== resolved,
    transitioning: source.transitioning === true || source.pending === true,
    adaptiveEnabled: enriched.adaptiveEnabled,
    automaticTransitions: enriched.automaticTransitions,
    automatic: selected === "auto" && enriched.adaptiveEnabled && enriched.automaticTransitions,
    reason: dockedActive ? "docked mode" : selected === "auto" ? (enriched.adaptiveEnabled && enriched.automaticTransitions ? "automatic posture and capability policy" : "automatic transitions disabled") : selected + " profile",
    signals: normalizeSignals(enriched),
    docked: dockedActive,
    dockedState: docked,
    componentPolicy: policy,
    autoOverrides: autoOverrides(selected, resolved, config || {}, enriched)
  }
}

var api = {
  profiles: profiles,
  normalizedProfile: normalizedProfile,
  normalizedMode: normalizedMode,
  inferMode: inferMode,
  mode: mode,
  componentPolicy: componentPolicy,
  autoOverrides: autoOverrides,
  effective: effective
}
if (typeof module !== "undefined") module.exports = api
