function normalize(entry) {
  if (!entry) return null
  var categories = Array.isArray(entry.categories) ? entry.categories : []
  var keywords = Array.isArray(entry.keywords) ? entry.keywords : []
  return {
    entry: entry,
    id: String(entry.id || entry.desktopId || entry.desktopFile || ""),
    name: String(entry.name || entry.genericName || entry.id || "Application"),
    genericName: String(entry.genericName || ""),
    comment: String(entry.comment || entry.description || ""),
    icon: String(entry.icon || "application-x-executable"),
    categories: categories,
    keywords: keywords,
    startupClass: String(entry.startupClass || ""),
    noDisplay: entry.noDisplay === true
  }
}

function searchable(entry) {
  var item = normalize(entry)
  if (!item) return ""
  return (item.name + " " + item.genericName + " " + item.id + " " + item.comment + " " + item.categories.join(" ") + " " + item.keywords.join(" ")).toLowerCase()
}

function score(item, needle, favorites, recent) {
  if (!needle) return 0
  var value = searchable(item)
  if (value.indexOf(needle) < 0) return -1
  var result = 0
  if (String(item.name).toLowerCase().indexOf(needle) === 0) result += 100
  if (String(item.id).toLowerCase().indexOf(needle) === 0) result += 60
  if (favorites.indexOf(item.id) >= 0) result += 20
  var recentIndex = recent.indexOf(item.id)
  if (recentIndex >= 0) result += Math.max(0, 15 - recentIndex)
  return result
}

function sorted(entries, query, limit, favoriteIds, recentIds) {
  var needle = String(query || "").trim().toLowerCase()
  var values = Array.isArray(entries) ? entries : []
  var favorites = Array.isArray(favoriteIds) ? favoriteIds.map(function(id) { return String(id).replace(/\.desktop$/, "") }) : []
  var recent = Array.isArray(recentIds) ? recentIds.map(function(id) { return String(id).replace(/\.desktop$/, "") }) : []
  var result = []
  for (var i = 0; i < values.length; i++) {
    var item = normalize(values[i])
    if (!item || !item.id) continue
    if (item.noDisplay) continue
    var itemScore = score(item, needle, favorites, recent)
    if (needle && itemScore < 0) continue
    item.favorite = favorites.indexOf(item.id) >= 0
    item.recent = recent.indexOf(item.id) >= 0
    item.score = itemScore
    result.push(item)
  }
  result.sort(function(a, b) {
    if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
    if (a.score !== b.score) return b.score - a.score
    var recentCompare = recent.indexOf(a.id) - recent.indexOf(b.id)
    if (a.recent !== b.recent) return a.recent ? -1 : 1
    if (a.recent && recentCompare !== 0) return recentCompare
    return a.name.localeCompare(b.name) || a.id.localeCompare(b.id)
  })
  return result.slice(0, Number(limit || 200))
}

function categories(entries) {
  var seen = {}
  var result = []
  var values = Array.isArray(entries) ? entries : []
  for (var i = 0; i < values.length; i++) {
    var item = normalize(values[i])
    if (!item) continue
    for (var j = 0; j < item.categories.length; j++) {
      var category = String(item.categories[j] || "").trim()
      if (category && !seen[category]) { seen[category] = true; result.push(category) }
    }
  }
  return result.sort(function(a, b) { return a.localeCompare(b) }).slice(0, 24)
}

function inCategory(item, category) {
  if (!item || !category || category === "All") return true
  return Array.isArray(item.categories) && item.categories.indexOf(category) >= 0
}

var api = { normalize: normalize, searchable: searchable, sorted: sorted, categories: categories, inCategory: inCategory }
if (typeof module !== "undefined") module.exports = api
