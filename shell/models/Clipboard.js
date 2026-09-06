function normalize(value) {
  if (typeof value === "string") return value.length > 0 ? { type: "text", text: value } : null
  if (!value || typeof value !== "object") return null
  var type = String(value.type || "text")
  if (type === "text") {
    var text = String(value.text || "")
    return text.length > 0 ? { type: "text", text: text, capturedAt: String(value.capturedAt || "") } : null
  }
  if (type === "image" && value.path) return { type: "image", path: String(value.path), mime: String(value.mime || "image/png"), capturedAt: String(value.capturedAt || "") }
  return null
}

function parse(line) {
  try { return normalize(JSON.parse(String(line || "").trim())) } catch (error) { return null }
}

function key(entry) {
  return entry && entry.type === "image" ? "image:" + entry.path : "text:" + (entry ? entry.text : "")
}

function add(history, entry, limit) {
  var item = normalize(entry)
  var max = Math.max(0, Number(limit || 100))
  if (!item || max === 0) return []
  var result = [item]
  var itemKey = key(item)
  var values = Array.isArray(history) ? history : []
  for (var i = 0; i < values.length && result.length < max; i++) {
    var old = normalize(values[i])
    if (old && key(old) !== itemKey) result.push(old)
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
    var haystack = item.type === "image" ? item.mime + " image" : item.text
    if (!needle || haystack.toLowerCase().indexOf(needle) >= 0) result.push({ item: item, index: i })
  }
  return result
}
