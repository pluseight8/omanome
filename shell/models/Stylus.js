function text(value) { return String(value || "").toLowerCase() }

function isTouchscreen(device) {
  if (!device) return false
  var kind = text(device.type || device.deviceType || device.kind)
  var name = text(device.name || device.identifier || device.device)
  if (kind.indexOf("touchpad") >= 0 || name.indexOf("touchpad") >= 0 || name.indexOf("trackpad") >= 0) return false
  return kind.indexOf("touch") >= 0 || name.indexOf("touchscreen") >= 0 || name.indexOf("touch screen") >= 0
}

function isStylus(device) {
  if (!device) return false
  var kind = text(device.type || device.deviceType || device.kind)
  var name = text(device.name || device.identifier || device.device)
  return kind.indexOf("tablet") >= 0 || kind.indexOf("stylus") >= 0 || kind.indexOf("pen") >= 0 || name.indexOf("stylus") >= 0 || name.indexOf("pen") >= 0 || name.indexOf("wacom") >= 0
}

function capabilities(device) {
  var item = device || {}
  var caps = item.capabilities || item.capability || {}
  function yes(key) { return item[key] === true || caps[key] === true || caps[key] === 1 }
  return {
    pressure: yes("pressure") || yes("pressureRange") || item.pressureMin !== undefined,
    tilt: yes("tilt") || yes("tiltX") || yes("tiltY"),
    rotation: yes("rotation") || item.rotation !== undefined,
    proximity: yes("proximity") || yes("hover"),
    eraser: yes("eraser") || text(item.toolType).indexOf("eraser") >= 0,
    barrelButtons: Number(item.buttons || item.buttonCount || 0) > 0 || yes("buttons"),
    toolType: String(item.toolType || item.type || "unknown")
  }
}

function classify(devices) {
  var list = Array.isArray(devices) ? devices : []
  var result = []
  for (var i = 0; i < list.length; i++) {
    if (!isStylus(list[i])) continue
    result.push({ device: list[i], capabilities: capabilities(list[i]) })
  }
  return result
}

var api = { isTouchscreen: isTouchscreen, isStylus: isStylus, capabilities: capabilities, classify: classify }
if (typeof module !== "undefined") module.exports = api
