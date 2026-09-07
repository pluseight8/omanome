function text(value) { return String(value === undefined || value === null ? "" : value).toLowerCase() }

function token(value) {
  return text(value).replace(/[_\s]+/g, "-")
}

function capabilityBag(device) {
  var item = device || {}
  var source = item.capabilities || item.capability || item.features || {}
  var bag = {}
  if (Array.isArray(source)) {
    for (var i = 0; i < source.length; i++) bag[token(source[i])] = true
  } else if (source && typeof source === "object") {
    for (var key in source) {
      if (source[key] === true || source[key] === 1 || Number(source[key]) > 0)
        bag[token(key)] = true
    }
  }
  var aliases = {
    pressure: ["pressure", "pressure-range", "pressurerange", "pressureaxis", "pressure-axis"],
    tiltX: ["tiltx", "tilt-x", "tilt_x"],
    tiltY: ["tilty", "tilt-y", "tilt_y"],
    rotation: ["rotation", "wheel", "twist"],
    distance: ["distance", "z", "distance-axis"],
    proximity: ["proximity", "hover", "in-proximity"],
    eraser: ["eraser", "rubber"],
    buttons: ["buttons", "barrel-buttons", "side-buttons"],
    touch: ["touch", "touchscreen", "touch-screen"],
    keyboard: ["keyboard", "keys"]
  }
  var result = {}
  for (var normalized in aliases) {
    result[normalized] = false
    var names = aliases[normalized]
    for (var n = 0; n < names.length; n++) {
      if (bag[token(names[n])]) { result[normalized] = true; break }
    }
  }
  return result
}

function explicitTypes(device) {
  var item = device || {}
  var values = [item.type, item.deviceType, item.kind, item.inputType, item.toolType, item.tool_type, item.libinputType]
  var result = []
  for (var i = 0; i < values.length; i++) {
    var value = token(values[i])
    if (value && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function hasType(device, accepted) {
  var types = explicitTypes(device)
  for (var i = 0; i < types.length; i++) if (accepted.indexOf(types[i]) >= 0) return true
  return false
}

function isTouchscreen(device, sourceKind) {
  if (!device) return false
  var caps = capabilityBag(device)
  if (hasType(device, ["touchpad", "trackpad", "tablet-pad"])) return false
  if (sourceKind === "touch") return true
  if (hasType(device, ["touchscreen", "touch-screen", "touch-display", "touch"])) return true
  return caps.touch === true && !hasType(device, ["tablet-tool", "tablet-tool-pen", "stylus", "eraser"])
}

function isTabletPad(device) {
  return Boolean(device) && hasType(device, ["tablet-pad", "tabletpad", "pad"])
}

function isStylus(device, sourceKind) {
  if (!device) return false
  var caps = capabilityBag(device)
  if (sourceKind === "tablet" || sourceKind === "tablet-tool") return !isTabletPad(device)
  var accepted = ["tablet", "tablet-tool", "tablettool", "stylus", "pen", "eraser", "airbrush", "cursor"]
  if (hasType(device, accepted)) return true
  if (caps.pressure || caps.tiltX || caps.tiltY || caps.rotation || caps.distance || caps.proximity || caps.eraser)
    return !caps.touch
  return false
}

function buttonCount(device, caps) {
  var item = device || {}
  var value = item.buttonCount
  if (value === undefined) value = item.buttons
  if (Array.isArray(value)) return value.length
  if (Number(value) >= 0) return Number(value)
  return caps.buttons ? 1 : 0
}

function capabilities(device) {
  var item = device || {}
  var caps = capabilityBag(item)
  var tool = token(item.toolType || item.tool_type || item.type || "unknown")
  var serial = item.serial !== undefined ? item.serial : (item.toolSerial !== undefined ? item.toolSerial : item.tool_serial)
  var output = item.output || item.mappedOutput || item.mapped_output || item.belongsTo || item.belongs_to || ""
  return {
    pressure: caps.pressure || item.pressure === true || item.pressureMin !== undefined || item.pressure_max !== undefined,
    tiltX: caps.tiltX || item.tiltX === true || item.tilt_x === true,
    tiltY: caps.tiltY || item.tiltY === true || item.tilt_y === true,
    tilt: caps.tiltX || caps.tiltY || item.tiltX === true || item.tiltY === true,
    rotation: caps.rotation || item.rotation === true,
    distance: caps.distance || item.distance === true,
    proximity: caps.proximity || item.proximity === true || item.hover === true,
    eraser: caps.eraser || item.eraser === true || tool === "eraser" || tool === "rubber",
    buttons: buttonCount(item, caps),
    barrelButtons: buttonCount(item, caps) > 0,
    toolType: tool || "unknown",
    serial: serial === undefined || serial === null ? "" : String(serial),
    output: String(output || ""),
    backend: String(item.backend || item.protocol || item.source || "unknown")
  }
}

function normalizeDevice(device, fallbackBackend) {
  var item = device || {}
  var caps = capabilities(item)
  return {
    id: String(item.id || item.address || item.identifier || item.name || "unknown"),
    name: String(item.name || item.device || item.identifier || "Unnamed input device"),
    type: String(item.type || item.deviceType || item.kind || "unknown"),
    backend: caps.backend === "unknown" ? String(fallbackBackend || "unknown") : caps.backend,
    output: caps.output,
    capabilities: caps,
    raw: item
  }
}

function classify(devices, fallbackBackend) {
  var list = Array.isArray(devices) ? devices : []
  var result = []
  for (var i = 0; i < list.length; i++) {
    if (!isStylus(list[i])) continue
    result.push(normalizeDevice(list[i], fallbackBackend))
  }
  return result
}

function isPhysicalKeyboard(device) {
  if (!device) return false
  var caps = capabilityBag(device)
  var name = token(device.name || device.device || device.identifier)
  if (hasType(device, ["consumer-control", "system-control", "power-button", "switch", "gamepad", "joystick", "tablet-pad"])) return false
  if (name.indexOf("consumer-control") >= 0 || name.indexOf("system-control") >= 0 || name.indexOf("power-button") >= 0) return false
  if (caps.keyboard || hasType(device, ["keyboard", "keyboards"])) return true
  if (name === "keyboard" || name.slice(-9) === "-keyboard") return true
  return device.main === true && !isStylus(device) && !isTouchscreen(device)
}

function classifyKeyboards(devices) {
  var list = Array.isArray(devices) ? devices : []
  var result = []
  for (var i = 0; i < list.length; i++) if (isPhysicalKeyboard(list[i])) result.push(normalizeDevice(list[i], "hyprland"))
  return result
}

function keyboardTransport(device) {
  var item = device || {}
  var values = [item.transport, item.connection, item.bus, item.backend, item.protocol, item.type]
  for (var i = 0; i < values.length; i++) {
    var value = token(values[i])
    if (value) return value
  }
  return "unknown"
}

function isBluetoothKeyboard(device) {
  if (!isPhysicalKeyboard(device)) return false
  var value = keyboardTransport(device)
  var name = token(device && (device.name || device.device || device.identifier))
  return value.indexOf("bluetooth") >= 0 || value.indexOf("bluez") >= 0 || name.indexOf("bluetooth") >= 0
}

function isDetachableKeyboard(device) {
  if (!isPhysicalKeyboard(device)) return false
  var item = device || {}
  var value = token(item.formFactor || item.connection || item.transport || item.role || item.type)
  return item.detachable === true || item.detachableKeyboard === true || value.indexOf("detachable") >= 0 || value.indexOf("tablet-keyboard") >= 0
}

function diagnostics(device, fallbackBackend) {
  var item = normalizeDevice(device, fallbackBackend)
  var caps = item.capabilities
  return {
    id: item.id,
    name: item.name,
    type: item.type,
    backend: item.backend,
    mappedOutput: item.output || "automatic",
    pressure: caps.pressure,
    tiltX: caps.tiltX,
    tiltY: caps.tiltY,
    rotation: caps.rotation,
    distance: caps.distance,
    proximity: caps.proximity,
    eraser: caps.eraser,
    buttons: caps.buttons,
    toolType: caps.toolType,
    serial: caps.serial
  }
}

var buttonActions = [
  "right-click", "middle-click", "back", "forward", "eraser", "screenshot", "annotation", "overview", "launcher",
  "quicksettings", "clipboard", "keyboard", "handwriting", "undo", "redo", "copy", "paste", "custom", "disabled"
]

function normalizeButtonMap(map) {
  var source = map || {}
  var result = {}
  var keys = ["primary", "secondary", "tertiary", "eraser"]
  for (var i = 0; i < keys.length; i++) {
    var value = String(source[keys[i]] || "")
    result[keys[i]] = buttonActions.indexOf(value) >= 0 ? value : (keys[i] === "eraser" ? "eraser" : "right-click")
  }
  return result
}

var api = {
  isTouchscreen: isTouchscreen,
  isTabletPad: isTabletPad,
  isStylus: isStylus,
  isPhysicalKeyboard: isPhysicalKeyboard,
  keyboardTransport: keyboardTransport,
  isBluetoothKeyboard: isBluetoothKeyboard,
  isDetachableKeyboard: isDetachableKeyboard,
  capabilities: capabilities,
  normalizeDevice: normalizeDevice,
  classify: classify,
  classifyKeyboards: classifyKeyboards,
  diagnostics: diagnostics,
  buttonActions: buttonActions,
  normalizeButtonMap: normalizeButtonMap
}
if (typeof module !== "undefined") module.exports = api
