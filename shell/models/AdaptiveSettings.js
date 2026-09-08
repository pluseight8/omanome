// Pure data helpers for the Adaptive Mode settings editor.
//
// The editor writes only versioned profile overlays. It never owns hardware
// detection and it never turns a visual preview into a persistent preference.

var PROFILE_IDS = ["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"]

var PROFILE_DEFINITIONS = [
  { id: "auto", label: "Auto", description: "Follow posture, keyboards and device capabilities", automatic: true },
  { id: "desktop", label: "Desktop", description: "Compact pointer-first controls", automatic: false },
  { id: "tablet", label: "Tablet", description: "Touch-first controls with larger targets", automatic: false },
  { id: "hybrid", label: "Hybrid", description: "Touch-friendly controls with a keyboard present", automatic: false },
  { id: "presentation", label: "Presentation", description: "Quiet, conservative notifications and gestures", automatic: false },
  { id: "gaming", label: "Gaming", description: "Low-interference controls and effects", automatic: false },
  { id: "custom", label: "Custom", description: "Your own component and feature policy", automatic: false }
]

var COMPONENT_DEFINITIONS = [
  { id: "dock", key: "dock", label: "Dock", description: "Density and reveal affordance", type: "choice", values: ["desktop", "tablet", "adaptive", "off"], defaults: { desktop: "desktop", tablet: "tablet", hybrid: "adaptive", presentation: "desktop", gaming: "off", custom: "adaptive", auto: "adaptive" } },
  { id: "overview", key: "overview", label: "Overview", description: "Overview card density", type: "choice", values: ["compact", "comfortable", "spacious"], defaults: { desktop: "compact", tablet: "spacious", hybrid: "comfortable", presentation: "compact", gaming: "compact", custom: "comfortable", auto: "comfortable" } },
  { id: "osk", key: "osk", label: "OSK", description: "On-screen keyboard policy", type: "choice", values: ["suppressed", "manual", "auto"], defaults: { desktop: "suppressed", tablet: "auto", hybrid: "manual", presentation: "suppressed", gaming: "suppressed", custom: "manual", auto: "manual" } },
  { id: "touch-controls", key: "touchControls", label: "Touch Controls", description: "Touch window-control affordance", type: "choice", values: ["disabled", "conservative", "adaptive", "always"], defaults: { desktop: "conservative", tablet: "always", hybrid: "adaptive", presentation: "conservative", gaming: "disabled", custom: "adaptive", auto: "adaptive" } },
  { id: "gestures", key: "gestures", label: "Gestures", description: "Gesture coordinator policy", type: "choice", values: ["disabled", "conservative", "enabled"], defaults: { desktop: "conservative", tablet: "enabled", hybrid: "enabled", presentation: "disabled", gaming: "disabled", custom: "enabled", auto: "enabled" } },
  { id: "snap", key: "snapAssist", label: "Snap", description: "Snap Assist affordances", type: "boolean", values: ["on", "off"], defaults: { desktop: true, tablet: true, hybrid: true, presentation: false, gaming: false, custom: true, auto: true } },
  { id: "rotation", key: "rotation", label: "Rotation", description: "Per-profile orientation policy", type: "choice", values: ["preserve", "auto", "locked", "unchanged"], defaults: { desktop: "preserve", tablet: "auto", hybrid: "auto", presentation: "locked", gaming: "preserve", custom: "preserve", auto: "auto" } },
  { id: "effects", key: "effects", label: "Effects", description: "Optional visual effect policy", type: "choice", values: ["off", "conservative", "normal"], defaults: { desktop: "normal", tablet: "normal", hybrid: "normal", presentation: "conservative", gaming: "off", custom: "normal", auto: "normal" } },
  { id: "animations", key: "animations", label: "Animations", description: "Motion policy for Omanome surfaces", type: "choice", values: ["disabled", "reduced", "enabled"], defaults: { desktop: "enabled", tablet: "enabled", hybrid: "enabled", presentation: "reduced", gaming: "disabled", custom: "enabled", auto: "enabled" } }
]

var FEATURE_DEFINITIONS = [
  { id: "touch-mode", label: "Touch Mode" },
  { id: "tablet-ui", label: "Tablet UI" },
  { id: "osk", label: "OSK" },
  { id: "gestures", label: "Gestures" },
  { id: "snap-assist", label: "Snap Assist" },
  { id: "split-view", label: "Split View" },
  { id: "dock", label: "Dock" },
  { id: "window-controls", label: "Window Controls" },
  { id: "rotation", label: "Rotation" },
  { id: "stylus", label: "Stylus" },
  { id: "notifications", label: "Notifications" },
  { id: "clipboard", label: "Clipboard" },
  { id: "effects", label: "Effects" }
]

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function token(value) {
  return string(value).trim().toLowerCase().replace(/[\s_]+/g, "-")
}

function normalizedProfile(value) {
  var name = token(value || "auto")
  if (name === "automatic" || name === "default") name = "auto"
  if (name === "presentation-mode") name = "presentation"
  return PROFILE_IDS.indexOf(name) >= 0 ? name : "auto"
}

function definition(profile) {
  var name = normalizedProfile(profile)
  for (var i = 0; i < PROFILE_DEFINITIONS.length; i++) if (PROFILE_DEFINITIONS[i].id === name) return PROFILE_DEFINITIONS[i]
  return PROFILE_DEFINITIONS[0]
}

function componentDefinition(id) {
  var name = string(id)
  for (var i = 0; i < COMPONENT_DEFINITIONS.length; i++) if (COMPONENT_DEFINITIONS[i].id === name || COMPONENT_DEFINITIONS[i].key === name) return COMPONENT_DEFINITIONS[i]
  return null
}

function adaptiveConfig(config) {
  var source = object(config)
  return object(source.adaptive || source)
}

function storedProfile(config, profile) {
  var adaptive = adaptiveConfig(config)
  var profiles = object(adaptive.profiles)
  return object(profiles[normalizedProfile(profile)])
}

function profileDefaults(profile) {
  var name = normalizedProfile(profile)
  return { mode: name === "auto" || name === "custom" ? "auto" : name, featureOverrides: {}, componentBehavior: {} }
}

function profileConfig(config, profile) {
  var name = normalizedProfile(profile)
  var stored = storedProfile(config, name)
  var behavior = object(stored.componentBehavior || stored.components)
  var features = object(stored.featureOverrides || stored.features)
  var configured = Object.keys(behavior).length > 0 || Object.keys(features).length > 0 || stored.mode !== undefined
  return {
    id: name,
    label: definition(name).label,
    description: definition(name).description,
    mode: token(stored.mode || profileDefaults(name).mode) || "auto",
    componentBehavior: clone(behavior),
    featureOverrides: clone(features),
    configured: configured,
    componentCount: Object.keys(behavior).length,
    featureCount: Object.keys(features).length
  }
}

function profiles(config, selected) {
  var chosen = normalizedProfile(selected)
  return PROFILE_DEFINITIONS.map(function(row) {
    var detail = profileConfig(config, row.id)
    return {
      id: row.id,
      label: row.label,
      description: row.description,
      automatic: row.automatic === true,
      selected: row.id === chosen,
      configured: detail.configured,
      componentCount: detail.componentCount,
      featureCount: detail.featureCount,
      mode: detail.mode
    }
  })
}

function components() {
  return clone(COMPONENT_DEFINITIONS)
}

function features() {
  return clone(FEATURE_DEFINITIONS)
}

function behaviorValue(config, profile, component, fallback) {
  var def = componentDefinition(component)
  if (!def) return fallback
  var detail = profileConfig(config, profile)
  var raw = detail.componentBehavior[def.key]
  if (raw !== undefined) {
    if (def.type === "boolean") return raw === true || token(raw) === "on" || token(raw) === "enabled"
    if (raw && typeof raw === "object") raw = raw.mode || raw.policy || raw.behavior
    var normalized = token(raw)
    if (def.values.indexOf(normalized) >= 0) return normalized
  }
  var defaults = def.defaults || {}
  return defaults[normalizedProfile(profile)] !== undefined ? defaults[normalizedProfile(profile)] : fallback
}

function behaviorConfigured(config, profile, component) {
  var def = componentDefinition(component)
  if (!def) return false
  return profileConfig(config, profile).componentBehavior[def.key] !== undefined
}

function featureValue(config, profile, id, fallback) {
  var detail = profileConfig(config, profile)
  var raw = detail.featureOverrides[string(id)]
  if (raw === undefined) return fallback !== false
  if (raw && typeof raw === "object" && raw.enabled !== undefined) return raw.enabled !== false
  return raw !== false
}

function featureConfigured(config, profile, id) {
  return profileConfig(config, profile).featureOverrides[string(id)] !== undefined
}

function reset(config, profile) {
  var result = clone(config || {})
  if (!object(result.adaptive)) result.adaptive = {}
  if (!object(result.adaptive.profiles)) result.adaptive.profiles = {}
  result.adaptive.profiles[normalizedProfile(profile)] = profileDefaults(profile)
  if (result.schemaVersion !== undefined) result.schemaVersion = Number(result.schemaVersion)
  return result
}

function emptyPreviewState() {
  return { active: false, profile: "", startedAt: 0, expiresAt: 0, reason: "not-previewing", token: 0 }
}

function beginPreview(state, profile, now, durationMs) {
  var current = object(state)
  var started = Number(now || Date.now())
  var duration = Math.max(1000, Math.min(15000, Math.round(Number(durationMs || 6000))))
  return { active: true, profile: normalizedProfile(profile), startedAt: started, expiresAt: started + duration, reason: "temporary profile preview", token: Number(current.token || 0) + 1 }
}

function tickPreview(state, now) {
  var current = object(state)
  if (current.active !== true) return emptyPreviewState()
  if (Number(now || Date.now()) < Number(current.expiresAt || 0)) return clone(current)
  return { active: false, profile: "", startedAt: 0, expiresAt: 0, reason: "preview-expired", token: Number(current.token || 0) }
}

function cancelPreview(state, reason) {
  var current = object(state)
  return { active: false, profile: "", startedAt: 0, expiresAt: 0, reason: string(reason || "preview-cancelled"), token: Number(current.token || 0) }
}

function summary(state, now) {
  var current = tickPreview(state, now)
  return {
    active: current.active === true,
    profile: current.active === true ? current.profile : "",
    remainingMs: current.active === true ? Math.max(0, Number(current.expiresAt || 0) - Number(now || Date.now())) : 0,
    reason: string(current.reason || "not-previewing"),
    token: Number(current.token || 0)
  }
}

var api = {
  profiles: function(config, selected) { return profiles(config, selected) },
  profile: profileConfig,
  profileDefaults: profileDefaults,
  components: components,
  features: features,
  behaviorValue: behaviorValue,
  behaviorConfigured: behaviorConfigured,
  featureValue: featureValue,
  featureConfigured: featureConfigured,
  reset: reset,
  normalizedProfile: normalizedProfile,
  emptyPreviewState: emptyPreviewState,
  beginPreview: beginPreview,
  tickPreview: tickPreview,
  cancelPreview: cancelPreview,
  previewSummary: summary
}
if (typeof module !== "undefined") module.exports = api
