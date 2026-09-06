var DIRECTIONS = ["left", "right", "previous", "next"]

function object(value) { return value && typeof value === "object" ? value : {} }

function normalize(config) {
  var source = object(config)
  return {
    enabled: source.enabled === true,
    backend: String(source.backend || "detect"),
    monitorMode: String(source.monitorMode || "active-monitor"),
    touchInteractive: source.touchInteractive !== false,
    touchpadOverride: source.touchpadOverride === true,
    mouseDrag: source.mouseDrag !== false,
    stylusDrag: source.stylusDrag !== false,
    animationDuration: Math.max(0, Math.min(2000, Number(source.animationDuration || 420)))
  }
}

function available(config, capabilities) {
  return normalize(config).enabled && object(capabilities).desktopCube === true
}

function lua(action, value) {
  var name = String(action || "")
  if (name === "toggle" || name === "close" || name === "reload") return "hl.plugin.desktop_cube." + name + "()"
  if (name === "overview") return "hl.plugin.desktop_cube.overview(" + (value === true ? "true" : "false") + ")"
  if (name === "rotate") {
    var rotation = Number(value)
    if (!isFinite(rotation)) rotation = 0
    return "hl.plugin.desktop_cube.rotate(" + Math.max(-1, Math.min(1, Math.round(rotation))) + ")"
  }
  if (name === "pitch") {
    var pitch = Number(value)
    if (!isFinite(pitch)) pitch = 0
    return "hl.plugin.desktop_cube.pitch(" + Math.max(-1, Math.min(1, pitch)).toFixed(4) + ")"
  }
  if (name === "select") {
    if (value === undefined) return "hl.plugin.desktop_cube.select()"
    var index = Number(value)
    if (!isFinite(index)) return ""
    return "hl.plugin.desktop_cube.select(" + Math.max(0, Math.floor(index)) + ")"
  }
  if (name === "workspace" && DIRECTIONS.indexOf(String(value)) >= 0) return "hl.plugin.desktop_cube.workspace(\"" + String(value) + "\")"
  return ""
}

function state(config, capabilities) {
  var options = normalize(config)
  var caps = object(capabilities)
  var isAvailable = available(config, caps)
  return {
    configured: options.enabled,
    available: isAvailable,
    enabled: isAvailable,
    backend: isAvailable ? String(caps.desktopCubeBackend || "omarchy-desktop-cube") : "none",
    reason: isAvailable ? "external compositor cube API" : (options.enabled ? "external compositor cube is not loaded" : "disabled in configuration")
  }
}

var api = { DIRECTIONS: DIRECTIONS, normalize: normalize, available: available, lua: lua, state: state }
if (typeof module !== "undefined") module.exports = api
