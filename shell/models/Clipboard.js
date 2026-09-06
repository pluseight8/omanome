var SENSITIVE_MIME_HINTS = ["password", "secret", "credential", "token", "private-key", "private_key"]

function object(value) { return value && typeof value === "object" ? value : {} }

function sensitiveMime(mime) {
  var value = String(mime || "").toLowerCase()
  for (var i = 0; i < SENSITIVE_MIME_HINTS.length; i++)
    if (value.indexOf(SENSITIVE_MIME_HINTS[i]) >= 0) return true
  return false
}

function normalizeTags(value) {
  var source = Array.isArray(value) ? value : String(value || "").split(",")
  var result = []
  for (var i = 0; i < source.length && result.length < 12; i++) {
    var tag = String(source[i] || "").trim().slice(0, 48)
    if (tag && result.indexOf(tag) < 0) result.push(tag)
  }
  return result
}

function normalize(value) {
  if (typeof value === "string") value = { type: "text", text: value }
  var source = object(value)
  var type = String(source.type || "text")
  var mime = String(source.mime || (type === "image" ? "image/png" : "text/plain"))
  if (source.sensitive === true || sensitiveMime(mime)) return null

  var item = {
    type: type,
    mime: mime,
    capturedAt: String(source.capturedAt || ""),
    pinned: source.pinned === true,
    tags: normalizeTags(source.tags),
    sourceApp: String(source.sourceApp || "")
  }
  if (type === "text") {
    item.text = String(source.text || "")
    return item.text.length > 0 ? item : null
  }
  if (type === "image" && source.path) {
    item.path = String(source.path)
    return item
  }
  return null
}

function parse(line) {
  try { return normalize(JSON.parse(String(line || "").trim())) } catch (error) { return null }
}

function key(entry) {
  return entry && entry.type === "image" ? "image:" + entry.path : "text:" + (entry ? entry.text : "")
}

function mergeMetadata(next, old) {
  var item = normalize(next)
  var previous = normalize(old)
  if (!item) return null
  if (!previous || key(item) !== key(previous)) return item
  item.pinned = item.pinned || previous.pinned
  item.tags = normalizeTags(item.tags.concat(previous.tags || []))
  if (!item.sourceApp) item.sourceApp = previous.sourceApp
  return item
}

function add(history, entry, limit) {
  var item = normalize(entry)
  var max = Math.max(0, Math.floor(Number(limit || 100)))
  if (!item || max === 0) return []
  var itemKey = key(item)
  var values = Array.isArray(history) ? history : []
  var result = [item]
  for (var i = 0; i < values.length && result.length < max; i++) {
    var old = normalize(values[i])
    if (old && key(old) !== itemKey) result.push(old)
    else if (old && key(old) === itemKey) result[0] = mergeMetadata(item, old)
  }
  return result
}

function capturedMillis(item) {
  var value = Date.parse(String(item && item.capturedAt || ""))
  return isFinite(value) ? value : 0
}

function approxBytes(item) {
  var value = JSON.stringify(item || {})
  return value.length * 2 + (item && item.type === "text" ? String(item.text || "").length * 2 : 0)
}

function prune(history, settings, now) {
  var config = object(settings)
  var limit = Math.max(0, Math.floor(Number(config.historyLimit || 100)))
  var retentionDays = Math.max(0, Number(config.retentionDays || 0))
  var maxBytes = Math.max(0, Number(config.maxStorageMb || 0)) * 1024 * 1024
  var timestamp = Number(now || Date.now())
  var values = Array.isArray(history) ? history : []
  var result = []
  var bytes = 0
  for (var i = 0; i < values.length; i++) {
    var item = normalize(values[i])
    if (!item) continue
    var age = capturedMillis(item)
    if (!item.pinned && retentionDays > 0 && age > 0 && timestamp - age > retentionDays * 86400000) continue
    if (!item.pinned && maxBytes > 0 && bytes + approxBytes(item) > maxBytes) continue
    if (!item.pinned && limit > 0 && result.length >= limit) continue
    result.push(item)
    bytes += approxBytes(item)
  }
  return result
}

function filtered(history, query) {
  var needle = String(query || "").trim().toLowerCase()
  var values = Array.isArray(history) ? history : []
  var result = []
  for (var i = 0; i < values.length; i++) {
    var item = normalize(values[i])
    if (!item) continue
    var haystack = item.type === "image" ? item.mime + " image " + item.tags.join(" ") : item.text + " " + item.tags.join(" ")
    if (!needle || haystack.toLowerCase().indexOf(needle) >= 0) result.push({ item: item, index: i })
  }
  return result
}

function clearUnpinned(history) {
  var values = Array.isArray(history) ? history : []
  return values.map(normalize).filter(function(item) { return item && item.pinned })
}

function togglePin(history, index) {
  var values = Array.isArray(history) ? history.map(normalize) : []
  var n = Math.floor(Number(index))
  if (n < 0 || n >= values.length || !values[n]) return values
  values[n].pinned = !values[n].pinned
  return values
}

function editText(history, index, text) {
  var values = Array.isArray(history) ? history.map(normalize) : []
  var n = Math.floor(Number(index))
  var value = String(text || "")
  if (n < 0 || n >= values.length || !values[n] || values[n].type !== "text" || !value) return values
  values[n].text = value
  return values
}

function setTags(history, index, tags) {
  var values = Array.isArray(history) ? history.map(normalize) : []
  var n = Math.floor(Number(index))
  if (n < 0 || n >= values.length || !values[n]) return values
  values[n].tags = normalizeTags(tags)
  return values
}

function wildcard(pattern, value) {
  var source = String(pattern || "").toLowerCase()
  var text = String(value || "").toLowerCase()
  if (!source) return false
  var escaped = source.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".")
  try { return new RegExp("^" + escaped + "$").test(text) } catch (error) { return false }
}

function excludedApp(appId, excludedApps) {
  var list = Array.isArray(excludedApps) ? excludedApps : []
  for (var i = 0; i < list.length; i++) if (wildcard(list[i], appId)) return true
  return false
}

function persistable(history, settings) {
  var config = object(settings)
  var values = Array.isArray(history) ? history : []
  return prune(values, config).filter(function(item) { return config.persistPinnedOnly !== true || item.pinned })
}

function preview(entry, limit) {
  var item = normalize(entry)
  if (!item) return ""
  if (item.type === "image") return item.mime
  return item.text.replace(/\s+/g, " ").slice(0, Math.max(1, Number(limit || 140)))
}

var api = {
  SENSITIVE_MIME_HINTS: SENSITIVE_MIME_HINTS,
  sensitiveMime: sensitiveMime,
  normalize: normalize,
  normalizeTags: normalizeTags,
  parse: parse,
  key: key,
  add: add,
  prune: prune,
  filtered: filtered,
  clearUnpinned: clearUnpinned,
  togglePin: togglePin,
  editText: editText,
  setTags: setTags,
  excludedApp: excludedApp,
  persistable: persistable,
  preview: preview
}
if (typeof module !== "undefined") module.exports = api
