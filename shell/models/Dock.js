function normalizeId(value) {
  var id = String(value || "").trim()
  return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id
}

function uniqueIds(values) {
  var seen = {}
  var result = []
  var list = Array.isArray(values) ? values : []
  for (var i = 0; i < list.length; i++) {
    var id = normalizeId(list[i])
    if (!id || seen[id]) continue
    seen[id] = true
    result.push(id)
  }
  return result
}

function reorder(values, id, targetIndex) {
  var result = uniqueIds(values)
  var key = normalizeId(id)
  var from = result.indexOf(key)
  if (from < 0) return result
  result.splice(from, 1)
  var index = Math.max(0, Math.min(result.length, Math.floor(Number(targetIndex || 0))))
  result.splice(index, 0, key)
  return result
}

function config(config) {
  var dock = config && config.dock ? config.dock : {}
  return {
    position: ["bottom", "left", "right", "top"].indexOf(String(dock.position || "bottom")) >= 0 ? String(dock.position || "bottom") : "bottom",
    mode: ["gnome", "floating", "full-width", "panel"].indexOf(String(dock.mode || "floating")) >= 0 ? String(dock.mode || "floating") : "floating",
    autohide: dock.autohide !== false,
    autohideMode: String(dock.autohideMode || "intelligent"),
    workspaceIsolation: dock.workspaceIsolation === true,
    monitorIsolation: dock.monitorIsolation === true,
    iconSize: Math.max(24, Number(dock.iconSize || 48)),
    minIconSize: Math.max(24, Number(dock.minIconSize || 40)),
    maxIconSize: Math.max(Number(dock.minIconSize || 40), Number(dock.maxIconSize || 64))
  }
}

var api = { normalizeId: normalizeId, uniqueIds: uniqueIds, reorder: reorder, config: config }
if (typeof module !== "undefined") module.exports = api
