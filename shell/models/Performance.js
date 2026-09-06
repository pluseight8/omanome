function quality(config, context) {
  var settings = config && typeof config === "object" ? config : {}
  var state = context && typeof context === "object" ? context : {}
  if (state.batterySaver === true && settings.batterySaverMode !== false) return "battery-saver"
  if (state.fullscreen === true && settings.fullscreenPolicy === "battery-saver") return "battery-saver"
  if (state.gpuLoad !== undefined && settings.adaptiveQuality !== false && Number(state.gpuLoad) >= Number(settings.highGpuThreshold || 0.85)) return "performance"
  return String(settings.qualityPreset || settings.performanceMode || "balanced")
}

function effectsEnabled(config, context) {
  var settings = config && typeof config === "object" ? config : {}
  var state = context && typeof context === "object" ? context : {}
  if (settings.enabled === false) return false
  if (state.batterySaver === true && settings.disableOnBattery === true) return false
  if (state.fullscreen === true && settings.disableOnFullscreen === true) return false
  if (state.safeMode === true) return false
  return true
}

function snapshot(config, context) {
  return { quality: quality(config, context), effectsEnabled: effectsEnabled(config, context), gpuLoadSource: String((config || {}).gpuLoadSource || "backend-only") }
}

var api = { quality: quality, effectsEnabled: effectsEnabled, snapshot: snapshot }
if (typeof module !== "undefined") module.exports = api
