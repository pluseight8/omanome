function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function lower(value) {
  return string(value).toLowerCase()
}

function bool(value) {
  return value === true || value === 1 || lower(value) === "true" || lower(value) === "yes"
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function token(value) {
  return lower(value).replace(/[\s_]+/g, "-")
}

var MAX_DEVICES = 256
var MAX_MONITORS = 32

function values(item) {
  var source = object(item)
  var result = []
  var fields = [source.type, source.deviceType, source.device_type, source.kind, source.inputType, source.input_type, source.role]
  for (var i = 0; i < fields.length; i++) {
    var value = token(fields[i])
    if (value && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function capabilities(item) {
  var source = object(item)
  var raw = source.capabilities || source.capability || source.features || {}
  var result = {}
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length; i++) result[token(raw[i])] = true
  } else {
    for (var key in object(raw)) if (bool(raw[key])) result[token(key)] = true
  }
  var fields = ["keyboard", "touch", "touchscreen", "stylus", "tablet", "tablet-tool", "pressure", "tilt-x", "tilt-y", "eraser", "buttons", "proximity"]
  for (var f = 0; f < fields.length; f++) if (bool(source[fields[f]]) || bool(source[fields[f].replace(/-/g, "_")])) result[fields[f]] = true
  return result
}

function hasAny(source, names) {
  var item = object(source)
  var typeList = values(item)
  var caps = capabilities(item)
  for (var i = 0; i < names.length; i++) {
    var wanted = token(names[i])
    if (typeList.indexOf(wanted) >= 0 || caps[wanted] === true) return true
  }
  return false
}

function roleFor(item, hint) {
  var source = object(item)
  var role = token(hint || source.role)
  if (role === "touch" || role === "touchscreen" || role === "touch-device") return "touchscreen"
  if (role === "tablet" || role === "tablet-tool" || role === "stylus" || role === "pen") return "stylus"
  if (role === "keyboard" || role === "keyboards") return "keyboard"
  if (role === "tablet-pad" || role === "pad") return "tablet-pad"
  if (role === "mouse" || role === "pointer" || role === "touchpad" || role === "trackpad") return role
  if (hasAny(source, ["touchscreen", "touch-screen", "touch-display"])) return "touchscreen"
  if (hasAny(source, ["tablet", "tablet-tool", "stylus", "pen", "eraser", "pressure", "tilt-x", "tilt-y"])) return "stylus"
  if (hasAny(source, ["keyboard", "keys"])) return "keyboard"
  if (hasAny(source, ["touchpad", "trackpad"])) return "touchpad"
  if (hasAny(source, ["mouse", "pointer"])) return "mouse"
  return "unknown"
}

function durablePart(source, names) {
  for (var i = 0; i < names.length; i++) {
    var value = string(source[names[i]]).trim()
    if (value) return value
  }
  return ""
}

// Device identities can contain a USB serial or a Bluetooth address. Keep the
// identity deterministic for mapping persistence, but never expose those raw
// values in shell state or diagnostics.
function opaquePart(value) {
  var source = string(value)
  var hash = 2166136261
  for (var i = 0; i < source.length; i++) {
    hash ^= source.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return ("00000000" + (hash >>> 0).toString(16)).slice(-8)
}

// Stable identity deliberately prefers hardware/path characteristics. The
// display name is only a last-resort component and is never the sole key.
function stableId(item, hint) {
  var source = object(item)
  var role = roleFor(source, hint)
  var vendor = durablePart(source, ["vendorId", "vendor_id", "vendor", "idVendor", "ID_VENDOR_ID"])
  var product = durablePart(source, ["productId", "product_id", "product", "idProduct", "ID_MODEL_ID"])
  var serial = durablePart(source, ["serial", "serialNumber", "serial_number", "ID_SERIAL_SHORT"])
  var path = durablePart(source, ["devpath", "devPath", "path", "phys", "devicePath", "ID_PATH"])
  var uniq = durablePart(source, ["uniq", "uniqueId", "unique_id", "address", "syspath"])
  var explicit = durablePart(source, ["stableId", "stable_id", "nodeId", "node_id", "deviceId", "device_id", "id", "identifier"])
  var name = durablePart(source, ["name", "device", "identifier", "ID_MODEL"])
  var caps = Object.keys(capabilities(source)).sort().join(",")
  var durable = []
  if (vendor) durable.push("vendor-" + vendor)
  if (product) durable.push("product-" + product)
  if (serial) durable.push("serial-h-" + opaquePart(serial))
  if (path) durable.push("path-h-" + opaquePart(path))
  if (uniq) durable.push("uniq-h-" + opaquePart(uniq))
  if (explicit && !/event[0-9]+|[\\/]dev[\\/]input/i.test(explicit)) durable.push("explicit-h-" + opaquePart(explicit))
  if (durable.length === 0) durable = ["fallback-h-" + opaquePart((name || "unnamed") + "|" + (caps || role))]
  return "input:" + role + ":" + durable.join("/")
}

function transport(item) {
  var source = object(item)
  var fields = [source.transport, source.connection, source.bus, source.backend, source.protocol, source.ID_BUS]
  for (var i = 0; i < fields.length; i++) {
    var value = token(fields[i])
    if (value) return value
  }
  return "unknown"
}

function isExcludedKeyboard(item) {
  var source = object(item)
  var name = token(source.name || source.device || source.identifier)
  return hasAny(source, ["consumer-control", "system-control", "power-button", "gamepad", "joystick", "tablet-pad"]) ||
    name.indexOf("consumer-control") >= 0 || name.indexOf("system-control") >= 0 || name.indexOf("power-button") >= 0
}

function isDetachable(item) {
  var source = object(item)
  var form = token(source.formFactor || source.form_factor || source.connection || source.role || source.type)
  return bool(source.detachable) || bool(source.detachableKeyboard) || form.indexOf("detachable") >= 0 || form.indexOf("tablet-keyboard") >= 0
}

function isBluetooth(item) {
  var value = transport(item)
  var name = token(object(item).name || object(item).device || object(item).identifier)
  return value.indexOf("bluetooth") >= 0 || value.indexOf("bluez") >= 0 || name.indexOf("bluetooth") >= 0
}

function normalize(item, hint, sourceName) {
  var source = object(item)
  var role = roleFor(source, hint)
  var caps = capabilities(source)
  return {
    id: stableId(source, hint),
    name: durablePart(source, ["name", "device", "identifier", "ID_MODEL"]) || "Unnamed input device",
    role: role,
    type: string(source.type || source.deviceType || source.kind || role || "unknown"),
    source: string(sourceName || "compositor"),
    seat: durablePart(source, ["seat", "seatName", "seat_name", "ID_SEAT"]) || "default",
    vendorId: durablePart(source, ["vendorId", "vendor_id", "vendor", "idVendor", "ID_VENDOR_ID"]),
    productId: durablePart(source, ["productId", "product_id", "product", "idProduct", "ID_MODEL_ID"]),
    serialPresent: durablePart(source, ["serial", "serialNumber", "serial_number", "ID_SERIAL_SHORT"]) !== "",
    path: durablePart(source, ["devpath", "devPath", "path", "phys", "devicePath", "ID_PATH"]),
    transport: transport(source),
    detachable: isDetachable(source),
    bluetooth: isBluetooth(source),
    output: durablePart(source, ["output", "mappedOutput", "mapped_output", "belongsTo", "belongs_to"]),
    capabilities: caps,
    proximity: bool(source.proximity) || bool(source.inProximity) || bool(source.in_proximity),
    present: true
  }
}

function groups(snapshot) {
  var source = object(snapshot)
  var result = []
  var known = [
    ["keyboards", "keyboard"], ["keyboard", "keyboard"],
    ["touch", "touchscreen"], ["touchDevices", "touchscreen"], ["touchdevices", "touchscreen"],
    ["tablets", "stylus"], ["tabletTools", "stylus"], ["tablettools", "stylus"],
    ["tabletPads", "tablet-pad"], ["tabletpads", "tablet-pad"],
    ["mice", "mouse"], ["pointers", "pointer"], ["touchpads", "touchpad"]
  ]
  for (var i = 0; i < known.length; i++) {
    var list = array(source[known[i][0]])
    for (var j = 0; j < list.length; j++) result.push({ item: list[j], role: known[i][1], source: known[i][0] })
  }
  var generic = array(source.devices)
  for (var g = 0; g < generic.length; g++) result.push({ item: generic[g], role: "", source: "devices" })
  return result
}

function normalizeSnapshot(snapshot) {
  var source = object(snapshot)
  var rows = groups(source)
  var devices = []
  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var item = normalize(rows[i].item, rows[i].role, rows[i].source)
    if (seen[item.id]) continue
    seen[item.id] = true
    if (devices.length < MAX_DEVICES) devices.push(item)
  }
  var switchValue = source.tabletSwitch
  if (switchValue === undefined) switchValue = source.tablet_switch
  if (switchValue === undefined && object(source.switches).tabletMode !== undefined) switchValue = object(source.switches).tabletMode
  if (switchValue === undefined && object(source.switches).tablet !== undefined) switchValue = object(source.switches).tablet
  var posture = string(source.posture || source.formFactor || source.form_factor || source.platformPosture || "").toLowerCase()
  var lid = string(source.lidState || source.lid_state || "").toLowerCase()
  return {
    schemaVersion: 1,
    devices: devices,
    monitors: array(source.monitors).slice(0, MAX_MONITORS),
    tabletSwitch: switchValue,
    posture: posture,
    lidState: lid,
    source: "compositor-snapshot"
  }
}

function emptyState() {
  return { schemaVersion: 1, revision: 0, devices: [], monitors: [], backend: "unavailable", hotplug: { available: false, lastEvent: "", lastAction: "" }, posture: {} }
}

function stateFromSnapshot(snapshot, previous) {
  var normalized = normalizeSnapshot(snapshot)
  var old = object(previous)
  return {
    schemaVersion: 1,
    revision: Number(old.revision || 0) + 1,
    devices: normalized.devices,
    monitors: normalized.monitors,
    backend: "hyprland-device-snapshot",
    hotplug: object(old.hotplug),
    posture: { tabletSwitch: normalized.tabletSwitch, posture: normalized.posture, lidState: normalized.lidState }
  }
}

function eventDevice(event) {
  var source = object(event)
  var item = object(source.device)
  if (Object.keys(item).length === 0) item = source
  return normalize(item, source.role, source.subsystem || "udev")
}

function eventSource(event) {
  var source = object(event)
  var item = object(source.device)
  return Object.keys(item).length === 0 ? source : item
}

function matchesEventDevice(existing, normalized, raw, roleHint) {
  var current = object(existing)
  var source = object(raw)
  if (current.id && current.id === normalized.id) return true
  var path = durablePart(source, ["devpath", "devPath", "path", "phys", "devicePath", "ID_PATH"])
  if (path && current.path && path === current.path && (!roleHint || current.role === normalized.role)) return true
  var vendor = durablePart(source, ["vendorId", "vendor_id", "vendor", "idVendor", "ID_VENDOR_ID"])
  var product = durablePart(source, ["productId", "product_id", "product", "idProduct", "ID_MODEL_ID"])
  if (vendor && product && current.vendorId === vendor && current.productId === product && current.role === normalized.role) return true
  return false
}

function mergeDevice(previous, next) {
  var old = object(previous)
  var fresh = object(next)
  var result = {}
  for (var key in old) result[key] = old[key]
  for (var field in fresh) {
    var value = fresh[field]
    if (value !== "" && value !== undefined && value !== null) result[field] = value
  }
  result.id = old.id || fresh.id
  result.present = fresh.present !== false
  return result
}

function applyEvent(previous, event) {
  var old = object(previous)
  var source = object(event)
  var current = array(old.devices).slice(0, MAX_DEVICES)
  var item = eventDevice(source)
  var raw = eventSource(source)
  var action = token(source.action || source.event || "change")
  var index = -1
  for (var i = 0; i < current.length; i++) {
    if (current[i] && matchesEventDevice(current[i], item, raw, source.role)) { index = i; break }
  }
  if (action === "remove" || action === "delete") {
    if (index >= 0) current.splice(index, 1)
  } else if (index >= 0) current[index] = mergeDevice(current[index], item)
  else if (current.length < MAX_DEVICES) current.push(item)
  return {
    schemaVersion: 1,
    revision: Number(old.revision || 0) + 1,
    devices: current,
    monitors: array(old.monitors).slice(0, MAX_MONITORS),
    backend: "udev-hotplug",
    hotplug: { available: true, lastEvent: string(source.subsystem || "input"), lastAction: action, lastDevice: item.id },
    posture: object(old.posture)
  }
}

function signalValue(snapshot, state, name, fallback) {
  var source = object(snapshot)
  if (source[name] !== undefined) return source[name]
  var current = object(state)
  if (object(current.posture)[name] !== undefined) return current.posture[name]
  return fallback
}

function postureSignals(snapshot, state, lastInput) {
  var normalized = normalizeSnapshot(snapshot)
  var current = object(state)
  var devices = array(current.devices).length > 0 ? current.devices : normalized.devices
  var touch = false
  var stylus = false
  var proximity = false
  var keyboard = false
  var detachable = false
  var bluetooth = false
  for (var i = 0; i < devices.length; i++) {
    var item = devices[i] || {}
    touch = touch || item.role === "touchscreen"
    stylus = stylus || item.role === "stylus"
    proximity = proximity || item.role === "stylus" && item.proximity === true
    if (item.role === "keyboard") {
      if (!isExcludedKeyboard(item)) {
        keyboard = true
        detachable = detachable || item.detachable === true
        bluetooth = bluetooth || item.bluetooth === true
      }
    }
  }
  var switchValue = signalValue(snapshot, state, "tabletSwitch", normalized.tabletSwitch)
  var switchObject = object(switchValue)
  var switchAvailable = typeof switchValue === "object" ? switchObject.available !== false : switchValue !== undefined && switchValue !== null
  var switchActive = typeof switchValue === "object" ? (switchObject.active === true || string(switchObject.state).toLowerCase() === "tablet") : bool(switchValue)
  var posture = string(signalValue(snapshot, state, "posture", normalized.posture)).toLowerCase()
  var lidState = string(signalValue(snapshot, state, "lidState", normalized.lidState)).toLowerCase()
  return {
    touchscreen: touch,
    stylus: stylus,
    stylusProximity: proximity,
    physicalKeyboard: keyboard,
    detachableKeyboard: detachable,
    bluetoothKeyboard: bluetooth,
    tabletSwitchAvailable: switchAvailable,
    tabletSwitchActive: switchActive,
    posture: posture,
    lidState: lidState,
    orientation: string(signalValue(snapshot, state, "orientation", "landscape")),
    lastInput: string(lastInput || "keyboard")
  }
}

function mapOutput(device, outputs, profile) {
  var item = object(device)
  var list = array(outputs)
  var settings = object(profile)
  var explicit = string(item.output || item.mappedOutput || item.mapped_output || settings.output)
  if (explicit) {
    for (var i = 0; i < list.length; i++) if (string(list[i] && (list[i].name || list[i].id)) === explicit) return { status: "mapped", output: explicit, reason: "explicit device mapping" }
    return { status: "unavailable", output: explicit, reason: "configured output is absent" }
  }
  if (list.length === 1) return { status: "mapped", output: string(list[0].name || list[0].id), reason: "single available output" }
  var builtin = bool(item.builtin) || string(item.outputRole).toLowerCase() === "internal"
  if (builtin) {
    for (var b = 0; b < list.length; b++) if (bool(list[b].builtin) || string(list[b].description || list[b].name).toLowerCase().indexOf("internal") >= 0) return { status: "mapped", output: string(list[b].name || list[b].id), reason: "capability-based internal output" }
  }
  return { status: "automatic", output: "", reason: list.length === 0 ? "no output inventory" : "compositor mapping owns target selection" }
}

function explain(signals, mode) {
  var source = object(signals)
  var rows = []
  if (source.tabletSwitchAvailable) rows.push("tablet switch: " + (source.tabletSwitchActive ? "active" : "inactive"))
  rows.push("physical keyboard: " + (source.physicalKeyboard ? "present" : "absent"))
  rows.push("touchscreen: " + (source.touchscreen ? "present" : "absent"))
  rows.push("stylus: " + (source.stylus ? (source.stylusProximity ? "present/in proximity" : "present") : "absent"))
  if (source.detachableKeyboard) rows.push("detachable keyboard: present")
  if (source.bluetoothKeyboard) rows.push("Bluetooth keyboard: present")
  if (source.posture) rows.push("posture: " + source.posture)
  if (source.lidState) rows.push("lid: " + source.lidState)
  rows.push("last input: " + string(source.lastInput || "unknown"))
  return { mode: string(mode || "desktop"), signals: source, lines: rows }
}

var api = {
  MAX_DEVICES: MAX_DEVICES,
  MAX_MONITORS: MAX_MONITORS,
  stableId: stableId,
  normalize: normalize,
  normalizeSnapshot: normalizeSnapshot,
  emptyState: emptyState,
  stateFromSnapshot: stateFromSnapshot,
  applyEvent: applyEvent,
  postureSignals: postureSignals,
  mapOutput: mapOutput,
  explain: explain
}
if (typeof module !== "undefined") module.exports = api
