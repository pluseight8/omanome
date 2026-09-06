function normalize(entry) {
  if (!entry) return null
  return {
    id: String(entry.id || entry.desktopId || entry.desktopFile || ""),
    name: String(entry.name || entry.genericName || entry.id || "Application"),
    comment: String(entry.comment || entry.description || ""),
    icon: String(entry.icon || "application-x-executable"),
    categories: entry.categories || []
  }
}

function searchable(entry) {
  var item = normalize(entry)
  if (!item) return ""
  return (item.name + " " + item.id + " " + item.comment + " " + item.categories.join(" ")).toLowerCase()
}

function sorted(entries, query, limit) {
  var needle = String(query || "").trim().toLowerCase()
  var values = Array.isArray(entries) ? entries : []
  var result = []
  for (var i = 0; i < values.length; i++) {
    var item = normalize(values[i])
    if (!item || !item.id) continue
    if (needle && searchable(item).indexOf(needle) < 0) continue
    result.push(item)
  }
  result.sort(function(a, b) { return a.name.localeCompare(b.name) || a.id.localeCompare(b.id) })
  return result.slice(0, Number(limit || 200))
}
