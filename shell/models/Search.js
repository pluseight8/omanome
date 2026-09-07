function text(value) { return String(value === undefined || value === null ? "" : value).toLowerCase().trim() }

function score(value, query) {
  var source = text(value)
  var needle = text(query)
  if (!needle) return 0
  var index = source.indexOf(needle)
  if (index < 0) return -1
  return (index === 0 ? 100 : 0) + Math.max(0, 40 - index)
}

function result(kind, id, title, subtitle, scoreValue, payload, action) {
  return { kind: kind, id: String(id || ""), title: String(title || ""), subtitle: String(subtitle || ""), score: scoreValue, payload: payload || {}, action: action || "" }
}

function apps(entries, query, limit) {
  var needle = text(query)
  var values = Array.isArray(entries) ? entries : []
  var output = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i] || {}
    if (item.noDisplay === true) continue
    var value = [item.name, item.genericName, item.id, item.comment, (item.categories || []).join(" ")].join(" ")
    var itemScore = score(value, needle)
    if (needle && itemScore < 0) continue
    output.push(result("app", item.id, item.name, item.comment || item.genericName, itemScore, item, "launch"))
  }
  output.sort(function(a, b) { return b.score - a.score || a.title.localeCompare(b.title) })
  return output.slice(0, Number(limit || 8))
}

function windows(entries, query, titleFor, appFor, limit) {
  var needle = text(query)
  var values = Array.isArray(entries) ? entries : []
  var output = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i] || {}
    var title = typeof titleFor === "function" ? titleFor(item) : item.title
    var app = typeof appFor === "function" ? appFor(item) : item.appId
    var itemScore = score([title, app].join(" "), needle)
    if (needle && itemScore < 0) continue
    output.push(result("window", item.address || item.title || i, title, app, itemScore, item, "activate"))
  }
  output.sort(function(a, b) { return b.score - a.score || a.title.localeCompare(b.title) })
  return output.slice(0, Number(limit || 8))
}

function settings(entries, query, limit) {
  var needle = text(query)
  var values = Array.isArray(entries) ? entries : []
  var output = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i] || {}
    var itemScore = score([item.title, item.description, (item.aliases || []).join(" ")].join(" "), needle)
    if (needle && itemScore < 0) continue
    output.push(result("setting", item.key, item.title, item.description, itemScore, item, "open-settings"))
  }
  output.sort(function(a, b) { return b.score - a.score || a.title.localeCompare(b.title) })
  return output.slice(0, Number(limit || 8))
}

function actions(entries, query, limit) {
  var needle = text(query)
  var values = Array.isArray(entries) ? entries : []
  var output = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i] || {}
    var itemScore = score([item.title, item.description, (item.aliases || []).join(" ")].join(" "), needle)
    if (needle && itemScore < 0) continue
    output.push(result("action", item.key, item.title, item.description, itemScore, item, "quick-action"))
  }
  output.sort(function(a, b) { return b.score - a.score || a.title.localeCompare(b.title) })
  return output.slice(0, Number(limit || 8))
}

function all(query, providers) {
  var source = providers || {}
  return [].concat(
    apps(source.apps, query, 6),
    windows(source.windows, query, source.titleFor, source.appFor, 6),
    settings(source.settings, query, 5),
    actions(source.actions, query, 5)
  ).sort(function(a, b) { return b.score - a.score || a.kind.localeCompare(b.kind) || a.title.localeCompare(b.title) })
}

var api = { text: text, score: score, apps: apps, windows: windows, settings: settings, actions: actions, all: all }
if (typeof module !== "undefined") module.exports = api
