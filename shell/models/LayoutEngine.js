// Shared, compositor-neutral geometry for tablet multitasking.  Coordinates
// are logical monitor coordinates; applying a layout is deliberately left to
// the caller so preview can remain a local geometry overlay.

var LAYOUT_SCHEMA_VERSION = 1
var DEFAULT_GAP = 12

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}

function positive(value, fallback) {
  return Math.max(0, number(value, fallback))
}

function clamp(value, minimum, maximum) {
  return Math.max(Number(minimum), Math.min(Number(maximum), Number(value)))
}

function text(value) {
  return String(value === undefined || value === null ? "" : value).trim().toLowerCase()
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function orientation(value, width, height) {
  var name = text(value)
  if (name.indexOf("portrait") >= 0 || name === "vertical" || name === "top-bottom") return "portrait"
  if (name.indexOf("landscape") >= 0 || name === "horizontal" || name === "left-right") return "landscape"
  return number(width, 1) < number(height, 1) ? "portrait" : "landscape"
}

function rect(x, y, width, height) {
  return {
    x: Math.round(number(x, 0)),
    y: Math.round(number(y, 0)),
    width: Math.max(1, Math.round(number(width, 1))),
    height: Math.max(1, Math.round(number(height, 1)))
  }
}

function right(value) { return number(value && value.x, 0) + number(value && value.width, 0) }
function bottom(value) { return number(value && value.y, 0) + number(value && value.height, 0) }

function normalizeReserved(source, options) {
  var item = source && typeof source === "object" ? source : {}
  var extra = options && options.reserved && typeof options.reserved === "object" ? options.reserved : {}
  return {
    top: positive(extra.top !== undefined ? extra.top : (item.top !== undefined ? item.top : options && options.barReserved), 0),
    right: positive(extra.right !== undefined ? extra.right : item.right, 0),
    bottom: positive(extra.bottom !== undefined ? extra.bottom : (item.bottom !== undefined ? item.bottom : options && options.dockReserved), 0),
    left: positive(extra.left !== undefined ? extra.left : item.left, 0)
  }
}

function normalizeMonitor(value, options) {
  var source = value && typeof value === "object" ? value : {}
  var settings = options && typeof options === "object" ? options : {}
  var scale = clamp(source.scale !== undefined ? source.scale : source.deviceScale, 0.5, 4) || 1
  var width = source.logicalWidth !== undefined ? source.logicalWidth : source.width
  var height = source.logicalHeight !== undefined ? source.logicalHeight : source.height
  if (width === undefined && source.physicalWidth !== undefined) width = number(source.physicalWidth, 1) / scale
  if (height === undefined && source.physicalHeight !== undefined) height = number(source.physicalHeight, 1) / scale
  width = Math.max(1, number(width, 1))
  height = Math.max(1, number(height, 1))
  var reserved = normalizeReserved(source.reserved, settings)
  reserved.top = clamp(reserved.top, 0, Math.max(0, height - 1))
  reserved.bottom = clamp(reserved.bottom, 0, Math.max(0, height - reserved.top - 1))
  reserved.left = clamp(reserved.left, 0, Math.max(0, width - 1))
  reserved.right = clamp(reserved.right, 0, Math.max(0, width - reserved.left - 1))
  var x = number(source.x, 0)
  var y = number(source.y, 0)
  var usable = rect(x + reserved.left, y + reserved.top,
    width - reserved.left - reserved.right,
    height - reserved.top - reserved.bottom)
  return {
    name: String(source.name || source.monitor || "active"),
    x: x,
    y: y,
    width: width,
    height: height,
    scale: scale,
    orientation: orientation(settings.orientation || source.orientation, width, height),
    reserved: reserved,
    usable: usable
  }
}

function gap(options) {
  var value = options && options.gap !== undefined ? options.gap : DEFAULT_GAP
  return clamp(positive(value, DEFAULT_GAP), 0, 160)
}

function axisSegments(start, length, count, spacing) {
  var totalSpacing = Math.max(0, count - 1) * spacing
  var segment = Math.max(1, (length - totalSpacing) / Math.max(1, count))
  var result = []
  for (var i = 0; i < count; i++) result.push({ start: start + i * (segment + spacing), length: segment })
  return result
}

function splitRects(area, ratio, axis, spacing) {
  var value = clamp(number(ratio, 0.5), 0.01, 0.99)
  var gapSize = Math.min(spacing, axis === "horizontal" ? area.height - 1 : area.width - 1)
  if (axis === "horizontal") {
    var usableHeight = Math.max(1, area.height - gapSize)
    var topHeight = usableHeight * value
    return [
      rect(area.x, area.y, area.width, topHeight),
      rect(area.x, area.y + topHeight + gapSize, area.width, usableHeight - topHeight)
    ]
  }
  var usableWidth = Math.max(1, area.width - gapSize)
  var leftWidth = usableWidth * value
  return [
    rect(area.x, area.y, leftWidth, area.height),
    rect(area.x + leftWidth + gapSize, area.y, usableWidth - leftWidth, area.height)
  ]
}

function gridRects(area, columns, rows, spacing) {
  var horizontal = axisSegments(area.x, area.width, columns, spacing)
  var vertical = axisSegments(area.y, area.height, rows, spacing)
  var result = []
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      result.push(rect(horizontal[column].start, vertical[row].start, horizontal[column].length, vertical[row].length))
    }
  }
  return result
}

function canonicalZoneId(value) {
  var name = text(value).replace(/_/g, "-")
  var aliases = {
    "left": "half-left",
    "right": "half-right",
    "top": "half-top",
    "bottom": "half-bottom",
    "1/2-left": "half-left",
    "1/2-right": "half-right",
    "1/2-top": "half-top",
    "1/2-bottom": "half-bottom",
    "top-half": "half-top",
    "bottom-half": "half-bottom",
    "1/3-left": "third-left",
    "1/3-center": "third-center",
    "1/3-right": "third-right",
    "1/3-top": "third-top",
    "1/3-bottom": "third-bottom",
    "2/3-left": "two-thirds-left",
    "2/3-right": "two-thirds-right",
    "2/3-top": "two-thirds-top",
    "2/3-bottom": "two-thirds-bottom",
    "maximize": "maximized",
    "max": "maximized",
    "top-left": "quarter-top-left",
    "top-right": "quarter-top-right",
    "bottom-left": "quarter-bottom-left",
    "bottom-right": "quarter-bottom-right"
  }
  return aliases[name] || name
}

function zoneLabelKey(id) {
  var labels = {
    "half-left": "snap.leftHalf",
    "half-right": "snap.rightHalf",
    "half-top": "snap.topHalf",
    "half-bottom": "snap.bottomHalf",
    "third-left": "snap.leftThird",
    "third-center": "snap.centerThird",
    "third-right": "snap.rightThird",
    "third-top": "snap.topThird",
    "third-bottom": "snap.bottomThird",
    "two-thirds-left": "snap.leftTwoThirds",
    "two-thirds-right": "snap.rightTwoThirds",
    "two-thirds-top": "snap.topTwoThirds",
    "two-thirds-bottom": "snap.bottomTwoThirds",
    "quarter-top-left": "snap.topLeftQuarter",
    "quarter-top-right": "snap.topRightQuarter",
    "quarter-bottom-left": "snap.bottomLeftQuarter",
    "quarter-bottom-right": "snap.bottomRightQuarter",
    maximized: "snap.maximize"
  }
  return labels[id] || "snap.custom"
}

function zoneIds(direction) {
  if (direction === "portrait") return [
    "half-top", "half-bottom", "third-top", "third-bottom",
    "two-thirds-top", "two-thirds-bottom", "maximized"
  ]
  return [
    "half-left", "half-right", "third-left", "third-center", "third-right",
    "two-thirds-left", "two-thirds-right", "quarter-top-left",
    "quarter-top-right", "quarter-bottom-left", "quarter-bottom-right", "maximized"
  ]
}

function customZone(item, area, settings) {
  var source = item && typeof item === "object" ? item : {}
  var slots = Array.isArray(source.slots) ? source.slots : []
  if (slots.length === 0 || slots.length > 4) return null
  var result = []
  for (var i = 0; i < slots.length; i++) {
    var slot = slots[i] || {}
    var x = Number(slot.x)
    var y = Number(slot.y)
    var width = Number(slot.width)
    var height = Number(slot.height)
    if (!isFinite(x) || !isFinite(y) || !isFinite(width) || !isFinite(height)) return null
    if (x < 0 || y < 0 || x > 1 || y > 1 || width <= 0 || height <= 0 || width > 1 || height > 1) return null
    if (x + width > 1 || y + height > 1) return null
    result.push({
      id: String(slot.id || "slot-" + (i + 1)),
      rect: rect(area.x + area.width * x, area.y + area.height * y, area.width * width, area.height * height)
    })
  }
  return {
    id: canonicalZoneId(source.id || source.name || "custom"),
    labelKey: String(source.labelKey || "snap.custom"),
    orientation: settings.orientation,
    axis: settings.orientation === "portrait" ? "horizontal" : "vertical",
    slots: result,
    custom: true
  }
}

function builtInZone(id, monitor, settings) {
  var area = monitor.usable
  var spacing = gap(settings)
  var canonical = canonicalZoneId(id)
  var axis = settings.orientation === "portrait" ? "horizontal" : "vertical"
  var slots = []
  if (canonical === "maximized") {
    slots = [{ id: "primary", rect: clone(area) }]
  } else if (canonical === "half-left" || canonical === "half-right") {
    var halves = splitRects(area, 0.5, "vertical", spacing)
    slots = [{ id: "primary", rect: halves[canonical === "half-left" ? 0 : 1] }]
  } else if (canonical === "half-top" || canonical === "half-bottom") {
    var verticalHalves = splitRects(area, 0.5, "horizontal", spacing)
    slots = [{ id: "primary", rect: verticalHalves[canonical === "half-top" ? 0 : 1] }]
  } else if (canonical === "third-left" || canonical === "third-center" || canonical === "third-right") {
    var thirds = axisSegments(area.x, area.width, 3, spacing)
    var thirdIndex = canonical === "third-left" ? 0 : (canonical === "third-center" ? 1 : 2)
    slots = [{ id: "primary", rect: rect(thirds[thirdIndex].start, area.y, thirds[thirdIndex].length, area.height) }]
  } else if (canonical === "third-top" || canonical === "third-bottom") {
    var topThirds = axisSegments(area.y, area.height, 3, spacing)
    var topIndex = canonical === "third-top" ? 0 : 2
    slots = [{ id: "primary", rect: rect(area.x, topThirds[topIndex].start, area.width, topThirds[topIndex].length) }]
  } else if (canonical === "two-thirds-left" || canonical === "two-thirds-right") {
    var horizontalPair = splitRects(area, 2 / 3, "vertical", spacing)
    if (canonical === "two-thirds-right") horizontalPair.reverse()
    slots = [{ id: "primary", rect: horizontalPair[0] }]
  } else if (canonical === "two-thirds-top" || canonical === "two-thirds-bottom") {
    var verticalPair = splitRects(area, 2 / 3, "horizontal", spacing)
    if (canonical === "two-thirds-bottom") verticalPair.reverse()
    slots = [{ id: "primary", rect: verticalPair[0] }]
  } else if (canonical.indexOf("quarter-") === 0) {
    var quarters = gridRects(area, 2, 2, spacing)
    var quarterIndex = {
      "quarter-top-left": 0,
      "quarter-top-right": 1,
      "quarter-bottom-left": 2,
      "quarter-bottom-right": 3
    }[canonical]
    if (quarterIndex === undefined) return null
    slots = [{ id: "primary", rect: quarters[quarterIndex] }]
  } else {
    return null
  }
  return {
    id: canonical,
    labelKey: zoneLabelKey(canonical),
    orientation: settings.orientation,
    axis: axis,
    slots: slots,
    custom: false
  }
}

function zones(monitorValue, options) {
  var settings = options && typeof options === "object" ? clone(options) : {}
  var monitor = normalizeMonitor(monitorValue, settings)
  settings.orientation = orientation(settings.orientation || monitor.orientation, monitor.width, monitor.height)
  var ids = Array.isArray(settings.layouts) && settings.layouts.length > 0 ? settings.layouts : zoneIds(settings.orientation)
  var result = []
  for (var i = 0; i < ids.length; i++) {
    var builtIn = builtInZone(ids[i], monitor, settings)
    if (builtIn) result.push(builtIn)
  }
  var custom = Array.isArray(settings.customLayouts) ? settings.customLayouts : []
  for (var c = 0; c < custom.length; c++) {
    var customValue = customZone(custom[c], monitor.usable, settings)
    if (customValue) result.push(customValue)
  }
  return result
}

function areaForZone(monitorValue, zoneId, options) {
  var list = zones(monitorValue, Object.assign({}, options || {}, { layouts: [zoneId] }))
  return list.length > 0 ? list[0] : null
}

function minimumSize(value) {
  var source = value && typeof value === "object" ? value : {}
  return { width: Math.max(1, number(source.width, 1)), height: Math.max(1, number(source.height, 1)) }
}

function fitMinimum(value, containerValue, minimumValue) {
  var source = rect(value && value.x, value && value.y, value && value.width, value && value.height)
  var container = rect(containerValue && containerValue.x, containerValue && containerValue.y, containerValue && containerValue.width, containerValue && containerValue.height)
  var minimum = minimumSize(minimumValue)
  var width = Math.min(container.width, Math.max(source.width, minimum.width))
  var height = Math.min(container.height, Math.max(source.height, minimum.height))
  var x = clamp(source.x, container.x, right(container) - width)
  var y = clamp(source.y, container.y, bottom(container) - height)
  return {
    rect: rect(x, y, width, height),
    satisfied: width >= minimum.width && height >= minimum.height,
    bestEffort: width < minimum.width || height < minimum.height
  }
}

function expand(value, amount, containerValue) {
  var source = rect(value && value.x, value && value.y, value && value.width, value && value.height)
  var container = rect(containerValue && containerValue.x, containerValue && containerValue.y, containerValue && containerValue.width, containerValue && containerValue.height)
  var padding = Math.max(0, number(amount, 0))
  var x = Math.max(container.x, source.x - padding)
  var y = Math.max(container.y, source.y - padding)
  var maxRight = Math.min(right(container), right(source) + padding)
  var maxBottom = Math.min(bottom(container), bottom(source) + padding)
  return rect(x, y, maxRight - x, maxBottom - y)
}

function activationRect(zone, monitorValue, inputKind, options) {
  if (!zone || !zone.slots || zone.slots.length === 0) return null
  var monitor = normalizeMonitor(monitorValue, options || {})
  var settings = options && typeof options === "object" ? options : {}
  var kind = text(inputKind || "mouse")
  var base = kind === "touch" ? Math.max(80, number(settings.touchActivationSize, 132)) :
    (kind === "stylus" ? Math.max(44, number(settings.stylusActivationSize, 76)) : Math.max(40, number(settings.mouseActivationSize, 56)))
  var region = expand(zone.slots[0].rect, base, monitor.usable)
  return {
    rect: region,
    inputKind: kind,
    movementThreshold: kind === "touch" ? Math.max(8, number(settings.touchMovementThreshold, 18)) : Math.max(4, number(settings.movementThreshold, 8)),
    dwellMs: kind === "touch" ? Math.max(80, number(settings.touchDwellMs, 220)) : (kind === "stylus" ? Math.max(60, number(settings.stylusDwellMs, 120)) : Math.max(0, number(settings.mouseDwellMs, 90))),
    accidentalProtection: kind === "touch"
  }
}

function ratioValue(value) {
  var name = text(value).replace(/\s+/g, "")
  var known = { "50/50": 0.5, "40/60": 0.4, "60/40": 0.6, "33/67": 1 / 3, "67/33": 2 / 3 }
  if (known[name] !== undefined) return known[name]
  return clamp(number(value, 0.5), 0.05, 0.95)
}

function splitPair(monitorValue, ratio, options, windows) {
  var settings = options && typeof options === "object" ? clone(options) : {}
  var monitor = normalizeMonitor(monitorValue, settings)
  var direction = orientation(settings.orientation || monitor.orientation, monitor.width, monitor.height)
  var area = splitRects(monitor.usable, ratioValue(ratio), direction === "portrait" ? "horizontal" : "vertical", gap(settings))
  var ids = Array.isArray(windows) ? windows : []
  return {
    schemaVersion: LAYOUT_SCHEMA_VERSION,
    type: "split-pair",
    orientation: direction,
    axis: direction === "portrait" ? "horizontal" : "vertical",
    ratio: ratioValue(ratio),
    ratioName: String(ratio || "50/50"),
    monitor: { name: monitor.name, scale: monitor.scale },
    usable: clone(monitor.usable),
    slots: [
      { id: "primary", windowId: String(ids[0] || ""), rect: area[0] },
      { id: "secondary", windowId: String(ids[1] || ""), rect: area[1] }
    ]
  }
}

function layoutForZone(monitorValue, zoneId, options, windowId) {
  var settings = options && typeof options === "object" ? clone(options) : {}
  var monitor = normalizeMonitor(monitorValue, settings)
  var zone = areaForZone(monitor, zoneId, settings)
  if (!zone) return null
  var minimum = settings.minSize || settings.minimumSize || {}
  var slots = []
  for (var i = 0; i < zone.slots.length; i++) {
    var fitted = fitMinimum(zone.slots[i].rect, monitor.usable, Array.isArray(minimum) ? minimum[i] : minimum)
    slots.push({ id: zone.slots[i].id, windowId: Array.isArray(windowId) ? String(windowId[i] || "") : String(i === 0 ? (windowId || "") : ""), rect: fitted.rect, minimumSatisfied: fitted.satisfied, bestEffort: fitted.bestEffort })
  }
  return {
    schemaVersion: LAYOUT_SCHEMA_VERSION,
    type: zone.slots.length > 1 ? "custom" : "snap",
    id: zone.id,
    labelKey: zone.labelKey,
    orientation: zone.orientation,
    axis: zone.axis,
    monitor: { name: monitor.name, scale: monitor.scale },
    usable: clone(monitor.usable),
    slots: slots
  }
}

function signature(layout) {
  if (!layout || !Array.isArray(layout.slots)) return ""
  return [layout.type, layout.id || "", layout.orientation || "", layout.monitor && layout.monitor.name || "", layout.slots.map(function(slot) {
    return [slot.windowId || "", slot.rect.x, slot.rect.y, slot.rect.width, slot.rect.height].join(":")
  }).join("|")].join("/")
}

function contains(value, point) {
  var source = value || {}
  var x = number(point && point.x, NaN)
  var y = number(point && point.y, NaN)
  return isFinite(x) && isFinite(y) && x >= source.x && y >= source.y && x < right(source) && y < bottom(source)
}

var api = {
  LAYOUT_SCHEMA_VERSION: LAYOUT_SCHEMA_VERSION,
  number: number,
  clamp: clamp,
  orientation: orientation,
  rect: rect,
  normalizeMonitor: normalizeMonitor,
  canonicalZoneId: canonicalZoneId,
  zoneIds: zoneIds,
  zones: zones,
  areaForZone: areaForZone,
  activationRect: activationRect,
  ratioValue: ratioValue,
  splitPair: splitPair,
  layoutForZone: layoutForZone,
  fitMinimum: fitMinimum,
  expand: expand,
  contains: contains,
  signature: signature
}
if (typeof module !== "undefined") module.exports = api
