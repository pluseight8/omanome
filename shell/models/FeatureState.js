// One source of truth for Omanome feature availability and effective state.
//
// The registry is deliberately a pure model. QML, the headless service and
// the CLI can use the same precedence rules without one surface silently
// changing another surface's user preference.

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function bool(value) {
  return value === true || value === 1 || string(value).toLowerCase() === "true"
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function getPath(source, path, fallback) {
  var current = source
  var parts = string(path).split(".")
  for (var i = 0; i < parts.length; i++) {
    if (!current || current[parts[i]] === undefined) return fallback
    current = current[parts[i]]
  }
  return current
}

var FEATURE_DEFINITIONS = [
  { id: "touch-mode", label: "Touch Mode", configPath: "touch.enabled", availability: "touch", defaultEnabled: true },
  { id: "tablet-ui", label: "Tablet UI", configPath: "tabletMode.enabled", availability: "tablet", defaultEnabled: true },
  { id: "osk", label: "OSK", configPath: "keyboard.enabled", availability: "osk", defaultEnabled: true },
  { id: "gestures", label: "Gestures", configPath: "multitasking.gestures.enabled", availability: "gestures", defaultEnabled: true },
  { id: "snap-assist", label: "Snap Assist", configPath: "multitasking.snapAssist.enabled", availability: "compositor", defaultEnabled: true },
  { id: "split-view", label: "Split View", configPath: "multitasking.splitView.enabled", availability: "compositor", defaultEnabled: true },
  { id: "dock", label: "Dock", configPath: "dock.enabled", availability: "compositor", defaultEnabled: true },
  { id: "window-controls", label: "Window Controls", configPath: "windowControls.enabled", availability: "compositor", defaultEnabled: true },
  { id: "rotation", label: "Rotation", configPath: "rotation.enabled", availability: "rotation", defaultEnabled: true },
  { id: "stylus", label: "Stylus", configPath: "stylus.enabled", availability: "stylus", defaultEnabled: true },
  { id: "notifications", label: "Notifications", configPath: "notifications.enabled", availability: "notifications", defaultEnabled: true },
  { id: "clipboard", label: "Clipboard", configPath: "clipboard.enabled", availability: "clipboard", defaultEnabled: true },
  { id: "effects", label: "Effects", configPath: "effects.enabled", availability: "effects", defaultEnabled: true }
]

var BUILTIN_PROFILE_OVERRIDES = {
  auto: {},
  desktop: {},
  tablet: {},
  hybrid: {},
  presentation: {
    gestures: { enabled: false, reason: "Presentation profile" },
    "snap-assist": { enabled: false, reason: "Presentation profile" },
    "split-view": { enabled: false, reason: "Presentation profile" },
    notifications: { enabled: false, reason: "Presentation profile" },
    effects: { enabled: false, reason: "Presentation profile" }
  },
  gaming: {
    gestures: { enabled: false, reason: "Gaming profile" },
    "snap-assist": { enabled: false, reason: "Gaming profile" },
    "split-view": { enabled: false, reason: "Gaming profile" },
    notifications: { enabled: false, reason: "Gaming profile" },
    effects: { enabled: false, reason: "Gaming profile" }
  },
  custom: {}
}

var DEFAULT_UNAVAILABLE_REASONS = {
  touch: "No touchscreen or touchpad detected",
  tablet: "No touchscreen or tablet posture signal",
  osk: "No text-input backend available",
  gestures: "No touch-capable input detected",
  rotation: "No rotation backend available",
  stylus: "No stylus detected",
  effects: "Effect backend unavailable",
  compositor: "Compositor integration unavailable",
  notifications: "Notification integration unavailable",
  clipboard: "Clipboard integration unavailable"
}

function normalizedProfile(value) {
  var name = string(value || "auto").toLowerCase().replace(/[\s_]+/g, "-")
  if (name === "automatic" || name === "default") name = "auto"
  if (name === "presentation-mode") name = "presentation"
  if (["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"].indexOf(name) < 0) return "auto"
  return name
}

function definition(id) {
  var name = string(id)
  for (var i = 0; i < FEATURE_DEFINITIONS.length; i++) {
    if (FEATURE_DEFINITIONS[i].id === name) return FEATURE_DEFINITIONS[i]
  }
  return null
}

function definitions() {
  return clone(FEATURE_DEFINITIONS)
}

function availabilityFor(def, context) {
  var source = object(context)
  var explicit = object(source.availability)
  var direct = explicit[def.id]
  if (direct !== undefined) {
    if (typeof direct === "object") {
      return { available: direct.available !== false, reason: string(direct.reason || "") }
    }
    return { available: bool(direct), reason: string(source.availabilityReasons && source.availabilityReasons[def.id] || "") }
  }

  var capabilities = object(source.capabilities)
  var available = true
  if (def.availability === "touch") available = bool(capabilities.touchscreen) || bool(capabilities.touchpad) || bool(capabilities.touch)
  else if (def.availability === "tablet") available = bool(capabilities.touchscreen) || bool(capabilities.tabletSwitch) || bool(capabilities.stylus)
  else if (def.availability === "osk") available = capabilities.osk !== false && capabilities.textInput !== false
  else if (def.availability === "gestures") available = bool(capabilities.touchscreen) || bool(capabilities.touchpad) || bool(capabilities.touch)
  else if (def.availability === "rotation") available = bool(capabilities.rotation) || bool(source.rotationAvailable)
  else if (def.availability === "stylus") available = bool(capabilities.stylus)
  else if (def.availability === "effects") available = capabilities.effects !== false && source.effectsAvailable !== false
  else if (def.availability === "compositor") available = source.compositorAvailable !== false
  else if (def.availability === "notifications") available = source.notificationsAvailable !== false
  else if (def.availability === "clipboard") available = source.clipboardAvailable !== false

  return { available: available, reason: available ? "" : string(DEFAULT_UNAVAILABLE_REASONS[def.availability] || "Feature unavailable") }
}

function profileOverrides(profile, config) {
  var name = normalizedProfile(profile)
  var result = clone(BUILTIN_PROFILE_OVERRIDES[name] || {})
  if (name !== "custom") return result
  var adaptive = object(object(config).adaptive)
  var profiles = object(adaptive.profiles)
  var custom = object(profiles.custom)
  var customOverrides = object(custom.featureOverrides || custom.features)
  Object.keys(customOverrides).forEach(function(id) {
    var value = customOverrides[id]
    if (typeof value === "boolean") result[id] = { enabled: value, reason: "Custom profile" }
    else if (typeof value === "object" && value.enabled !== undefined)
      result[id] = { enabled: value.enabled !== false, reason: string(value.reason || "Custom profile") }
  })
  return result
}

function accessibilityOverride(id, context) {
  var accessibility = object(object(context).accessibility)
  if (accessibility.reducedMotion === true && id === "effects")
    return { enabled: false, reason: "Accessibility reduced motion" }
  return null
}

function autoOverride(id, context) {
  var overrides = object(object(context).autoOverrides)
  var value = overrides[id]
  if (value === undefined) return null
  if (typeof value === "boolean") return { enabled: value, reason: "Automatic mode" }
  if (typeof value === "object" && value.enabled !== undefined)
    return { enabled: value.enabled !== false, reason: string(value.reason || "Automatic mode") }
  return null
}

function safetyReason(context) {
  var source = object(context)
  if (source.safeMode === true) return "Safe Mode"
  if (source.suspended === true) return "Omanome is suspended"
  if (source.masterEnabled === false) return "Omanome master toggle is off"
  return ""
}

function stateFor(def, context, profileMap) {
  var source = object(context)
  var availability = availabilityFor(def, source)
  var userValue = getPath(source.config, def.configPath, def.defaultEnabled)
  var userEnabled = userValue !== false
  var profile = normalizedProfile(source.profile || getPath(source.config, "adaptive.profile", "auto"))
  var profileOverride = profileMap[def.id] || null
  var accessibility = accessibilityOverride(def.id, source)
  var automatic = autoOverride(def.id, source)
  var reason = ""
  var effectiveEnabled = userEnabled
  var temporarilySuppressed = false
  var overrideSource = "user"
  var safety = safetyReason(source)

  // Precedence is intentional and acyclic: safety, accessibility, manual,
  // profile, auto mode, then the feature default.
  if (safety) {
    effectiveEnabled = false
    reason = safety
    temporarilySuppressed = true
    overrideSource = "safety"
  } else if (!availability.available) {
    effectiveEnabled = false
    reason = availability.reason
    overrideSource = "availability"
  } else if (accessibility) {
    effectiveEnabled = accessibility.enabled === true
    reason = accessibility.reason
    temporarilySuppressed = true
    overrideSource = "accessibility"
  } else if (!userEnabled) {
    effectiveEnabled = false
    reason = "Disabled by user"
    overrideSource = "user"
  } else if (profileOverride) {
    effectiveEnabled = profileOverride.enabled === true
    reason = string(profileOverride.reason || (profile + " profile"))
    temporarilySuppressed = true
    overrideSource = "profile"
  } else if (automatic) {
    effectiveEnabled = automatic.enabled === true
    reason = automatic.reason
    temporarilySuppressed = true
    overrideSource = "automatic"
  } else {
    effectiveEnabled = def.defaultEnabled !== false
    overrideSource = "default"
  }

  if (effectiveEnabled) reason = ""
  return {
    id: def.id,
    label: def.label,
    configPath: def.configPath,
    available: availability.available === true,
    enabled: effectiveEnabled === true,
    userEnabled: userEnabled,
    effectiveEnabled: effectiveEnabled === true,
    disabledReason: reason,
    temporarilySuppressed: temporarilySuppressed,
    profileOverride: profileOverride ? { enabled: profileOverride.enabled === true, profile: profile, reason: string(profileOverride.reason || "") } : null,
    overrideSource: overrideSource,
    profile: profile
  }
}

function registry(context) {
  var source = object(context)
  var profile = normalizedProfile(source.profile || getPath(source.config, "adaptive.profile", "auto"))
  var overrides = profileOverrides(profile, source.config)
  var rows = []
  for (var i = 0; i < FEATURE_DEFINITIONS.length; i++) rows.push(stateFor(FEATURE_DEFINITIONS[i], source, overrides))
  return rows
}

function state(context, id) {
  var rows = registry(context)
  for (var i = 0; i < rows.length; i++) if (rows[i].id === string(id)) return rows[i]
  return null
}

function canToggle(row) {
  return !!row && row.available === true && row.overrideSource !== "safety" && row.overrideSource !== "availability"
}

function summary(context) {
  var rows = registry(context)
  var active = 0
  var available = 0
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].available) available++
    if (rows[i].effectiveEnabled) active++
  }
  return { total: rows.length, available: available, active: active, partial: active > 0 && active < available, states: rows }
}

var api = {
  definitions: definitions,
  normalizedProfile: normalizedProfile,
  availabilityFor: availabilityFor,
  profileOverrides: profileOverrides,
  registry: registry,
  state: state,
  canToggle: canToggle,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
