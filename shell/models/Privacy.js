// Shared privacy boundary for runtime status and diagnostics.
//
// Internal models may need raw backend values while they are normalizing a
// snapshot. Anything crossing the Service status/diagnostics boundary goes
// through this module. Sensitive fields are dropped or replaced, strings are
// bounded, and collections cannot grow without a limit.

var SCHEMA_VERSION = 1
var MAX_DEPTH = 8
var MAX_ITEMS = 128
var MAX_KEYS = 128
var MAX_STRING = 192
var OPAQUE_ID = /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/
var MAC = /(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i
var EVENT_NODE = /(?:^|[\\/])(?:dev[\\/]input[\\/]event[0-9]+|event[0-9]+)(?:$|[\\/])/i
var PRIVATE_PATH = /(?:^|[\\/])(?:dev|sys|proc|run|home|tmp|var)[\\/]/i
var PRIVATE_TOKEN = /(?:serial|bluetooth[-_ ]?address|private[-_ ]?serial)/i

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function token(value) {
  return string(value).replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/[\\s_]+/g, "-").toLowerCase()
}

function sensitiveKey(value) {
  var name = token(value)
  var exact = [
    "address", "bluetooth-address", "mac", "mac-address", "uniq", "unique-id",
    "serial", "serial-number", "id-serial-short", "edid-serial", "physical-path",
    "device-path", "dev-path", "path", "syspath", "event", "last-event", "event-node",
    "event-path", "last-device", "clipboard", "clipboard-history", "typed-text",
    "surrounding-text", "window-title", "title", "command", "command-line",
    "working-directory", "cwd", "hostname", "username", "home-directory"
  ]
  return exact.indexOf(name) >= 0
}

function identifierKey(value) {
  var name = token(value)
  return ["device-id", "node-id", "output-id", "parent-id", "mapped-output", "legacy-id", "from", "to"].indexOf(name) >= 0
}

function safeString(value, key) {
  var result = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!result) return ""
  if (MAC.test(result) || EVENT_NODE.test(result) || PRIVATE_PATH.test(result) || PRIVATE_TOKEN.test(result)) return "<redacted>"
  // Internal IDs from legacy adapters may contain a slash and raw vendor or
  // transport material. Only the public opaque graph forms are retained.
  if (identifierKey(key) && !OPAQUE_ID.test(result)) return "<redacted>"
  if (token(key) === "id" && /^(?:input|keyboard):[^\s]*\//i.test(result)) return "<redacted>"
  if (result.length > MAX_STRING) result = result.slice(0, MAX_STRING).trim()
  return result
}

function sanitize(value, options, depth, key) {
  var settings = object(options)
  var level = Number(depth || 0)
  if (level > Number(settings.maxDepth || MAX_DEPTH)) return "<depth-limit>"
  if (key && sensitiveKey(key)) return settings.redact === false ? undefined : "<redacted>"
  if (value === null || value === undefined) return value
  if (typeof value === "string") return safeString(value, key)
  if (typeof value === "number") return isFinite(value) ? value : null
  if (typeof value === "boolean") return value
  if (Array.isArray(value)) {
    var list = []
    var limit = Math.max(0, Math.floor(Number(settings.maxItems || MAX_ITEMS)))
    for (var i = 0; i < value.length && i < limit; i++) {
      var item = sanitize(value[i], settings, level + 1, "")
      if (item !== undefined) list.push(item)
    }
    if (value.length > limit) list.push("<items-truncated>")
    return list
  }
  if (typeof value === "object") {
    var result = {}
    var keys = Object.keys(value)
    var keyLimit = Math.max(0, Math.floor(Number(settings.maxKeys || MAX_KEYS)))
    for (var k = 0; k < keys.length && k < keyLimit; k++) {
      var name = keys[k]
      var child = sanitize(value[name], settings, level + 1, name)
      if (child !== undefined) result[name] = child
    }
    if (keys.length > keyLimit) result._privacy = "keys-truncated"
    return result
  }
  return undefined
}

function boundary(value, options) {
  var result = sanitize(value, options, 0, "")
  if (!result || typeof result !== "object" || Array.isArray(result)) result = {}
  result.schemaVersion = SCHEMA_VERSION
  result.privacy = Object.assign({}, object(result.privacy), {
    rawHardwareIdentifiersEmitted: false,
    rawPathsEmitted: false,
    typedTextLogged: false,
    collectionsBounded: true
  })
  return result
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_DEPTH: MAX_DEPTH,
  MAX_ITEMS: MAX_ITEMS,
  MAX_KEYS: MAX_KEYS,
  MAX_STRING: MAX_STRING,
  sensitiveKey: sensitiveKey,
  sanitize: sanitize,
  boundary: boundary
}
if (typeof module !== "undefined") module.exports = api
