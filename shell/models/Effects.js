var SURFACES = ["dock", "overview", "launcher", "quickSettings", "notifications", "clipboard", "altTab", "osk", "settings", "windowControls", "annotation"]

var QUALITY_PRESETS = {
  quality: { radius: 28, passes: 4, opacity: 0.92, brightness: 0.82, saturation: 1.12, noise: 0.025, vibrancy: 0.12 },
  balanced: { radius: 18, passes: 2, opacity: 0.9, brightness: 0.86, saturation: 1.08, noise: 0.015, vibrancy: 0.06 },
  performance: { radius: 10, passes: 1, opacity: 0.94, brightness: 0.9, saturation: 1.0, noise: 0.0, vibrancy: 0.0 },
  "battery-saver": { radius: 0, passes: 0, opacity: 0.96, brightness: 1.0, saturation: 1.0, noise: 0.0, vibrancy: 0.0 }
}

function clamp(value, minimum, maximum, fallback) {
  var number = Number(value)
  if (!isFinite(number)) number = Number(fallback)
  return Math.max(minimum, Math.min(maximum, number))
}

function object(value) { return value && typeof value === "object" && !Array.isArray(value) ? value : {} }

function qualityName(value) {
  var name = String(value || "balanced").toLowerCase()
  return QUALITY_PRESETS[name] ? name : "balanced"
}

function surfaceConfig(config, surface) {
  var source = object(config)
  var defaults = object(source.defaults)
  var surfaces = object(source.surfaces)
  var selected = object(surfaces[surface])
  var preset = QUALITY_PRESETS[qualityName(selected.quality || source.quality)]
  var result = {}
  Object.keys(preset).forEach(function(key) { result[key] = preset[key] })
  Object.keys(defaults).forEach(function(key) { result[key] = defaults[key] })
  Object.keys(selected).forEach(function(key) { result[key] = selected[key] })
  result.enabled = selected.enabled !== undefined ? selected.enabled !== false : source.enabled !== false
  result.quality = qualityName(selected.quality || source.quality)
  result.radius = Math.round(clamp(result.radius, 0, 64, preset.radius))
  result.passes = Math.round(clamp(result.passes, 0, 6, preset.passes))
  result.opacity = clamp(result.opacity, 0.0, 1.0, preset.opacity)
  result.brightness = clamp(result.brightness, 0.2, 1.5, preset.brightness)
  result.saturation = clamp(result.saturation, 0.0, 2.0, preset.saturation)
  result.noise = clamp(result.noise, 0.0, 0.2, preset.noise)
  result.vibrancy = clamp(result.vibrancy, 0.0, 1.0, preset.vibrancy)
  result.tint = String(result.tint || "")
  result.border = result.border !== false
  result.shadow = result.shadow !== false
  return result
}

function effectiveBlur(config, surface, context) {
  var source = object(context)
  var result = surfaceConfig(config, surface)
  var quality = qualityName(result.quality)
  if (source.batterySaver === true) quality = "battery-saver"
  else if (source.fullscreen === true && source.disableOnFullscreen !== false) quality = "battery-saver"
  else if (source.gpuLoad !== undefined && source.gpuLoad >= Number(source.highGpuThreshold || 0.85)) quality = "performance"
  if (quality !== result.quality) {
    var preset = QUALITY_PRESETS[quality]
    Object.keys(preset).forEach(function(key) { result[key] = preset[key] })
    result.quality = quality
    result.radius = Math.round(preset.radius)
    result.passes = Math.round(preset.passes)
  }
  if (source.reducedMotion === true && source.reduceBlurWithMotion !== false) result.noise = 0.0
  if (source.backendAvailable === false) result.enabled = false
  return result
}

function capabilityState(companion, external) {
  var native = object(companion)
  var other = object(external)
  return {
    blur: native.blur === true,
    livePreview: native.livePreview === true,
    wobblyWindows: native.wobblyWindows === true,
    desktopCube: native.desktopCube === true || other.desktopCube === true,
    desktopCubeBackend: native.desktopCube === true ? "omanome-hypr" : (other.desktopCube === true ? String(other.desktopCubeBackend || "external") : "none")
  }
}

var api = { SURFACES: SURFACES, QUALITY_PRESETS: QUALITY_PRESETS, surfaceConfig: surfaceConfig, effectiveBlur: effectiveBlur, capabilityState: capabilityState }
if (typeof module !== "undefined") module.exports = api
