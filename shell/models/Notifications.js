function object(value) { return value && typeof value === "object" ? value : {} }

function wildcard(pattern, value) {
  var source = String(pattern || "").toLowerCase()
  var text = String(value || "").toLowerCase()
  if (!source) return false
  var escaped = source.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".")
  try { return new RegExp("^" + escaped + "$").test(text) } catch (error) { return false }
}

function muted(app, list) {
  var values = Array.isArray(list) ? list : []
  for (var i = 0; i < values.length; i++) if (wildcard(values[i], app)) return true
  return false
}

function timestampLabel(timestamp, now) {
  var value = Number(timestamp || 0)
  if (!isFinite(value) || value <= 0) return ""
  var age = Math.max(0, Number(now || Date.now()) - value)
  if (age < 60000) return "now"
  if (age < 3600000) return Math.floor(age / 60000) + "m"
  if (age < 86400000) return Math.floor(age / 3600000) + "h"
  try { return new Date(value).toLocaleDateString() } catch (error) { return "" }
}

function rawRows(backend, limit) {
  var model = backend && backend.popupModel
  if (!model || typeof model.get !== "function") return []
  var max = Math.max(0, Math.floor(Number(limit || 200)))
  var rows = []
  for (var i = 0; i < model.count && rows.length < max; i++) {
    var row = object(model.get(i))
    rows.push({
      index: i,
      app: String(row.app || "unknown"),
      summary: String(row.summary || ""),
      body: String(row.body || ""),
      image: String(row.image || ""),
      urgency: row.urgency,
      timestamp: Number(row.timestamp || 0),
      originalId: Number(row.originalId || row.id || 0)
    })
  }
  return rows
}

function rows(backend, config, now) {
  var settings = object(config)
  var limit = Math.max(0, Math.floor(Number(settings.maxHistory || 200)))
  var source = rawRows(backend, limit)
  var grouped = settings.groupByApp !== false
  var result = []
  var positions = {}
  var mutedApps = Array.isArray(settings.perAppMute) ? settings.perAppMute : []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    if (muted(item.app, mutedApps)) continue
    var key = grouped ? item.app.toLowerCase() : String(item.originalId || item.index)
    var position = positions[key]
    if (position === undefined) {
      position = result.length
      positions[key] = position
      result.push({
        app: item.app,
        summary: item.summary,
        body: item.body,
        image: item.image,
        urgency: item.urgency,
        timestamp: item.timestamp,
        time: settings.timestamps === false ? "" : timestampLabel(item.timestamp, now),
        count: 0,
        indices: [],
        latestIndex: item.index,
        hasActions: settings.actions !== false
      })
    }
    var group = result[position]
    group.count++
    group.indices.push(item.index)
    if (item.timestamp >= group.timestamp) {
      group.summary = item.summary
      group.body = item.body
      group.image = item.image
      group.urgency = item.urgency
      group.timestamp = item.timestamp
      group.time = settings.timestamps === false ? "" : timestampLabel(item.timestamp, now)
      group.latestIndex = item.index
    }
  }
  return result
}

function sortDescending(indices) {
  var values = Array.isArray(indices) ? indices.slice() : []
  return values.map(function(value) { return Math.floor(Number(value)) }).filter(function(value) { return value >= 0 }).sort(function(a, b) { return b - a })
}

var api = { muted: muted, timestampLabel: timestampLabel, rawRows: rawRows, rows: rows, sortDescending: sortDescending }
if (typeof module !== "undefined") module.exports = api
