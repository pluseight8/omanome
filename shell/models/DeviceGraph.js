// Universal, privacy-safe device graph foundation.
//
// This model deliberately consumes snapshots instead of probing hardware. It
// turns explicit compositor/libinput/udev-style records into a small graph
// contract that later policies can share. Raw paths, serials, Bluetooth
// addresses, EDID blobs, and event-node names are used only as input to a
// deterministic opaque identity hash and never leave this module.

var SCHEMA_VERSION = 1
var CATEGORIES = [
  "display", "touchscreen", "stylus", "tablet-pad", "keyboard", "mouse",
  "touchpad", "gamepad", "sensor", "dock", "battery", "audio"
]
var CONFIDENCES = ["confirmed", "probable", "unknown"]
var RELATIONS = ["parent", "attached-to", "mapped-to", "reports-to", "paired-with", "none"]
// Graph state is fed by backend snapshots and hotplug events. Keep hostile
// or unexpectedly large adapters from turning a diagnostics model into an
// unbounded collection.
var MAX_NODES = 256
var MAX_OUTPUTS = 32
var MAX_RELATIONSHIPS = 512
var CAPABILITY_KEYS = [
  "display", "touch", "touchscreen", "multitouch", "stylus", "tablet",
  "keyboard", "mouse", "touchpad", "gamepad", "sensor", "battery", "audio",
  "pressure", "tilt", "tilt-x", "tilt-y", "rotation", "distance", "proximity",
  "eraser", "buttons", "absolute", "relative", "haptic", "lid", "power"
]

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
  var normalized = string(value).toLowerCase()
  return value === true || value === 1 || normalized === "true" || normalized === "yes" || normalized === "1"
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function finiteNumber(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function clamp(value, minimum, maximum, fallback) {
  var result = finiteNumber(value, fallback)
  return Math.max(minimum, Math.min(maximum, result))
}

function safeLabel(value, fallback) {
  var result = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  // Names occasionally contain a full device node or an address. They are
  // useful as input hints but are not safe public labels.
  if (!result || /\/dev\/input\/event\d+/i.test(result) || /(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i.test(result)) return fallback
  if (result.length > 96) result = result.slice(0, 96).trim()
  return result || fallback
}

// FNV-1a is sufficient here: this is an opaque, deterministic identifier,
// not a security boundary. Include a second mixed value to reduce collisions
// when many anonymous devices share the same role.
function opaquePart(value) {
  var source = string(value)
  var first = 2166136261
  var second = 2166136261 ^ 0x9e3779b9
  for (var i = 0; i < source.length; i++) {
    var code = source.charCodeAt(i)
    first ^= code
    first = Math.imul(first, 16777619)
    second ^= code + ((i + 1) * 17)
    second = Math.imul(second, 16777619)
  }
  return ("00000000" + (first >>> 0).toString(16)).slice(-8) + ("00000000" + (second >>> 0).toString(16)).slice(-8)
}

function first(source, names) {
  var item = object(source)
  for (var i = 0; i < names.length; i++) {
    var value = string(item[names[i]]).trim()
    if (value) return value
  }
  return ""
}

function capabilityToken(value) {
  var name = token(value)
  if (name === "tiltx") name = "tilt-x"
  if (name === "tilty") name = "tilt-y"
  if (name === "touch-screen") name = "touchscreen"
  if (name === "tablet-tool") name = "stylus"
  return name
}

function capabilities(source, category) {
  var item = object(source)
  var raw = item.capabilities || item.capability || item.features || item.libinputCapabilities || item.libinput_capabilities || item.inputCapabilities || item.input_capabilities || {}
  var result = {}
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length; i++) {
      var listName = capabilityToken(raw[i])
      if (CAPABILITY_KEYS.indexOf(listName) >= 0) result[listName] = true
    }
  } else {
    var capabilityObject = object(raw)
    for (var key in capabilityObject) {
      var objectName = capabilityToken(key)
      if (CAPABILITY_KEYS.indexOf(objectName) >= 0 && bool(capabilityObject[key])) result[objectName] = true
    }
  }
  for (var c = 0; c < CAPABILITY_KEYS.length; c++) {
    var name = CAPABILITY_KEYS[c]
    var alternate = name.replace(/-/g, "_")
    if (bool(item[name]) || bool(item[alternate])) result[name] = true
  }
  if (category === "display") result.display = true
  if (category === "touchscreen") { result.touch = true; result.touchscreen = true }
  if (category === "stylus") { result.stylus = true; result.tablet = true }
  if (category === "tablet-pad") result.tablet = true
  if (category === "keyboard") result.keyboard = true
  if (category === "mouse") result.mouse = true
  if (category === "touchpad") { result.touchpad = true; result.relative = true }
  if (category === "gamepad") result.gamepad = true
  if (category === "sensor") result.sensor = true
  if (category === "battery") { result.battery = true; result.power = true }
  if (category === "audio") result.audio = true
  return result
}

function fieldTokens(source) {
  var item = object(source)
  var fields = [item.category, item.deviceCategory, item.device_category, item.type, item.deviceType, item.device_type, item.kind, item.inputType, item.input_type, item.role, item.formFactor, item.form_factor]
  var result = []
  for (var i = 0; i < fields.length; i++) {
    var name = token(fields[i])
    if (name && result.indexOf(name) < 0) result.push(name)
  }
  return result
}

function categoryFrom(source, hint) {
  var item = object(source)
  var wanted = token(hint || item.category || item.deviceCategory || item.device_category)
  var aliases = {
    monitor: "display", monitors: "display", display: "display", displays: "display", output: "display", outputs: "display",
    touch: "touchscreen", touchscreen: "touchscreen", "touch-screen": "touchscreen", touchdevice: "touchscreen", "touch-device": "touchscreen",
    tablet: "stylus", "tablet-tool": "stylus", "tablettool": "stylus", stylus: "stylus", pen: "stylus", eraser: "stylus",
    pad: "tablet-pad", "tablet-pad": "tablet-pad", tabletpads: "tablet-pad", "tablet-surface": "tablet-pad",
    keyboard: "keyboard", keyboards: "keyboard", key: "keyboard",
    mouse: "mouse", pointer: "mouse", pointers: "mouse",
    touchpad: "touchpad", trackpad: "touchpad", "touch-pad": "touchpad",
    gamepad: "gamepad", joystick: "gamepad", controller: "gamepad",
    sensor: "sensor", sensors: "sensor", accelerometer: "sensor", gyroscope: "sensor",
    dock: "dock", docking: "dock", "usb-c-dock": "dock",
    battery: "battery", batteries: "battery", power: "battery",
    audio: "audio", speaker: "audio", microphone: "audio", sound: "audio"
  }
  if (aliases[wanted]) {
    if (aliases[wanted] === "stylus" && (wanted === "tablet" || wanted === "tablet-tool") && (token(item.toolType || item.tool_type) === "pad" || token(item.formFactor || item.form_factor).indexOf("pad") >= 0)) return "tablet-pad"
    return aliases[wanted]
  }
  var fields = fieldTokens(item)
  for (var i = 0; i < fields.length; i++) if (aliases[fields[i]]) {
    if (aliases[fields[i]] === "stylus" && (token(item.toolType || item.tool_type) === "pad" || fields.indexOf("pad") >= 0)) return "tablet-pad"
    return aliases[fields[i]]
  }
  var caps = capabilities(item, "")
  if (caps.touchscreen || caps.touch) return "touchscreen"
  if (caps.stylus || caps.pressure || caps["tilt-x"] || caps["tilt-y"] || caps.eraser) return "stylus"
  if (caps.keyboard) return "keyboard"
  if (caps.touchpad) return "touchpad"
  if (caps.mouse || caps.relative) return "mouse"
  if (caps.gamepad) return "gamepad"
  if (caps.sensor) return "sensor"
  if (caps.battery) return "battery"
  if (caps.audio) return "audio"
  return ""
}

function categoryEvidence(source, hint, category) {
  var item = object(source)
  var explicit = token(hint || item.category || item.deviceCategory || item.device_category)
  if (explicit) return explicit === category || (category === "display" && ["monitor", "output"].indexOf(explicit) >= 0) ? "confirmed" : "probable"
  var typed = categoryFrom(item, "")
  if (typed === category && (item.type || item.deviceType || item.kind || item.role)) return "confirmed"
  if (typed === category) return "probable"
  return "unknown"
}

function transport(source) {
  var item = object(source)
  var value = token(first(item, ["transport", "connection", "bus", "protocol", "backend", "ID_BUS", "id_bus", "connector"]))
  if (!value) return "unknown"
  if (value.indexOf("bluetooth") >= 0 || value.indexOf("bluez") >= 0 || value === "bt") return "bluetooth"
  if (value.indexOf("usb-c") >= 0 || value.indexOf("usbc") >= 0 || value.indexOf("thunderbolt") >= 0) return "usb-c"
  if (value.indexOf("usb") >= 0) return "usb"
  if (value.indexOf("pogo") >= 0 || value.indexOf("pin") >= 0) return "pogo-pin"
  if (value.indexOf("i2c") >= 0) return "i2c"
  if (value.indexOf("spi") >= 0) return "spi"
  if (value.indexOf("platform") >= 0) return "platform"
  if (value.indexOf("displayport") >= 0 || value === "dp") return "displayport"
  if (value.indexOf("hdmi") >= 0) return "hdmi"
  return value.length <= 32 && /^[a-z0-9.-]+$/.test(value) ? value : "unknown"
}

function seat(source) {
  var value = first(source, ["seat", "seatName", "seat_name", "ID_SEAT", "id_seat"])
  return value && /^[a-zA-Z0-9_.-]{1,48}$/.test(value) ? value : "default"
}

function physicalPath(source) {
  var value = first(source, ["physicalPath", "physical_path", "phys", "devicePath", "device_path", "ID_PATH", "id_path", "devpath", "devPath", "path", "syspath"])
  if (!value) return ""
  // /dev/input/eventX is an ephemeral kernel node. A parent path can still be
  // useful, but the event suffix itself must never be the persistent key.
  value = value.replace(/[\\/]event[0-9]+$/i, "")
  if (/^\/?dev[\\/]input(?:[\\/]event[0-9]+)?$/i.test(value) || /\bevent[0-9]+\b/i.test(value) && value.indexOf("/") < 0) return ""
  return value
}

function stableIdentityMaterial(source, category, caps) {
  var item = object(source)
  var vendor = first(item, ["vendorId", "vendor_id", "vendor", "idVendor", "ID_VENDOR_ID", "id_vendor_id"])
  var product = first(item, ["productId", "product_id", "product", "idProduct", "ID_MODEL_ID", "id_product_id"])
  var serial = first(item, ["serial", "serialNumber", "serial_number", "ID_SERIAL_SHORT", "id_serial_short"])
  var address = first(item, ["address", "bluetoothAddress", "bluetooth_address", "uniq", "uniqueId", "unique_id"])
  var path = physicalPath(item)
  var explicit = first(item, ["stableId", "stable_id", "nodeId", "node_id", "deviceId", "device_id", "id", "identifier"])
  var label = first(item, ["label", "displayName", "display_name", "friendlyName", "friendly_name", "name", "device"])
  var signature = Object.keys(caps).sort().join(",")
  if (serial) return "serial|" + serial + "|" + category + "|" + seat(item)
  if (address) return "address|" + address + "|" + category + "|" + seat(item)
  if (vendor && product && path) return "hardware|" + vendor + "|" + product + "|" + path + "|" + category + "|" + seat(item)
  if (vendor && product) return "hardware|" + vendor + "|" + product + "|" + category + "|" + seat(item)
  if (explicit && !/event[0-9]+|\/dev\/input/i.test(explicit)) return "explicit|" + explicit + "|" + category + "|" + seat(item)
  if (path) return "path|" + path + "|" + category + "|" + seat(item)
  return "fallback|" + label + "|" + signature + "|" + transport(item) + "|" + category + "|" + seat(item)
}

function stableId(source, categoryHint) {
  var item = object(source)
  var category = categoryFrom(item, categoryHint) || "unknown"
  var caps = capabilities(item, category)
  return "device:" + category + ":" + opaquePart(stableIdentityMaterial(item, category, caps))
}

function confidence(value, fallback) {
  var name = token(value)
  if (name === "confirmed") return "confirmed"
  if (name === "probable" || name === "likely") return "probable"
  if (name === "unknown" || name === "unverified") return "unknown"
  return fallback || "unknown"
}

function formFactorRole(source, category) {
  var item = object(source)
  var explicit = token(first(item, ["formFactorRole", "form_factor_role", "formFactor", "form_factor", "outputRole", "output_role"]))
  var allowed = { "built-in": true, builtin: true, internal: true, external: true, detachable: true, dock: true, drawing: true, portable: true, convertible: true, unknown: true }
  if (allowed[explicit]) return explicit === "builtin" || explicit === "internal" ? "built-in" : explicit
  if (category === "dock") return "dock"
  if (bool(item.detachable) || bool(item.detachableKeyboard)) return "detachable"
  if (bool(item.builtin) || bool(item.builtIn) || bool(item.internal)) return "built-in"
  if (category === "display" && bool(item.external)) return "external"
  if (category === "stylus" || category === "tablet-pad") return "drawing"
  if (category === "keyboard" && ["bluetooth", "usb", "usb-c", "pogo-pin"].indexOf(transport(item)) >= 0) return "external"
  return "unknown"
}

function sourceList(source, sourceName, category) {
  var item = object(source)
  var raw = item.capabilitySource || item.capability_source || item.sources || item.source
  if (!raw) raw = sourceName
  var values = Array.isArray(raw) ? raw : [raw]
  var result = []
  var known = ["libinput", "udev", "sysfs", "compositor", "hyprland", "edid", "physical-path", "seat", "dbus", "kernel", "upower", "pipewire", "fixture", "user"]
  for (var i = 0; i < values.length; i++) {
    var name = token(values[i])
    if (name === "physicalpath") name = "physical-path"
    if (["monitors", "displays", "outputs", "display", "touch", "touchscreens", "touchdevices", "styluses", "tablets", "tablettools", "tabletpads", "keyboards", "mice", "pointers", "touchpads", "gamepads", "controllers", "sensors", "docks", "batteries", "audio", "audiodevices", "audios", "devices"].indexOf(name) >= 0) name = "compositor"
    if (known.indexOf(name) < 0) {
      if (name.indexOf("libinput") >= 0) name = "libinput"
      else if (name.indexOf("udev") >= 0) name = "udev"
      else if (name.indexOf("hypr") >= 0 || name.indexOf("compositor") >= 0) name = "compositor"
      else if (name.indexOf("sysfs") >= 0) name = "sysfs"
      else if (name.indexOf("upower") >= 0) name = "upower"
      else if (name.indexOf("pipewire") >= 0 || name.indexOf("pulse") >= 0) name = "pipewire"
      else if (name.indexOf("dbus") >= 0) name = "dbus"
      else name = "backend"
    }
    if (name && result.indexOf(name) < 0) result.push(name)
  }
  return result.length > 0 ? result : [category === "display" ? "compositor" : "backend"]
}

function normalizePolicy(value) {
  var source = object(value)
  var result = {}
  var booleans = ["enabled", "ignored", "remembered", "autoMap", "allowAutomation"]
  for (var i = 0; i < booleans.length; i++) if (source[booleans[i]] !== undefined) result[booleans[i]] = bool(source[booleans[i]])
  var strings = ["profile", "role", "mappingMode", "preferredOutput", "oskTarget"]
  for (var s = 0; s < strings.length; s++) {
    var name = strings[s]
    var valueText = string(source[name]).trim()
    if (valueText && valueText.length <= 80 && !/[\\/\n\r]/.test(valueText)) result[name] = valueText
  }
  return result
}

function normalizeMappedOutput(source, outputs) {
  var item = object(source)
  var raw = item.mappedOutput || item.mapped_output || item.output || item.monitor || item.outputName || item.output_name || item.mappedDisplay || item.mapped_display
  if (raw && typeof raw === "object") raw = raw.id || raw.name || raw.output || raw.monitor
  var wanted = string(raw).trim()
  if (!wanted || ["auto", "automatic", "default", "none", "unknown"].indexOf(token(wanted)) >= 0) return { output: "", status: "automatic" }
  var list = array(outputs)
  for (var i = 0; i < list.length; i++) {
    var output = list[i] || {}
    var aliases = output.aliases || []
    if (wanted === output.id || wanted === output.name || aliases.indexOf(wanted) >= 0) return { output: output.id, status: "mapped" }
  }
  return { output: "", status: "unavailable" }
}

function normalizeNode(source, categoryHint, sourceName, outputs, policies) {
  var item = object(source)
  var category = categoryFrom(item, categoryHint)
  if (CATEGORIES.indexOf(category) < 0) return null
  var caps = capabilities(item, category)
  var id = stableId(item, category)
  var policySource = object(policies && policies[id])
  if (Object.keys(policySource).length === 0) policySource = item.userPolicy || item.user_policy || item.policy
  var mapped = normalizeMappedOutput(item, outputs)
  var evidence = categoryEvidence(item, categoryHint, category)
  var explicitConfidence = item.confidence || item.relationConfidence || item.relation_confidence
  return {
    id: id,
    label: safeLabel(first(item, ["label", "displayName", "display_name", "friendlyName", "friendly_name"]), category),
    category: category,
    transport: transport(item),
    capabilities: caps,
    seat: seat(item),
    connected: item.connected !== false && item.present !== false && item.available !== false,
    parent: "",
    relation: "none",
    mappedOutput: mapped.output,
    mappingStatus: mapped.status,
    formFactorRole: formFactorRole(item, category),
    userPolicy: normalizePolicy(policySource),
    capabilitySource: sourceList(item, sourceName, category),
    confidence: confidence(explicitConfidence, evidence)
  }
}

function outputIdentity(source) {
  var item = object(source)
  var name = first(item, ["name", "monitor", "output", "connector", "port", "id"])
  var make = first(item, ["make", "manufacturer"])
  var model = first(item, ["model", "description"])
  var serial = first(item, ["serial", "serialNumber", "edidSerial"])
  var geometry = object(item.geometry)
  var dimensions = [item.x, item.y, item.width, item.height, geometry.x, geometry.y, geometry.width, geometry.height].join(",")
  return serial ? "serial|" + serial + "|" + make + "|" + model : "display|" + name + "|" + make + "|" + model + "|" + dimensions
}

function normalizeOutput(source, index) {
  var item = object(source)
  var aliases = []
  var fields = ["name", "monitor", "output", "connector", "port", "id"]
  for (var f = 0; f < fields.length; f++) {
    var alias = string(item[fields[f]]).trim()
    if (alias && aliases.indexOf(alias) < 0 && alias.length <= 96 && !/[\n\r]/.test(alias)) aliases.push(alias)
  }
  var geometry = object(item.geometry)
  var width = finiteNumber(item.width, finiteNumber(geometry.width, 0))
  var height = finiteNumber(item.height, finiteNumber(geometry.height, 0))
  var x = finiteNumber(item.x, finiteNumber(geometry.x, 0))
  var y = finiteNumber(item.y, finiteNumber(geometry.y, 0))
  var scale = clamp(item.scale, 0.25, 8, 1)
  var orientation = token(item.transform || item.orientation || "normal")
  if (["normal", "90", "180", "270", "left", "right", "inverted"].indexOf(orientation) < 0) orientation = "unknown"
  var category = "display"
  var id = "display:" + opaquePart(outputIdentity(item))
  var explicitRole = token(item.role || item.outputRole || item.output_role || "")
  var role = "unknown"
  if (bool(item.builtin) || bool(item.builtIn) || bool(item.internal) || ["internal", "built-in", "builtin"].indexOf(explicitRole) >= 0) role = "internal"
  else if (bool(item.external) || ["external", "dock", "presentation"].indexOf(explicitRole) >= 0) role = "external"
  var confidenceValue = item.confidence || (role === "unknown" ? "unknown" : "confirmed")
  return {
    id: id,
    name: safeLabel(first(item, ["label", "displayName", "display_name", "name", "monitor", "output"]), "Display " + String(index + 1)),
    aliases: aliases,
    category: category,
    geometry: { x: x, y: y, width: Math.max(0, width), height: Math.max(0, height) },
    scale: scale,
    orientation: orientation,
    role: role,
    connected: item.connected !== false && item.present !== false && item.available !== false,
    capabilitySource: sourceList(item, "compositor", category),
    confidence: confidence(confidenceValue, "unknown")
  }
}

function outputSources(snapshot) {
  var source = object(snapshot)
  var result = []
  var groups = [source.monitors, source.displays, source.outputs, source.display]
  for (var i = 0; i < groups.length; i++) {
    var list = array(groups[i])
    for (var j = 0; j < list.length; j++) result.push(list[j])
  }
  return result
}

function addGroup(result, value, category, sourceName) {
  if (Array.isArray(value)) {
    for (var i = 0; i < value.length; i++) result.push({ item: value[i], category: category, source: sourceName })
    return
  }
  var group = object(value)
  // A nested device inventory is common in fixture and compositor adapters.
  for (var key in group) {
    var nested = group[key]
    var nestedCategory = categoryFrom({}, key) || category
    if (Array.isArray(nested)) for (var n = 0; n < nested.length; n++) result.push({ item: nested[n], category: nestedCategory, source: key })
  }
}

function deviceSources(snapshot) {
  var source = object(snapshot)
  var result = []
  var groups = [
    [source.touchscreens, "touchscreen", "touchscreens"], [source.touch, "touchscreen", "touch"], [source.touchDevices, "touchscreen", "touchDevices"], [source.touchdevices, "touchscreen", "touchdevices"],
    [source.styluses, "stylus", "styluses"], [source.stylus, "stylus", "stylus"], [source.tablets, "stylus", "tablets"], [source.tabletTools, "stylus", "tabletTools"], [source.tablettools, "stylus", "tablettools"],
    [source.tabletPads, "tablet-pad", "tabletPads"], [source.tabletpads, "tablet-pad", "tabletpads"],
    [source.keyboards, "keyboard", "keyboards"], [source.mice, "mouse", "mice"], [source.pointers, "mouse", "pointers"], [source.touchpads, "touchpad", "touchpads"],
    [source.gamepads, "gamepad", "gamepads"], [source.controllers, "gamepad", "controllers"], [source.sensors, "sensor", "sensors"], [source.docks, "dock", "docks"],
    [source.batteries, "battery", "batteries"], [source.audio, "audio", "audio"], [source.audioDevices, "audio", "audioDevices"], [source.audios, "audio", "audios"]
  ]
  for (var i = 0; i < groups.length; i++) addGroup(result, groups[i][0], groups[i][1], groups[i][2])
  if (Array.isArray(source.devices)) addGroup(result, source.devices, "", "devices")
  else addGroup(result, source.devices, "", "devices")
  // Some adapters expose one battery/audio object rather than a list.
  if (source.battery && !Array.isArray(source.battery)) addGroup(result, [source.battery], "battery", "battery")
  return result
}

function relationName(value) {
  var name = token(value || "parent")
  if (name === "child-of" || name === "child") return "parent"
  if (name === "attached" || name === "attachment") return "attached-to"
  if (name === "mapped" || name === "mapping") return "mapped-to"
  if (name === "reports" || name === "reports-to") return "reports-to"
  if (name === "paired" || name === "pair") return "paired-with"
  return RELATIONS.indexOf(name) >= 0 ? name : "parent"
}

function relationConfidence(value) {
  return confidence(value, "unknown")
}

function relationReference(value) {
  if (value && typeof value === "object") {
    return string(value.id || value.stableId || value.stable_id || value.nodeId || value.node_id || value.deviceId || value.device_id || value.identifier).trim()
  }
  return string(value).trim()
}

function addRelationship(result, seen, from, to, type, confidenceValue, sourceName) {
  if (!from || !to || from === to) return
  var key = [from, to, type].join("|")
  if (seen[key]) return
  seen[key] = true
  result.push({ from: from, to: to, type: type, confidence: confidenceValue, source: sourceName })
}

function nodeParentReference(source) {
  var item = object(source)
  return relationReference(item.parentId || item.parent_id || item.parentDeviceId || item.parent_device_id || item.parent || item.attachedTo || item.attached_to || item.belongsTo || item.belongs_to)
}

function rawReference(source) {
  var item = object(source)
  var value = item.id || item.stableId || item.stable_id || item.nodeId || item.node_id || item.deviceId || item.device_id || item.identifier
  return string(value).trim()
}

function findRecordByReference(records, reference) {
  var wanted = string(reference).trim()
  if (!wanted) return null
  for (var i = 0; i < records.length; i++) {
    var raw = object(records[i].raw)
    if (rawReference(raw) === wanted || records[i].node.id === wanted) return records[i]
  }
  return null
}

function explicitRelations(snapshot, records, outputs) {
  var source = object(snapshot)
  var values = array(source.relationships)
  if (values.length === 0) values = array(source.relations)
  var result = []
  var seen = {}
  for (var i = 0; i < values.length; i++) {
    if (result.length >= MAX_RELATIONSHIPS) break
    var relation = object(values[i])
    var from = findRecordByReference(records, relationReference(relation.from || relation.child || relation.device || relation.source))
    var to = findRecordByReference(records, relationReference(relation.to || relation.parent || relation.target || relation.destination))
    if (!from || !to || from.node.id === to.node.id) continue
    var type = relationName(relation.type || relation.relation || relation.kind)
    var confidenceValue = relationConfidence(relation.confidence || relation.relationConfidence || relation.relation_confidence)
    from.node.parent = type === "parent" || type === "attached-to" ? to.node.id : from.node.parent
    from.node.relation = type
    addRelationship(result, seen, from.node.id, to.node.id, type, confidenceValue, "explicit")
  }
  // Device records may carry an explicit parent/attachment reference even
  // when the adapter has no top-level relationship list. Resolve only that
  // reference; never infer a relation from names, vendors, or proximity.
  for (var r = 0; r < records.length; r++) {
    if (result.length >= MAX_RELATIONSHIPS) break
    var record = records[r]
    var parentReference = nodeParentReference(record.raw)
    if (!parentReference) continue
    var parent = findRecordByReference(records, parentReference)
    if (!parent || parent.node.id === record.node.id) continue
    var relationType = relationName(object(record.raw).relation || object(record.raw).relationType || (object(record.raw).attachedTo || object(record.raw).attached_to ? "attached-to" : "parent"))
    var recordConfidence = relationConfidence(object(record.raw).relationConfidence || object(record.raw).relation_confidence || "confirmed")
    record.node.parent = relationType === "parent" || relationType === "attached-to" ? parent.node.id : record.node.parent
    record.node.relation = relationType
    addRelationship(result, seen, record.node.id, parent.node.id, relationType, recordConfidence, "device-record")
  }
  // A mapped output is an explicit user/compositor fact, so expose it as a
  // confirmed relation. Automatic mapping remains unconnected until a later
  // policy layer resolves it.
  for (var m = 0; m < records.length; m++) {
    if (result.length >= MAX_RELATIONSHIPS) break
    var mapped = normalizeMappedOutput(records[m].raw, outputs)
    if (mapped.status !== "mapped" || !mapped.output) continue
    var outputRecord = null
    for (var o = 0; o < records.length; o++) if (records[o].node.id === mapped.output) { outputRecord = records[o]; break }
    if (outputRecord && outputRecord.node.id !== records[m].node.id)
      addRelationship(result, seen, records[m].node.id, outputRecord.node.id, "mapped-to", "confirmed", "explicit-mapping")
  }
  return result
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: 0,
    nodes: [],
    relationships: [],
    outputs: [],
    health: { available: false, backend: "unavailable", reason: "no-device-snapshot" },
    confidence: { confirmed: 0, probable: 0, unknown: 0 }
  }
}

function fromSnapshot(snapshot, previous, options) {
  var source = object(snapshot)
  var old = object(previous)
  var settings = object(options)
  var rawOutputs = outputSources(source)
  var outputs = []
  var outputSeen = {}
  for (var o = 0; o < rawOutputs.length && outputs.length < MAX_OUTPUTS; o++) {
    var output = normalizeOutput(rawOutputs[o], o)
    if (outputSeen[output.id]) continue
    outputSeen[output.id] = true
    outputs.push(output)
  }
  var rows = deviceSources(source)
  var records = []
  var nodes = []
  var seen = {}
  for (var i = 0; i < rows.length && nodes.length < MAX_NODES; i++) {
    var row = rows[i]
    var node = normalizeNode(row.item, row.category, row.source, outputs, settings.policies || settings.userPolicies)
    if (!node || seen[node.id]) continue
    seen[node.id] = true
    var mapping = normalizeMappedOutput(row.item, outputs)
    if (mapping.output) node.mappedOutput = mapping.output
    records.push({ raw: row.item, node: node })
    nodes.push(node)
  }
  // A display is a graph node as well as an output topology record. It is
  // intentionally linked through the opaque display id, never its connector.
  for (var d = 0; d < outputs.length && nodes.length < MAX_NODES; d++) {
    var display = outputs[d]
    if (seen[display.id]) continue
    var displayNode = {
      id: display.id,
      label: display.name,
      category: "display",
      transport: "unknown",
      capabilities: { display: true },
      seat: "default",
      connected: display.connected,
      parent: "",
      relation: "none",
      mappedOutput: display.id,
      mappingStatus: "mapped",
      formFactorRole: display.role === "internal" ? "built-in" : display.role === "external" ? "external" : "unknown",
      userPolicy: {},
      capabilitySource: display.capabilitySource.slice(),
      confidence: display.confidence
    }
    seen[display.id] = true
    records.push({ raw: rawOutputs[d], node: displayNode })
    nodes.push(displayNode)
  }
  var relationships = explicitRelations(source, records, outputs)
  var confidenceCounts = { confirmed: 0, probable: 0, unknown: 0 }
  for (var n = 0; n < nodes.length; n++) confidenceCounts[confidence(nodes[n].confidence, "unknown")]++
  var backend = first(source, ["backend", "source", "provider"]) || (nodes.length > 0 ? "snapshot" : "unavailable")
  if (/[/\\\n\r]/.test(backend)) backend = "snapshot"
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: Number(old.revision || 0) + 1,
    nodes: nodes,
    relationships: relationships,
    outputs: outputs,
    health: { available: nodes.length > 0 || outputs.length > 0, backend: token(backend) || "snapshot", reason: nodes.length > 0 || outputs.length > 0 ? "snapshot" : "no-device-snapshot" },
    confidence: confidenceCounts
  }
}

function applyEvent(previous, event, options) {
  var old = object(previous)
  var source = object(event)
  var item = object(source.device)
  if (Object.keys(item).length === 0) item = source
  var category = categoryFrom(item, source.category || source.role || source.type)
  var node = normalizeNode(item, category, source.subsystem || "udev", array(old.outputs), object(options).policies || object(options).userPolicies)
  if (!node) return old
  var nodes = array(old.nodes).slice()
  var index = -1
  for (var i = 0; i < nodes.length; i++) if (nodes[i] && nodes[i].id === node.id) { index = i; break }
  var action = token(source.action || source.event || "change")
  if (action === "remove" || action === "delete") {
    if (index >= 0) nodes.splice(index, 1)
  } else if (index >= 0) {
    node.userPolicy = nodes[index].userPolicy || node.userPolicy
    nodes[index] = node
  } else if (nodes.length < MAX_NODES) nodes.push(node)
  var counts = { confirmed: 0, probable: 0, unknown: 0 }
  for (var n = 0; n < nodes.length; n++) counts[confidence(nodes[n].confidence, "unknown")]++
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: Number(old.revision || 0) + 1,
    nodes: nodes,
    relationships: array(old.relationships).slice(0, MAX_RELATIONSHIPS),
    outputs: array(old.outputs).slice(0, MAX_OUTPUTS),
    health: { available: nodes.length > 0 || array(old.outputs).length > 0, backend: "udev", reason: "event" },
    confidence: counts
  }
}

function summary(graph) {
  var source = object(graph)
  var nodes = array(source.nodes)
  var counts = {}
  var connected = 0
  for (var i = 0; i < nodes.length; i++) {
    var category = string(nodes[i] && nodes[i].category || "unknown")
    counts[category] = Number(counts[category] || 0) + 1
    if (nodes[i] && nodes[i].connected === true) connected++
  }
  return {
    schemaVersion: Number(source.schemaVersion || SCHEMA_VERSION),
    revision: Number(source.revision || 0),
    nodeCount: nodes.length,
    connectedCount: connected,
    outputCount: array(source.outputs).length,
    relationshipCount: array(source.relationships).length,
    categories: counts,
    confidence: Object.assign({ confirmed: 0, probable: 0, unknown: 0 }, object(source.confidence)),
    available: object(source.health).available === true
  }
}

function publicId(value) {
  var id = string(value).trim()
  return /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/.test(id) ? id : ""
}

function publicLabel(value, fallback) {
  var result = safeLabel(value, fallback)
  if (!result || /[\\/\n\r]/.test(result)) return fallback
  return result
}

function publicTransport(value) {
  var name = token(value || "unknown")
  var allowed = ["unknown", "usb", "usb-c", "bluetooth", "pogo-pin", "i2c", "spi", "virtual", "wayland", "kernel", "compositor", "wireless"]
  return allowed.indexOf(name) >= 0 ? name : "other"
}

function publicFormFactorRole(value) {
  var name = token(value || "unknown")
  var allowed = ["unknown", "built-in", "external", "detachable", "dock", "drawing", "portable", "convertible"]
  return allowed.indexOf(name) >= 0 ? name : "other"
}

function publicCapabilities(value) {
  var source = object(value)
  var result = {}
  for (var i = 0; i < CAPABILITY_KEYS.length; i++) if (source[CAPABILITY_KEYS[i]] === true) result[CAPABILITY_KEYS[i]] = true
  return result
}

function publicNode(value) {
  var source = object(value)
  var category = token(source.category)
  if (CATEGORIES.indexOf(category) < 0) category = "unknown"
  var relation = token(source.relation || "none")
  if (RELATIONS.indexOf(relation) < 0) relation = "none"
  var mapping = token(source.mappingStatus || "automatic")
  if (["mapped", "automatic", "unavailable"].indexOf(mapping) < 0) mapping = "automatic"
  return {
    id: publicId(source.id),
    label: publicLabel(source.label, category),
    category: category,
    transport: publicTransport(source.transport),
    capabilities: publicCapabilities(source.capabilities),
    seat: /^seat[0-9a-z-]{0,32}$/.test(token(source.seat || "default")) ? token(source.seat || "default") : "default",
    connected: source.connected === true,
    parent: publicId(source.parent),
    relation: relation,
    mappedOutput: publicId(source.mappedOutput),
    mappingStatus: mapping,
    formFactorRole: publicFormFactorRole(source.formFactorRole),
    capabilitySource: sourceList(source, "backend", category).slice(0, 8),
    confidence: confidence(source.confidence, "unknown")
  }
}

function publicGeometry(value) {
  var source = object(value)
  return {
    x: clamp(source.x, -1000000, 1000000, 0),
    y: clamp(source.y, -1000000, 1000000, 0),
    width: clamp(source.width, 0, 1000000, 0),
    height: clamp(source.height, 0, 1000000, 0)
  }
}

function publicOutput(value, index) {
  var source = object(value)
  var role = token(source.role || "unknown")
  if (["internal", "external", "primary", "presentation", "unknown"].indexOf(role) < 0) role = "unknown"
  var orientation = token(source.orientation || "auto")
  if (["auto", "normal", "90", "180", "270", "left", "right", "inverted", "unknown"].indexOf(orientation) < 0) orientation = "unknown"
  return {
    id: publicId(source.id),
    name: publicLabel(source.name, "Display " + String(index + 1)),
    category: "display",
    geometry: publicGeometry(source.geometry),
    scale: clamp(source.scale, 0.25, 8, 1),
    orientation: orientation,
    role: role,
    connected: source.connected === true,
    capabilitySource: sourceList(source, "compositor", "display").slice(0, 8),
    confidence: confidence(source.confidence, "unknown")
  }
}

function publicRelationship(value) {
  var source = object(value)
  var type = token(source.type || "none")
  if (RELATIONS.indexOf(type) < 0) type = "none"
  return {
    from: publicId(source.from),
    to: publicId(source.to),
    type: type,
    confidence: confidence(source.confidence, "unknown"),
    source: sourceList(source, "backend", "unknown")[0]
  }
}

function publicSnapshot(graph) {
  var source = object(graph)
  var nodes = array(source.nodes).slice(0, MAX_NODES).map(publicNode).filter(function(row) { return row.id !== "" })
  var outputs = array(source.outputs).slice(0, MAX_OUTPUTS).map(function(row, index) { return publicOutput(row, index) }).filter(function(row) { return row.id !== "" })
  var relationships = array(source.relationships).slice(0, MAX_RELATIONSHIPS).map(publicRelationship).filter(function(row) { return row.from !== "" && row.to !== "" && row.type !== "none" })
  var health = object(source.health)
  return {
    schemaVersion: SCHEMA_VERSION,
    revision: Number(source.revision || 0),
    nodes: nodes,
    relationships: relationships,
    outputs: outputs,
    health: { available: health.available === true, backend: token(health.backend || "unavailable") || "unavailable", reason: token(health.reason || "") || "unknown" },
    confidence: Object.assign({ confirmed: 0, probable: 0, unknown: 0 }, object(source.confidence)),
    summary: summary(source)
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  CATEGORIES: CATEGORIES,
  CONFIDENCES: CONFIDENCES,
  BOUNDS: { nodes: MAX_NODES, outputs: MAX_OUTPUTS, relationships: MAX_RELATIONSHIPS },
  stableId: stableId,
  categoryFrom: categoryFrom,
  capabilities: capabilities,
  normalizeNode: normalizeNode,
  normalizeOutput: normalizeOutput,
  fromSnapshot: fromSnapshot,
  normalize: fromSnapshot,
  applyEvent: applyEvent,
  emptyState: emptyState,
  summary: summary,
  publicSnapshot: publicSnapshot
}
if (typeof module !== "undefined") module.exports = api
