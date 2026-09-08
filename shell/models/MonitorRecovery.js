// Pure event-driven recovery for output hotplug and topology changes.
//
// A plan is calculated from one monitor event and one window snapshot. It
// never polls, persists compositor identities, or selects windows by caption.
// The service is responsible for dispatching the bounded address-scoped
// commands and for best-effort rollback.

var SCHEMA_VERSION = 1
var MAX_MONITORS = 16
var MAX_WINDOWS = 64
var MAX_COMMANDS = 128
var MIN_WIDTH = 240
var MIN_HEIGHT = 160

function object(value) { return value && typeof value === "object" && !Array.isArray(value) ? value : {} }
function list(value) { return Array.isArray(value) ? value : [] }
function finite(value, fallback) { var result = Number(value); return isFinite(result) ? result : fallback }
function clamp(value, minimum, maximum) { return Math.max(Number(minimum), Math.min(Number(maximum), Number(value))) }
function text(value, fallback, limit) { return String(value === undefined || value === null ? (fallback || "") : value).trim().slice(0, Math.max(1, Number(limit || 96))) }
function clone(value) { return JSON.parse(JSON.stringify(value)) }

function name(value) {
  var item = object(value)
  return text(item.name || item.monitor || item.output || item.id, "", 128)
}

function orientation(value, width, height) {
  var requested = text(value).toLowerCase()
  if (requested.indexOf("portrait") >= 0 || requested === "vertical") return "portrait"
  if (requested.indexOf("landscape") >= 0 || requested === "horizontal") return "landscape"
  return finite(width, 1) < finite(height, 1) ? "portrait" : "landscape"
}

function rect(value) {
  var item = object(value)
  var position = object(item.at || item.position)
  var size = object(item.size || item.geometry)
  return {
    x: Math.round(finite(item.x !== undefined ? item.x : position.x !== undefined ? position.x : position[0], 0)),
    y: Math.round(finite(item.y !== undefined ? item.y : position.y !== undefined ? position.y : position[1], 0)),
    width: Math.max(0, Math.round(finite(item.width !== undefined ? item.width : size.width !== undefined ? size.width : size[0], 0))),
    height: Math.max(0, Math.round(finite(item.height !== undefined ? item.height : size.height !== undefined ? size.height : size[1], 0)))
  }
}

function normalizeMonitor(value) {
  var source = object(value)
  var scale = clamp(finite(source.scale !== undefined ? source.scale : source.factor, 1), 0.5, 4)
  var rawWidth = source.logicalWidth !== undefined ? source.logicalWidth : source.width
  var rawHeight = source.logicalHeight !== undefined ? source.logicalHeight : source.height
  if (rawWidth === undefined) rawWidth = finite(source.physicalWidth, 1) / scale
  if (rawHeight === undefined) rawHeight = finite(source.physicalHeight, 1) / scale
  var width = Math.max(1, finite(rawWidth, 1))
  var height = Math.max(1, finite(rawHeight, 1))
  var reserved = object(source.reserved)
  var usableSource = object(source.usable)
  var usable = rect(usableSource)
  if (usable.width <= 0 || usable.height <= 0) {
    var x = finite(source.x, 0)
    var y = finite(source.y, 0)
    var left = Math.max(0, finite(reserved.left, 0))
    var top = Math.max(0, finite(reserved.top, 0))
    var right = Math.max(0, finite(reserved.right, 0))
    var bottom = Math.max(0, finite(reserved.bottom, 0))
    usable = { x: x + left, y: y + top, width: Math.max(1, width - left - right), height: Math.max(1, height - top - bottom) }
  }
  return {
    name: name(source) || "active",
    x: finite(source.x, 0),
    y: finite(source.y, 0),
    width: width,
    height: height,
    scale: scale,
    orientation: orientation(source.orientation || source.transform, width, height),
    usable: { x: usable.x, y: usable.y, width: Math.max(1, usable.width), height: Math.max(1, usable.height) }
  }
}

function normalizeMonitors(values) {
  var result = []
  var seen = {}
  var source = list(values)
  for (var i = 0; i < source.length && result.length < MAX_MONITORS; i++) {
    var item = normalizeMonitor(source[i])
    if (!item.name || seen[item.name]) continue
    seen[item.name] = true
    result.push(item)
  }
  return result
}

function monitorMap(values) {
  var result = {}
  var listValue = normalizeMonitors(values)
  for (var i = 0; i < listValue.length; i++) result[listValue[i].name] = listValue[i]
  return result
}

function diff(previous, current) {
  var before = monitorMap(previous)
  var after = monitorMap(current)
  var removed = []
  var added = []
  var changed = []
  for (var oldName in before) {
    if (!after[oldName]) removed.push(oldName)
    else if (JSON.stringify(before[oldName]) !== JSON.stringify(after[oldName])) changed.push(oldName)
  }
  for (var newName in after) if (!before[newName]) added.push(newName)
  return { previous: before, current: after, removed: removed.slice(0, MAX_MONITORS), added: added.slice(0, MAX_MONITORS), changed: changed.slice(0, MAX_MONITORS) }
}

function foreign(value) { return value && value.wayland ? value.wayland : value }

function address(value) {
  var item = object(foreign(value))
  var raw = text(item.address, "", 96)
  if (raw.indexOf("address:") === 0) raw = raw.substring(8)
  return /^[0-9a-fA-Fx]+$/.test(raw) ? raw : ""
}

function identity(value) {
  var item = object(foreign(value))
  var raw = text(item.identity, "", 96)
  if (raw.indexOf("address:") === 0) return raw
  var current = address(item)
  return current ? "address:" + current : ""
}

function monitorForWindow(value) {
  var item = object(foreign(value))
  var monitor = item.monitorName || item.monitor || item.output
  if (monitor && typeof monitor === "object") monitor = monitor.name || monitor.id
  return text(monitor, "", 128)
}

function windowRect(value) {
  var item = object(foreign(value))
  var result = rect(item)
  if (result.width <= 0 || result.height <= 0) result = rect(item.geometry || item.rect || item.at || item.position)
  if (result.width <= 0) result.width = Math.max(0, Math.round(finite(item.width, 0)))
  if (result.height <= 0) result.height = Math.max(0, Math.round(finite(item.height, 0)))
  return result
}

function overlaps(value, area) {
  if (!value || value.width <= 0 || value.height <= 0 || !area) return false
  return value.x < area.x + area.width && value.x + value.width > area.x && value.y < area.y + area.height && value.y + value.height > area.y
}

function safeSize(source, area, options) {
  var settings = object(options)
  var minimum = object(settings.minimumWindowSize)
  var width = source.width > 0 ? source.width : finite(settings.defaultWidth, 640)
  var height = source.height > 0 ? source.height : finite(settings.defaultHeight, 480)
  var minimumWidth = Math.max(1, finite(minimum.width, MIN_WIDTH))
  var minimumHeight = Math.max(1, finite(minimum.height, MIN_HEIGHT))
  return {
    width: Math.round(clamp(width, Math.min(minimumWidth, area.width), area.width)),
    height: Math.round(clamp(height, Math.min(minimumHeight, area.height), area.height))
  }
}

function safeRect(sourceRect, sourceMonitor, targetMonitor, options) {
  var area = targetMonitor && targetMonitor.usable ? targetMonitor.usable : targetMonitor
  if (!area || area.width <= 0 || area.height <= 0) return null
  var sourceArea = sourceMonitor && sourceMonitor.usable ? sourceMonitor.usable : null
  var size = safeSize(sourceRect || {}, area, options)
  var x = finite(sourceRect && sourceRect.x, area.x)
  var y = finite(sourceRect && sourceRect.y, area.y)
  if (sourceArea && sourceArea.width > 0 && sourceArea.height > 0 && sourceRect && sourceRect.width > 0 && sourceRect.height > 0) {
    var xRatio = (sourceRect.x - sourceArea.x) / sourceArea.width
    var yRatio = (sourceRect.y - sourceArea.y) / sourceArea.height
    x = area.x + clamp(xRatio, 0, 1) * Math.max(0, area.width - size.width)
    y = area.y + clamp(yRatio, 0, 1) * Math.max(0, area.height - size.height)
  }
  return {
    x: Math.round(clamp(x, area.x, Math.max(area.x, area.x + area.width - size.width))),
    y: Math.round(clamp(y, area.y, Math.max(area.y, area.y + area.height - size.height))),
    width: size.width,
    height: size.height
  }
}

function geometryCommands(windowAddress, target) {
  if (!windowAddress || !target) return []
  return [
    "resizewindowpixel exact " + target.width + " " + target.height + ",address:" + windowAddress,
    "movewindowpixel exact " + target.x + " " + target.y + ",address:" + windowAddress
  ]
}

function affectedGroups(groups, windowIdentity, removedMonitor) {
  var result = []
  var source = list(groups)
  for (var i = 0; i < source.length && result.length < MAX_MONITORS; i++) {
    var group = object(source[i])
    var runtime = object(group.runtime)
    var ids = list(runtime.memberIds)
    var members = list(runtime.members)
    var affected = ids.indexOf(windowIdentity) >= 0
    if (!affected) for (var j = 0; j < members.length; j++) if (text(members[j] && members[j].monitorName) === removedMonitor) { affected = true; break }
    if (affected && text(group.id)) result.push(text(group.id))
  }
  return result
}

function targetMonitorFor(window, monitors, settings) {
  var listValue = normalizeMonitors(monitors)
  if (listValue.length === 0) return null
  var source = object(settings)
  var preferred = text(source.activeMonitor || source.targetMonitor, "", 128)
  var item = object(foreign(window))
  if (!preferred) preferred = text(item.preferredMonitor, "", 128)
  if (preferred) for (var i = 0; i < listValue.length; i++) if (listValue[i].name === preferred) return listValue[i]
  for (var j = 0; j < listValue.length; j++) if (item.focused === true && listValue[j].name === monitorForWindow(window)) return listValue[j]
  return listValue[0]
}

function plan(previous, current, windows, groups, options) {
  var settings = object(options)
  var topology = diff(previous, current)
  var currentList = normalizeMonitors(current)
  var sourceWindows = list(windows)
  var commands = []
  var rollback = []
  var moved = []
  var skipped = []
  var affected = []
  var targetDefault = targetMonitorFor({}, currentList, settings)
  if (!targetDefault) return { ok: false, reason: "no-monitor-available", schemaVersion: SCHEMA_VERSION, topology: topology, commands: [], rollback: [], moved: [], skipped: [] }

  for (var i = 0; i < sourceWindows.length && i < MAX_WINDOWS; i++) {
    var window = sourceWindows[i]
    var currentName = monitorForWindow(window)
    var oldMonitor = topology.previous[currentName]
    var newMonitor = topology.current[currentName]
    var sourceRect = windowRect(window)
    var target = newMonitor || targetDefault
    var needsRecovery = topology.removed.indexOf(currentName) >= 0 || !newMonitor || (settings.recoverOffscreen !== false && !overlaps(sourceRect, target.usable))
    if (!needsRecovery) continue
    var windowAddress = address(window)
    var windowIdentity = identity(window)
    if (!windowAddress || !windowIdentity) {
      skipped.push({ monitor: currentName, reason: "window-address-unavailable" })
      continue
    }
    var safe = safeRect(sourceRect, oldMonitor || newMonitor, target, settings)
    if (!safe) {
      skipped.push({ identity: windowIdentity, reason: "safe-geometry-unavailable" })
      continue
    }
    var nextCommands = geometryCommands(windowAddress, safe)
    var oldSafe = oldMonitor && sourceRect.width > 0 && sourceRect.height > 0 ? sourceRect : null
    var nextRollback = oldSafe ? geometryCommands(windowAddress, oldSafe) : []
    if (commands.length + nextCommands.length > MAX_COMMANDS) {
      skipped.push({ identity: windowIdentity, reason: "recovery-command-limit" })
      continue
    }
    commands = commands.concat(nextCommands)
    rollback = nextRollback.concat(rollback).slice(0, MAX_COMMANDS)
    moved.push({ identity: windowIdentity, from: currentName || "unknown", to: target.name, rect: safe })
    var ids = affectedGroups(groups, windowIdentity, currentName)
    for (var groupIndex = 0; groupIndex < ids.length; groupIndex++) if (affected.indexOf(ids[groupIndex]) < 0) affected.push(ids[groupIndex])
  }
  return {
    ok: true,
    schemaVersion: SCHEMA_VERSION,
    reason: moved.length > 0 ? "monitor-recovery-planned" : (topology.removed.length > 0 ? "no-addressed-windows-to-recover" : "topology-unchanged"),
    topology: { removed: topology.removed, added: topology.added, changed: topology.changed },
    targetMonitor: targetDefault.name,
    commands: commands.slice(0, MAX_COMMANDS),
    rollback: rollback.slice(0, MAX_COMMANDS),
    moved: moved.slice(0, MAX_WINDOWS),
    skipped: skipped.slice(0, MAX_WINDOWS),
    affectedGroups: affected.slice(0, MAX_MONITORS)
  }
}

function summary(value) {
  var source = value || {}
  return {
    ok: source.ok === true,
    reason: text(source.reason, "not-used", 96),
    removed: list(source.topology && source.topology.removed).slice(0, MAX_MONITORS),
    added: list(source.topology && source.topology.added).slice(0, MAX_MONITORS),
    changed: list(source.topology && source.topology.changed).slice(0, MAX_MONITORS),
    targetMonitor: text(source.targetMonitor, "", 128),
    moved: list(source.moved).slice(0, MAX_WINDOWS).map(function(item) { return { from: text(item.from), to: text(item.to), rect: item.rect || null } }),
    skipped: list(source.skipped).slice(0, MAX_WINDOWS).map(function(item) { return { reason: text(item.reason) } }),
    affectedGroups: list(source.affectedGroups).slice(0, MAX_MONITORS),
    commandCount: Math.min(MAX_COMMANDS, list(source.commands).length),
    rollbackCount: Math.min(MAX_COMMANDS, list(source.rollback).length)
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_MONITORS: MAX_MONITORS,
  MAX_WINDOWS: MAX_WINDOWS,
  MAX_COMMANDS: MAX_COMMANDS,
  normalizeMonitor: normalizeMonitor,
  normalizeMonitors: normalizeMonitors,
  diff: diff,
  safeRect: safeRect,
  plan: plan,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
