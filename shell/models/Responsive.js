function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) && result > 0 ? result : Number(fallback || 1)
}

function clamp(value, minimum, maximum) {
  return Math.max(Number(minimum), Math.min(Number(maximum), Number(value)))
}

function normalizeInput(value) {
  var input = String(value || "keyboard").toLowerCase()
  return ["mouse", "touchpad", "touch", "stylus", "keyboard"].indexOf(input) >= 0 ? input : "keyboard"
}

function orientation(width, height) {
  return Number(height) > Number(width) * 1.05 ? "portrait" : "landscape"
}

// Breakpoints use logical coordinates after fractional scaling rather than a
// single raw framebuffer size. The names describe layout pressure, not a
// device brand or a hard-coded monitor.
function classify(width, height, scale) {
  var factor = number(scale, 1)
  var logicalWidth = number(width, 1280) / factor
  var logicalHeight = number(height, 720) / factor
  var longEdge = Math.max(logicalWidth, logicalHeight)
  var shortEdge = Math.min(logicalWidth, logicalHeight)
  var ratio = longEdge / Math.max(1, shortEdge)
  if (ratio >= 2.1 && logicalWidth >= 1800) return "ultrawide"
  if (shortEdge < 700 || logicalWidth < 1024) return "small-laptop"
  if (longEdge <= 1280 || shortEdge <= 800) return "tablet-compact"
  if (longEdge <= 1600 || shortEdge <= 1000) return "tablet"
  if (longEdge <= 2200 || shortEdge <= 1400) return "large-tablet"
  return "desktop"
}

function targetSize(inputKind, mode, profile, largeUi) {
  var input = normalizeInput(inputKind)
  var currentMode = String(mode || "desktop")
  var result = input === "touch" ? 52 : (input === "stylus" ? 48 : 44)
  if (input === "keyboard" || input === "mouse" || input === "touchpad") result = 40
  if (currentMode === "tablet" || currentMode === "hybrid") result = Math.max(result, 48)
  if (String(profile || "default") === "large") result = Math.max(result, 56)
  if (String(profile || "default") === "extra-large") result = Math.max(result, 64)
  if (largeUi === true) result = Math.max(result, 60)
  return result
}

function columns(width, height, scale, inputKind, mode, minimum) {
  var factor = number(scale, 1)
  var logicalWidth = number(width, 1280) / factor
  var target = Math.max(96, Number(minimum || 144))
  var input = normalizeInput(inputKind)
  if (input === "touch" || input === "stylus" || mode === "tablet") target += 12
  return Math.max(1, Math.floor(logicalWidth / target))
}

function context(width, height, scale, inputKind, mode, settings) {
  var options = settings && typeof settings === "object" ? settings : {}
  var factor = number(scale, 1)
  var logicalWidth = number(width, 1280) / factor
  var logicalHeight = number(height, 720) / factor
  var input = normalizeInput(inputKind)
  var currentMode = String(mode || "desktop")
  var profile = String(options.touchTargetSize || "default")
  var touchLike = input === "touch" || input === "stylus" || currentMode === "tablet"
  var density = touchLike ? 1.08 : 1
  if (profile === "large") density = Math.max(density, 1.14)
  if (profile === "extra-large") density = Math.max(density, 1.22)
  if (options.largeUi === true) density = Math.max(density, 1.16)
  var textScale = clamp(options.textScale || 1, 0.9, 1.5)
  var currentOrientation = orientation(logicalWidth, logicalHeight)
  return {
    breakpoint: classify(width, height, factor),
    orientation: currentOrientation,
    logicalWidth: Math.round(logicalWidth),
    logicalHeight: Math.round(logicalHeight),
    scale: factor,
    input: input,
    mode: currentMode,
    touchLike: touchLike,
    densityScale: density,
    textScale: textScale,
    targetSize: targetSize(input, currentMode, profile, options.largeUi === true),
    gridColumns: columns(width, height, factor, input, currentMode, options.gridMinimum || 144),
    reducedMotion: options.reducedMotion === true,
    reduceTransparency: options.reduceTransparency === true,
    highContrast: options.highContrast === true
  }
}

var api = {
  clamp: clamp,
  normalizeInput: normalizeInput,
  orientation: orientation,
  classify: classify,
  targetSize: targetSize,
  columns: columns,
  context: context
}
if (typeof module !== "undefined") module.exports = api
