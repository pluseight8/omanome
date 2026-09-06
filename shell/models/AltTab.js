function object(value) { return value && typeof value === "object" ? value : {} }

function foreign(window) {
  var item = object(window)
  return item.wayland || item.foreign || item
}

function appId(window) {
  var item = foreign(window)
  return String(item.appId || item.app_id || item.desktopId || window && window.appId || "unknown")
}

function title(window) {
  var item = foreign(window)
  return String(item.title || window && window.title || appId(window))
}

function workspaceId(window) {
  var item = object(window)
  var workspace = item.workspace || item.lastIpcObject && item.lastIpcObject.workspace
  if (workspace && typeof workspace === "object") return Number(workspace.id || 0)
  return Number(workspace || 0)
}

function monitorName(window) {
  var item = object(window)
  var monitor = item.monitor || item.lastIpcObject && item.lastIpcObject.monitor
  if (monitor && typeof monitor === "object") return String(monitor.name || monitor.id || "")
  return String(monitor || "")
}

function windowKey(window) {
  var item = foreign(window)
  return String(item.address || window && window.address || appId(window) + "\u0000" + title(window))
}

function previewTexture(window) {
  var item = foreign(window)
  var candidates = ["previewTexture", "thumbnailTexture", "texture", "preview", "thumbnail"]
  for (var i = 0; i < candidates.length; i++) {
    var name = candidates[i]
    if (item && item[name] !== undefined && item[name] !== null && typeof item[name] !== "function")
      return { available: true, property: name, value: item[name] }
  }
  return { available: false, property: "", value: null }
}

function hasLivePreview(windows) {
  var list = Array.isArray(windows) ? windows : []
  for (var i = 0; i < list.length; i++) if (previewTexture(list[i]).available) return true
  return false
}

function normalize(config) {
  var source = object(config)
  var modes = Array.isArray(source.modes) ? source.modes.map(String) : ["coverflow", "carousel", "gnome", "grid", "compact"]
  var style = modes.indexOf(String(source.style || "coverflow")) >= 0 ? String(source.style || "coverflow") : "coverflow"
  var scope = ["current-workspace", "all-workspaces", "current-monitor"].indexOf(String(source.scope || "current-workspace")) >= 0 ? String(source.scope || "current-workspace") : "current-workspace"
  return {
    style: style,
    modes: modes,
    groupByApp: source.groupByApp !== false,
    scope: scope,
    angle: Math.max(0, Math.min(60, Number(source.angle || 28))),
    spacing: Math.max(0, Math.min(0.5, Number(source.spacing || 0.18))),
    scale: Math.max(0.5, Math.min(1.0, Number(source.scale || 0.82))),
    selectedScale: Math.max(1.0, Math.min(1.2, Number(source.selectedScale || 1.0))),
    sideOpacity: Math.max(0.1, Math.min(1.0, Number(source.sideOpacity || 0.68))),
    livePreview: String(source.livePreview || "auto"),
    touchSwipe: source.touchSwipe !== false,
    touchFling: source.touchFling !== false,
    stylusPreciseSelection: source.stylusPreciseSelection !== false
  }
}

function selectable(windows, config, context) {
  var options = normalize(config)
  var state = object(context)
  var list = Array.isArray(windows) ? windows : []
  var filtered = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item) continue
    if (options.scope === "current-workspace" && state.workspaceId !== undefined && workspaceId(item) !== Number(state.workspaceId)) continue
    if (options.scope === "current-monitor" && state.monitorName && monitorName(item) !== String(state.monitorName)) continue
    var foreignItem = foreign(item)
    if (foreignItem.minimized === true) continue
    filtered.push(item)
  }
  if (!options.groupByApp) return filtered.map(function(item) { return { key: windowKey(item), window: item, windows: [item], appId: appId(item), title: title(item), count: 1 } })
  var groups = {}
  var order = []
  for (var j = 0; j < filtered.length; j++) {
    var key = appId(filtered[j])
    if (!groups[key]) { groups[key] = []; order.push(key) }
    groups[key].push(filtered[j])
  }
  return order.map(function(key) {
    var entries = groups[key]
    return { key: key, window: entries[0], windows: entries, appId: appId(entries[0]), title: title(entries[0]), count: entries.length }
  })
}

function windowOf(entry) { return entry && entry.window ? entry.window : entry }

function visual(index, selectedIndex, count, config) {
  var options = normalize(config)
  var distance = Number(index) - Number(selectedIndex)
  if (count > 1) {
    if (distance > count / 2) distance -= count
    if (distance < -count / 2) distance += count
  }
  var side = distance === 0
  var mode = options.style
  var rotation = mode === "grid" || mode === "compact" ? 0 : Math.max(-options.angle, Math.min(options.angle, distance * options.angle))
  var scale = side ? options.selectedScale : options.scale
  if (mode === "compact") scale *= 0.9
  if (mode === "grid") scale = side ? options.selectedScale : 0.94
  return { distance: distance, rotation: rotation, scale: scale, opacity: side ? 1.0 : options.sideOpacity, z: 100 - Math.abs(distance), selected: side }
}

function previewState(config, windows) {
  var options = normalize(config)
  var available = hasLivePreview(windows)
  var requested = options.livePreview !== "never"
  return { requested: requested, available: available, enabled: requested && available, reason: available ? "native texture property" : "Quickshell Toplevel has no texture provider" }
}

function moveIndex(index, delta, count) {
  if (count <= 0) return 0
  return (Number(index) + Number(delta) + count) % count
}

var api = { foreign: foreign, appId: appId, title: title, workspaceId: workspaceId, monitorName: monitorName, windowKey: windowKey, previewTexture: previewTexture, hasLivePreview: hasLivePreview, normalize: normalize, selectable: selectable, windowOf: windowOf, visual: visual, previewState: previewState, moveIndex: moveIndex }
if (typeof module !== "undefined") module.exports = api
