// Pure planning for real Hyprland floating-window actions.  The service owns
// dispatch and rollback; this module only validates bounded geometry and
// produces address-scoped commands.

var FLOATING_SCHEMA_VERSION = 1
var MAX_COMMANDS = 5
var MIN_WIDTH = 240
var MIN_HEIGHT = 160
var MAX_WIDTH = 1200
var MAX_HEIGHT = 900

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {} }

function text(value, fallback, limit) {
  var result = String(value === undefined || value === null ? (fallback || "") : value).trim()
  return result.slice(0, Math.max(1, Number(limit || 96)))
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}

function clamp(value, minimum, maximum) { return Math.max(minimum, Math.min(maximum, value)) }

function address(value) {
  var source = text(value, "", 96)
  if (source.indexOf("address:") === 0) source = source.substring(8)
  return /^[0-9a-fA-Fx]+$/.test(source) ? source : ""
}

function pid(value) {
  var result = Math.round(number(value, 0))
  return result > 0 ? result : 0
}

function appId(window) {
  var item = object(window && window.wayland ? window.wayland : window)
  return text(item.appId || item.app_id || item.desktopId || item.desktopFile || item.class || item.initialClass || "", "", 128).replace(/\.desktop$/, "")
}

function identity(window) {
  var item = object(window && window.wayland ? window.wayland : window)
  var explicit = text(item.identity, "", 96)
  if (explicit.indexOf("address:") === 0 || explicit.indexOf("pid:") === 0) return explicit
  var rawAddress = address(item.address)
  if (rawAddress) return "address:" + rawAddress
  var rawPid = pid(item.pid)
  return rawPid > 0 ? "pid:" + rawPid : ""
}

function rect(value) {
  var item = object(value)
  return {
    x: Math.round(number(item.x, 0)),
    y: Math.round(number(item.y, 0)),
    width: Math.max(0, Math.round(number(item.width, 0))),
    height: Math.max(0, Math.round(number(item.height, 0)))
  }
}

function monitorName(monitor) {
  var item = object(monitor)
  return text(item.name || item.monitor || item.id || "active", "active", 96)
}

function monitorRect(monitor) {
  var item = object(monitor)
  var usable = object(item.usable)
  if (number(usable.width, 0) > 0 && number(usable.height, 0) > 0) return rect(usable)
  var source = rect(item)
  return { x: source.x, y: source.y, width: source.width, height: source.height }
}

function bool(value) { return value === true || value === 1 || String(value || "").toLowerCase() === "true" }

function roleIsPip(window) {
  var item = object(window && window.wayland ? window.wayland : window)
  var role = text(item.role || item.windowRole || item.layer || "", "", 64).toLowerCase()
  return bool(item.pip) || bool(item.pictureInPicture) || ["pip", "picture-in-picture", "picture_in_picture"].indexOf(role) >= 0
}

function normalizeWindow(window) {
  var item = object(window && window.wayland ? window.wayland : window)
  var geometry = rect(item.geometry || item.rect)
  return {
    schemaVersion: FLOATING_SCHEMA_VERSION,
    identity: identity(window),
    appId: appId(window),
    floating: bool(item.floating),
    mini: bool(item.mini) || bool(item.compact),
    pip: roleIsPip(window),
    keepAbove: bool(item.pinned) || bool(item.alwaysOnTop) || bool(item.keepAbove),
    monitor: monitorName(item.monitorName || item.monitor),
    geometry: geometry
  }
}

function selector(window) {
  var value = address(window && window.address !== undefined ? window.address : window)
  return value ? "address:" + value : ""
}

function command(name, window) {
  var target = selector(window)
  return target ? String(name || "") + " " + target : ""
}

function sizeFor(area, options, mode) {
  var settings = object(options)
  var source = object(settings[mode + "Size"] || settings.size)
  var width = source.width > 0 ? number(source.width, 0) : area.width * (mode === "pip" ? 0.34 : 0.42)
  var height = source.height > 0 ? number(source.height, 0) : area.height * (mode === "pip" ? 0.30 : 0.34)
  return {
    width: Math.round(clamp(width, MIN_WIDTH, Math.min(MAX_WIDTH, area.width))),
    height: Math.round(clamp(height, MIN_HEIGHT, Math.min(MAX_HEIGHT, area.height)))
  }
}

function targetRect(monitor, options, mode) {
  var area = monitorRect(monitor)
  var settings = object(options)
  var size = sizeFor(area, settings, mode)
  var margin = Math.max(0, Math.round(number(settings.margin, number(settings.gap, 12))))
  var corner = text(settings.corner, "bottom-right", 32)
  var x = area.x + area.width - size.width - margin
  var y = area.y + area.height - size.height - margin
  if (corner.indexOf("left") >= 0) x = area.x + margin
  if (corner.indexOf("top") >= 0) y = area.y + margin
  return {
    x: Math.round(clamp(x, area.x, Math.max(area.x, area.x + area.width - size.width))),
    y: Math.round(clamp(y, area.y, Math.max(area.y, area.y + area.height - size.height))),
    width: size.width,
    height: size.height
  }
}

function geometryCommands(window, target) {
  var targetAddress = selector(window)
  if (!targetAddress || !target) return []
  return [
    "resizewindowpixel exact " + target.width + " " + target.height + "," + targetAddress,
    "movewindowpixel exact " + target.x + " " + target.y + "," + targetAddress
  ]
}

function basePlan(window, mode, monitor, options) {
  var state = normalizeWindow(window)
  var targetMode = mode === "pip" ? "pip" : "mini"
  var commands = []
  var rollback = []
  if (!state.identity || !selector(window)) return { ok: false, reason: "window-address-required", mode: targetMode, commands: [], rollback: [] }
  if (!state.floating) {
    var toggle = command("togglefloating", window)
    if (toggle) {
      commands.push(toggle)
      rollback.unshift(toggle)
    }
  }
  var target = targetRect(monitor, options, targetMode)
  commands = commands.concat(geometryCommands(window, target))
  if (targetMode === "pip" && object(options).keepAbove !== false) {
    var pin = command("pin", window)
    if (pin) commands.push(pin)
  }
  if (commands.length > MAX_COMMANDS) commands = commands.slice(0, MAX_COMMANDS)
  return {
    ok: commands.length > 0,
    reason: commands.length > 0 ? "planned" : "no-command",
    schemaVersion: FLOATING_SCHEMA_VERSION,
    mode: targetMode,
    identity: state.identity,
    appId: state.appId,
    monitor: monitorName(monitor),
    target: target,
    commands: commands,
    rollback: rollback.slice(0, MAX_COMMANDS)
  }
}

function toggleFloating(window) {
  var state = normalizeWindow(window)
  var value = command("togglefloating", window)
  if (!state.identity || !value) return { ok: false, reason: "window-address-required", commands: [], rollback: [] }
  return { ok: true, reason: "planned", schemaVersion: FLOATING_SCHEMA_VERSION, mode: "toggle", identity: state.identity, appId: state.appId, commands: [value], rollback: [value] }
}

function mini(window, monitor, options) { return basePlan(window, "mini", monitor, options) }

function pip(window, monitor, options) { return basePlan(window, "pip", monitor, options) }

function persistablePosition(window, monitor, geometry) {
  var state = normalizeWindow(window)
  var area = monitorRect(monitor)
  var target = rect(geometry)
  if (!state.appId || area.width <= 0 || area.height <= 0 || target.width <= 0 || target.height <= 0) return null
  return {
    appId: state.appId,
    monitor: monitorName(monitor),
    x: clamp((target.x - area.x) / area.width, 0, 1),
    y: clamp((target.y - area.y) / area.height, 0, 1),
    width: clamp(target.width / area.width, 0, 1),
    height: clamp(target.height / area.height, 0, 1)
  }
}

var api = {
  FLOATING_SCHEMA_VERSION: FLOATING_SCHEMA_VERSION,
  MAX_COMMANDS: MAX_COMMANDS,
  normalizeWindow: normalizeWindow,
  toggleFloating: toggleFloating,
  mini: mini,
  pip: pip,
  targetRect: targetRect,
  persistablePosition: persistablePosition
}
if (typeof module !== "undefined") module.exports = api
