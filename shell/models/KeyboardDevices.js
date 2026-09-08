// Capability-based physical keyboard classification.
//
// Device names are useful for display and exclusion hints only. A device is
// accepted as a keyboard only when libinput/udev/Hyprland-style capability or
// type evidence says it has keyboard input. Stable identities never expose a
// serial, Bluetooth address or ephemeral device path.

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function bool(value) {
  var name = string(value).toLowerCase()
  return value === true || value === 1 || name === "true" || name === "yes" || name === "1"
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function tokens(item) {
  var source = object(item)
  var result = []
  var fields = [source.type, source.deviceType, source.device_type, source.kind, source.inputType, source.input_type, source.role, source.formFactor, source.form_factor, source.connection]
  for (var i = 0; i < fields.length; i++) {
    var value = token(fields[i])
    if (value && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function capabilityBag(item) {
  var source = object(item)
  var raw = source.capabilities || source.libinputCapabilities || source.libinput_capabilities || source.inputCapabilities || source.input_capabilities || source.features || {}
  var result = {}
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length; i++) if (token(raw[i])) result[token(raw[i])] = true
  } else {
    var capabilityObject = object(raw)
    for (var key in capabilityObject) {
      if (bool(capabilityObject[key]) || /^key[-_]/i.test(key) || /^btn[-_]/i.test(key)) result[token(key)] = true
    }
  }
  var fields = ["keyboard", "keys", "normalKeyboard", "normal-keys", "numpad", "numpadOnly", "mediaOnly", "consumerControl", "systemControl", "powerButton", "gamepad", "joystick", "remote", "volume", "playback"]
  for (var f = 0; f < fields.length; f++) {
    var keyName = fields[f]
    var alternate = keyName.replace(/-/g, "_")
    if (bool(source[keyName]) || bool(source[alternate])) result[token(keyName)] = true
  }
  if (string(source.ID_INPUT_KEYBOARD) === "1" || string(source.id_input_keyboard) === "1") result.keyboard = true
  if (string(source.ID_INPUT_JOYSTICK) === "1" || string(source.id_input_joystick) === "1") result.joystick = true
  return result
}

function keyTokens(item, caps) {
  var source = object(item)
  var raw = source.keys || source.keyCodes || source.key_codes || source.keyboardKeys || source.keyboard_keys || source.evdevKeys || source.evdev_keys
  var result = []
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length; i++) if (token(raw[i])) result.push(token(raw[i]))
  } else if (typeof raw === "string") {
    var parts = raw.split(/[\s,;]+/)
    for (var p = 0; p < parts.length; p++) if (token(parts[p])) result.push(token(parts[p]))
  }
  for (var key in caps) if (/^(key|btn)-/.test(key)) result.push(key)
  return result.filter(function(value, index, list) { return list.indexOf(value) === index })
}

function hasAny(source, names) {
  var item = object(source)
  var list = tokens(item)
  var caps = capabilityBag(item)
  for (var i = 0; i < names.length; i++) {
    var wanted = token(names[i])
    if (list.indexOf(wanted) >= 0 || caps[wanted] === true) return true
  }
  return false
}

function keyboardEvidence(item, caps) {
  var source = object(item)
  var list = tokens(source)
  return caps.keyboard === true || caps.keys === true || bool(source.keyboard) || string(source.ID_INPUT_KEYBOARD) === "1" || string(source.id_input_keyboard) === "1" || list.indexOf("keyboard") >= 0 || list.indexOf("keyboards") >= 0
}

function excludedReason(item, caps, keys) {
  var source = object(item)
  var name = token(source.name || source.device || source.identifier)
  if (hasAny(source, ["consumer-control", "system-control", "power-button", "gamepad", "joystick", "remote", "tablet-pad", "stylus-buttons"])) return "non-keyboard control device"
  if (caps["consumer-control"] || caps["system-control"] || caps["power-button"] || caps.gamepad || caps.joystick || caps.remote) return "non-keyboard control device"
  if (name.indexOf("consumer-control") >= 0 || name.indexOf("system-control") >= 0 || name.indexOf("power-button") >= 0 || name.indexOf("gamepad") >= 0 || name.indexOf("joystick") >= 0 || name.indexOf("remote") >= 0) return "non-keyboard control device"
  var numpadOnly = bool(source.numpadOnly) || caps["numpad-only"] === true
  if (!numpadOnly && keys.length > 0) numpadOnly = keys.every(function(value) { return value.indexOf("key-kp") === 0 || value.indexOf("kp-") === 0 || value.indexOf("key-keypad-") === 0 || value.indexOf("key-numpad-") === 0 || value.indexOf("key-numlock") === 0 })
  if (numpadOnly) return "numpad-only input"
  var mediaOnly = bool(source.mediaOnly) || caps["media-only"] === true
  if (!mediaOnly && keys.length === 0 && (caps.volume || caps.playback || caps["consumer-control"] || caps["system-control"])) mediaOnly = true
  if (mediaOnly) return "multimedia-only input"
  return ""
}

function transport(item) {
  var source = object(item)
  var fields = [source.transport, source.connection, source.bus, source.backend, source.protocol, source.ID_BUS, source.id_bus]
  for (var i = 0; i < fields.length; i++) {
    var value = token(fields[i])
    if (value && value !== "unknown" && value !== "none") {
      if (value.indexOf("bluez") >= 0 || value.indexOf("bluetooth") >= 0 || value === "bt") return "bluetooth"
      if (value.indexOf("usb-c") >= 0 || value.indexOf("usbc") >= 0) return value.indexOf("dock") >= 0 ? "usb-c-dock" : "usb-c"
      if (value.indexOf("usb") >= 0) return "usb"
      if (value.indexOf("pogo") >= 0 || value.indexOf("pin") >= 0) return "pogo-pin"
      if (value.indexOf("i2c") >= 0) return "i2c"
      if (value.indexOf("platform") >= 0) return "platform"
      return value
    }
  }
  if (bool(source.bluetooth)) return "bluetooth"
  if (bool(source.usb)) return "usb"
  return "unknown"
}

function formFactorRelation(item, connection) {
  var source = object(item)
  var form = token(source.formFactor || source.form_factor || source.formFactorRelation || source.form_factor_relation || source.keyboardRole || source.role)
  var connectionValue = token(source.connection || "")
  if (bool(source.dock) || bool(source.docked) || bool(source.externalDock) || form.indexOf("dock") >= 0 || connection === "usb-c-dock" || connectionValue.indexOf("dock") >= 0) return "dock"
  if (bool(source.detachable) || bool(source.detachableKeyboard) || form.indexOf("detachable") >= 0 || form.indexOf("cover") >= 0 || form.indexOf("folio") >= 0 || form.indexOf("pogo") >= 0 || form.indexOf("tablet-keyboard") >= 0 || connection === "pogo-pin") return "detachable"
  if (bool(source.builtin) || bool(source.builtIn) || form.indexOf("built-in") >= 0 || form.indexOf("builtin") >= 0 || form.indexOf("internal") >= 0 || form.indexOf("integrated") >= 0) return "built-in"
  if (connection === "i2c" || connection === "platform") return "built-in"
  if (form.indexOf("convertible") >= 0) return "convertible"
  if (connection === "bluetooth" || connection === "usb" || connection === "usb-c") return "external"
  if (form.indexOf("external") >= 0 || form.indexOf("wireless") >= 0) return "external"
  return "unknown"
}

function opaquePart(value) {
  var source = string(value)
  var hash = 2166136261
  for (var i = 0; i < source.length; i++) {
    hash ^= source.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return ("00000000" + (hash >>> 0).toString(16)).slice(-8)
}

function durable(source, names) {
  for (var i = 0; i < names.length; i++) {
    var value = string(source[names[i]]).trim()
    if (value) return value
  }
  return ""
}

function capabilitySignature(caps, keys) {
  var bag = Object.keys(caps).sort().join(",")
  return bag + "|" + keys.slice().sort().join(",")
}

function stableId(item, relation, connection, caps, keys) {
  var source = object(item)
  var vendor = durable(source, ["vendorId", "vendor_id", "idVendor", "ID_VENDOR_ID", "id_vendor_id"])
  var product = durable(source, ["productId", "product_id", "idProduct", "ID_MODEL_ID", "id_model_id"])
  var serial = durable(source, ["serial", "serialNumber", "serial_number", "ID_SERIAL_SHORT", "id_serial_short"])
  var address = durable(source, ["address", "bluetoothAddress", "bluetooth_address", "uniq", "uniqueId", "unique_id"])
  var path = durable(source, ["devpath", "devPath", "path", "phys", "devicePath", "ID_PATH", "id_path"])
  var seat = durable(source, ["seat", "seatName", "seat_name", "ID_SEAT", "id_seat"]) || "default"
  var name = durable(source, ["name", "device", "identifier", "ID_MODEL"]) || "unnamed"
  var signature = capabilitySignature(caps, keys)
  var parts = ["relation-" + relation, "transport-" + connection, "seat-" + seat]
  if (vendor && product) {
    parts.push("vendor-" + vendor, "product-" + product)
    if (serial) parts.push("serial-h-" + opaquePart(serial))
    else if (address) parts.push("identity-h-" + opaquePart(address))
    else if (path) parts.push("path-h-" + opaquePart(path))
    return "keyboard:" + parts.join("/")
  }
  if (serial || address) {
    parts.push("identity-h-" + opaquePart(serial || address))
    return "keyboard:" + parts.join("/")
  }
  // Without a durable hardware identity, do not make an ephemeral path the
  // persistent key. This fallback is explicitly lower confidence and may
  // merge identical anonymous keyboards rather than leaking a device path.
  return "keyboard:fallback-h-" + opaquePart(name + "|" + signature + "|" + seat)
}

function normalize(item, sourceName) {
  var source = object(item)
  var caps = capabilityBag(source)
  var keys = keyTokens(source, caps)
  var connection = transport(source)
  var relation = formFactorRelation(source, connection)
  var exclusion = excludedReason(source, caps, keys)
  var evidence = keyboardEvidence(source, caps)
  var connected = source.connected !== false && source.present !== false && token(source.state || "connected") !== "disconnected"
  var identity = stableId(source, relation, connection, caps, keys)
  var normalKeyboard = evidence && !exclusion
  return {
    id: identity,
    name: durable(source, ["name", "device", "identifier", "ID_MODEL"]) || "Unnamed keyboard",
    role: "keyboard",
    category: relation === "unknown" || relation === "convertible" ? "external" : relation,
    classification: relation,
    transport: connection,
    formFactorRelation: relation,
    connected: connected,
    seat: durable(source, ["seat", "seatName", "seat_name", "ID_SEAT", "id_seat"]) || "default",
    capabilities: {
      keyboard: evidence,
      normalKeyboard: normalKeyboard,
      functionRow: bool(source.functionRow) || bool(source.function_row) || keys.some(function(value) { return value.indexOf("key-f") === 0 }),
      numberRow: bool(source.numberRow) || bool(source.number_row) || keys.some(function(value) { return ["key-1", "key-2", "key-3", "key-4", "key-5", "key-6", "key-7", "key-8", "key-9", "key-0"].indexOf(value) >= 0 }),
      modifiers: bool(source.modifiers) || keys.some(function(value) { return ["key-leftctrl", "key-rightctrl", "key-leftshift", "key-rightshift", "key-leftalt", "key-rightalt", "key-leftmeta", "key-rightmeta"].indexOf(value) >= 0 }),
      navigation: bool(source.navigation) || keys.some(function(value) { return ["key-up", "key-down", "key-left", "key-right", "key-home", "key-end", "key-pageup", "key-pagedown"].indexOf(value) >= 0 }),
      numpadOnly: exclusion === "numpad-only input",
      mediaOnly: exclusion === "multimedia-only input",
      excluded: exclusion !== ""
    },
    capabilityEvidence: evidence ? "input-capability" : "none",
    behavior: string(source.behavior || source.policy || "generic"),
    ignored: bool(source.ignore) || bool(source.ignored),
    preferredProfile: string(source.preferredProfile || source.preferred_profile || ""),
    source: string(sourceName || source.source || "input")
  }
}

function candidateGroups(snapshot) {
  if (Array.isArray(snapshot)) return [{ items: snapshot, source: "input" }]
  var source = object(snapshot)
  var result = []
  var known = [
    ["keyboards", "hyprland"], ["keyboard", "hyprland"], ["physicalKeyboards", "hyprland"], ["physical_keyboards", "hyprland"],
    ["inputKeyboards", "libinput"], ["input_keyboards", "libinput"], ["udevKeyboards", "udev"], ["udev_keyboards", "udev"]
  ]
  for (var i = 0; i < known.length; i++) {
    var list = source[known[i][0]]
    if (list && !Array.isArray(list)) list = [list]
    for (var j = 0; j < array(list).length; j++) result.push({ item: list[j], source: known[i][1] })
  }
  var generic = array(source.devices)
  for (var g = 0; g < generic.length; g++) result.push({ item: generic[g], source: "input-devices" })
  var inputs = array(source.inputs)
  for (var n = 0; n < inputs.length; n++) result.push({ item: inputs[n], source: "libinput" })
  return result
}

function classify(snapshot) {
  var rows = candidateGroups(snapshot)
  var result = []
  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var normalized = normalize(rows[i].item, rows[i].source)
    if (normalized.capabilities.normalKeyboard !== true || normalized.ignored || seen[normalized.id]) continue
    seen[normalized.id] = true
    result.push(normalized)
  }
  return result
}

function isPhysicalKeyboard(item) {
  var normalized = normalize(item, "input")
  return normalized.capabilities.normalKeyboard === true && normalized.ignored !== true
}

function summary(devices) {
  var list = array(devices)
  return list.map(function(item) {
    return {
      id: string(item.id),
      // Status and diagnostics are a privacy boundary. Device names can carry
      // a serial or a user-assigned Bluetooth label, so expose only a stable
      // category label here; classification and capability fields remain
      // available to the UI and adaptive policy.
      name: "Keyboard",
      category: string(item.category || "external"),
      classification: string(item.classification || item.formFactorRelation || "unknown"),
      transport: string(item.transport || "unknown"),
      connected: item.connected === true,
      seat: string(item.seat || "default"),
      behavior: string(item.behavior || "generic"),
      ignored: item.ignored === true,
      preferredProfile: string(item.preferredProfile || ""),
      capabilities: {
        normalKeyboard: item.capabilities && item.capabilities.normalKeyboard === true,
        functionRow: item.capabilities && item.capabilities.functionRow === true,
        numberRow: item.capabilities && item.capabilities.numberRow === true,
        modifiers: item.capabilities && item.capabilities.modifiers === true,
        navigation: item.capabilities && item.capabilities.navigation === true
      }
    }
  })
}

var api = {
  transport: transport,
  formFactorRelation: formFactorRelation,
  stableId: stableId,
  normalize: normalize,
  classify: classify,
  isPhysicalKeyboard: isPhysicalKeyboard,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
