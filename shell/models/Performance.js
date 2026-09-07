var MODES = ["automatic", "quality", "balanced", "performance", "battery-saver"]

var MODE_POLICY = {
  quality: { animationScale: 1.0, previewStreams: 4, blurPasses: 3, fallbackIntervalMs: 90000 },
  balanced: { animationScale: 1.0, previewStreams: 3, blurPasses: 2, fallbackIntervalMs: 120000 },
  performance: { animationScale: 0.8, previewStreams: 2, blurPasses: 1, fallbackIntervalMs: 180000 },
  "battery-saver": { animationScale: 0.65, previewStreams: 1, blurPasses: 0, fallbackIntervalMs: 300000 }
}

function settingsObject(config) {
  return config && typeof config === "object" ? config : {}
}

function contextObject(context) {
  return context && typeof context === "object" ? context : {}
}

function requestedMode(config) {
  var settings = settingsObject(config)
  var value = String(settings.mode || settings.qualityPreset || settings.performanceMode || "balanced").toLowerCase()
  return MODES.indexOf(value) >= 0 ? value : "balanced"
}

function automaticMode(settings, state) {
  var powerProfile = String(state.powerProfile || "").toLowerCase()
  var thermal = String(state.thermalPressure || "").toLowerCase()
  if (["critical", "high", "serious"].indexOf(thermal) >= 0) return "battery-saver"
  if (["power-saver", "powersave", "battery"].indexOf(powerProfile) >= 0) return "battery-saver"
  if (state.fullscreen === true && settings.disableOnFullscreen !== false) return "battery-saver"
  if (state.gpuLoad !== undefined && settings.adaptiveQuality !== false && Number(state.gpuLoad) >= Number(settings.highGpuThreshold || 0.85)) return "performance"
  if (powerProfile === "performance" || state.onAc === true) return "quality"
  return "balanced"
}

function mode(config, context) {
  var settings = settingsObject(config)
  var state = contextObject(context)
  var selected = requestedMode(settings)
  if (selected === "automatic") selected = automaticMode(settings, state)
  if (state.safeMode === true) return "battery-saver"
  if (state.batterySaver === true && settings.disableOnBattery !== false) return "battery-saver"
  if (state.fullscreen === true && settings.disableOnFullscreen !== false && String(settings.fullscreenPolicy || "battery-saver") === "battery-saver") return "battery-saver"
  if (state.gpuLoad !== undefined && settings.adaptiveQuality !== false && Number(state.gpuLoad) >= Number(settings.highGpuThreshold || 0.85) && selected !== "battery-saver") return "performance"
  return selected
}

function quality(config, context) {
  var settings = config && typeof config === "object" ? config : {}
  var state = context && typeof context === "object" ? context : {}
  return mode(settings, state)
}

function effectsEnabled(config, context) {
  var settings = config && typeof config === "object" ? config : {}
  var state = context && typeof context === "object" ? context : {}
  if (settings.enabled === false) return false
  return mode(settings, state) !== "battery-saver"
}

function snapshot(config, context) {
  var settings = settingsObject(config)
  var activeMode = mode(settings, context)
  var policy = MODE_POLICY[activeMode]
  return {
    requestedMode: requestedMode(settings),
    mode: activeMode,
    quality: activeMode,
    effectsEnabled: effectsEnabled(settings, context),
    animationScale: policy.animationScale,
    previewStreams: policy.previewStreams,
    blurPasses: policy.blurPasses,
    fallbackIntervalMs: policy.fallbackIntervalMs,
    gpuLoadSource: String(settings.gpuLoadSource || "backend-only")
  }
}

var api = { MODES: MODES, requestedMode: requestedMode, automaticMode: automaticMode, mode: mode, quality: quality, effectsEnabled: effectsEnabled, snapshot: snapshot }
if (typeof module !== "undefined") module.exports = api
