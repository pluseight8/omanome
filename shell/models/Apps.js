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
    item.favoriteIndex = favorites.indexOf(item.id)
    item.recent = recent.indexOf(item.id) >= 0
    item.score = itemScore
    result.push(item)
  }
  result.sort(function(a, b) {
    if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
    if (a.favorite && b.favorite && a.favoriteIndex !== b.favoriteIndex) return a.favoriteIndex - b.favoriteIndex
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

function normalizeFolders(values) {
  var source = Array.isArray(values) ? values : []
  var result = []
  var seen = {}
  for (var i = 0; i < source.length; i++) {
    var item = source[i] || {}
    var id = String(item.id || "folder-" + (i + 1))
    if (!id || seen[id]) continue
    var apps = Array.isArray(item.apps) ? item.apps.map(function(value) { return String(value || "").replace(/\.desktop$/, "") }).filter(Boolean) : []
    result.push({ id: id, name: String(item.name || "Folder"), apps: unique(apps) })
    seen[id] = true
  }
  return result
}

function unique(values) {
  var seen = {}
  var result = []
  var list = Array.isArray(values) ? values : []
  for (var i = 0; i < list.length; i++) {
    var value = String(list[i] || "")
    if (!value || seen[value]) continue
    seen[value] = true
    result.push(value)
  }
  return result
}

function folderContains(folder, id) {
  var item = folder || {}
  var key = String(id || "").replace(/\.desktop$/, "")
  return Array.isArray(item.apps) && item.apps.indexOf(key) >= 0
}

function addToFolder(folders, folderId, id) {
  var result = normalizeFolders(folders)
  var key = String(id || "").replace(/\.desktop$/, "")
  for (var i = 0; i < result.length; i++) if (result[i].id === String(folderId)) result[i].apps = unique(result[i].apps.concat([key]))
  return result
}

function removeFromFolder(folders, folderId, id) {
  var result = normalizeFolders(folders)
  var key = String(id || "").replace(/\.desktop$/, "")
  for (var i = 0; i < result.length; i++) if (result[i].id === String(folderId)) result[i].apps = result[i].apps.filter(function(value) { return value !== key })
  return result
}

function renameFolder(folders, folderId, name) {
  var result = normalizeFolders(folders)
  var value = String(name || "").trim()
  if (!value) return result
  for (var i = 0; i < result.length; i++) if (result[i].id === String(folderId)) result[i].name = value
  return result
}

function deleteFolder(folders, folderId) {
  return normalizeFolders(folders).filter(function(item) { return item.id !== String(folderId) })
}

var api = { normalize: normalize, searchable: searchable, sorted: sorted, categories: categories, inCategory: inCategory, normalizeFolders: normalizeFolders, folderContains: folderContains, addToFolder: addToFolder, removeFromFolder: removeFromFolder, renameFolder: renameFolder, deleteFolder: deleteFolder }
if (typeof module !== "undefined") module.exports = api
