// Data-driven, diagnostics-only device quirks.
//
// A quirk is an explicit, versioned note about a hardware combination.  The
// model may report a match, but it never applies an input mapping or a
// privileged workaround.  Critical mapping notes stay visible in diagnostics
// and require a separate, user-confirmed policy outside this model.

var SCHEMA_VERSION = 1
var MAX_ENTRIES = 64
var MAX_APPLIED = 128
var MAX_TEXT = 512
var MAX_TOKENS = 16
var CATEGORIES = ["display", "touchscreen", "stylus", "tablet-pad", "keyboard", "mouse", "touchpad", "gamepad", "sensor", "dock", "battery", "audio"]
var FORM_FACTORS = ["unknown", "built-in", "external", "detachable", "dock", "drawing", "portable", "convertible"]
var CONFIDENCES = ["confirmed", "probable", "unknown"]

function string(value) {
  return String(value === undefined || value === null ? "" : value)
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function bool(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback === undefined ? false : fallback
  var name = string(value).toLowerCase()
  return value === true || value === 1 || name === "true" || name === "yes" || name === "1"
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function token(value) {
  return string(value).trim().replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase().replace(/[\s_]+/g, "-")
}

function safeToken(value, maximum) {
  var result = token(value)
  var limit = maximum || 64
  return result && result.length <= limit && /^[a-z0-9][a-z0-9.-]*$/.test(result) ? result : ""
}

function safeText(value, fallback) {
  var result = string(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!result || result.length > MAX_TEXT || /\/dev\/|\/sys\/|\/org\/freedesktop\/UPower\/|\bevent[0-9]+\b/i.test(result)) return fallback || ""
  if (/(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i.test(result)) return fallback || ""
  return result
}

function containsUnsafeText(value) {
  var text = string(value)
  return /\/dev\/|\/sys\/|\/org\/freedesktop\/UPower\/|\bevent[0-9]+\b/i.test(text) || /(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i.test(text)
}

function safeId(value) {
  var id = token(value)
  return id && /^[a-z0-9][a-z0-9._-]{0,63}$/.test(id) ? id : ""
}

function safeGraphId(value) {
  var id = string(value).trim()
  return /^(?:device:[a-z0-9-]+:[0-9a-f]{16}|display:[0-9a-f]{16})$/.test(id) ? id : ""
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function uniqueTokens(value, maximum) {
  var result = []
  var limit = maximum || MAX_TOKENS
  var values = Array.isArray(value) ? value : string(value).split(/[,\s]+/)
  for (var i = 0; i < values.length && result.length < limit; i++) {
    var name = safeToken(values[i], 64)
    if (name && result.indexOf(name) < 0) result.push(name)
  }
  return result
}

function capabilityMap(node) {
  var source = object(node)
  var raw = object(source.capabilities)
  var result = {}
  for (var key in raw) if (raw[key] === true || raw[key] === 1 || string(raw[key]).toLowerCase() === "true") result[token(key)] = true
  return result
}

function normalizedMatch(raw) {
  var source = object(raw)
  var result = {}
  var category = token(source.category || source.deviceCategory || source.device_category)
  if (category === "monitor" || category === "output") category = "display"
  if (CATEGORIES.indexOf(category) >= 0) result.category = category
  var transport = safeToken(source.transport || source.connection || source.protocol, 32)
  if (transport) result.transport = transport
  var formFactor = token(source.formFactorRole || source.form_factor_role || source.formFactor || source.form_factor)
  if (FORM_FACTORS.indexOf(formFactor) >= 0) result.formFactorRole = formFactor
  var driver = safeToken(source.driverFamily || source.driver_family || source.driver, 64)
  if (driver) result.driverFamily = driver
  var bus = safeToken(source.bus, 32)
  if (bus) result.bus = bus
  var kernel = safeToken(source.kernelFamily || source.kernel_family || source.kernel, 64)
  if (kernel) result.kernelFamily = kernel
  var all = uniqueTokens(source.capabilitiesAll || source.capabilities_all || source.allCapabilities || source.all_capabilities)
  var any = uniqueTokens(source.capabilitiesAny || source.capabilities_any || source.anyCapabilities || source.any_capabilities)
  if (all.length > 0) result.capabilitiesAll = all
  if (any.length > 0) result.capabilitiesAny = any
  var model = safeText(source.model || source.modelName || source.model_name, "")
  if (model) result.model = model
  var modelTokens = uniqueTokens(source.modelTokens || source.model_tokens, MAX_TOKENS)
  if (modelTokens.length > 0) result.modelTokens = modelTokens
  return result
}

function hasStructuralMatch(match) {
  var source = object(match)
  return !!(source.category || source.transport || source.formFactorRole || source.driverFamily || source.bus || source.kernelFamily || array(source.capabilitiesAll).length || array(source.capabilitiesAny).length)
}

function normalizeOverrides(value) {
  var source = object(value)
  var result = {}
  var count = 0
  var allowed = ["mappingMode", "preferredOutput", "oskPolicy", "orientation", "pressureCurve", "palmRejection", "powerPolicy"]
  for (var key in source) {
    if (count >= 12 || allowed.indexOf(token(key)) < 0) continue
    var valueText = safeText(source[key], "")
    if (!valueText) continue
    result[token(key)] = valueText
    count++
  }
  return result
}

function normalizeEntry(raw) {
  var source = object(raw)
  var id = safeId(source.id || source.key || source.name)
  if (!id) return null
  if (containsUnsafeText(source.knownIssue || source.known_issue) || containsUnsafeText(source.workaround || source.safeWorkaround || source.safe_workaround) || containsUnsafeText(source.documentation || source.source || source.url) || containsUnsafeText(source.testedVersion || source.tested_version)) return null
  var matchSource = Object.assign({}, object(source.match), source)
  var match = normalizedMatch(matchSource)
  if (!hasStructuralMatch(match)) return null
  return {
    schemaVersion: SCHEMA_VERSION,
    id: id,
    enabled: source.enabled !== false,
    match: match,
    knownIssue: safeText(source.knownIssue || source.known_issue, ""),
    workaround: safeText(source.workaround || source.safeWorkaround || source.safe_workaround, ""),
    documentation: safeText(source.documentation || source.source || source.url, ""),
    testedVersion: safeText(source.testedVersion || source.tested_version, ""),
    criticalMapping: bool(source.criticalMapping || source.critical_mapping, false),
    visible: true,
    overrides: normalizeOverrides(source.overrides)
  }
}

function normalizeDatabase(raw) {
  var source = Array.isArray(raw) ? { entries: raw } : object(raw)
  var result = {
    schemaVersion: SCHEMA_VERSION,
    enabled: source.enabled !== false,
    source: source.entries || source.quirks ? "config" : "none",
    entries: [],
    revision: Math.max(0, Math.floor(number(source.revision, 0)))
  }
  var rows = Array.isArray(source.entries) ? source.entries : Array.isArray(source.quirks) ? source.quirks : []
  var seen = {}
  for (var i = 0; i < rows.length && result.entries.length < MAX_ENTRIES; i++) {
    var entry = normalizeEntry(rows[i])
    if (!entry || seen[entry.id]) continue
    seen[entry.id] = true
    result.entries.push(entry)
  }
  if (!result.enabled) result.entries = []
  if (result.entries.length === 0) result.source = "none"
  return result
}

function nodeValue(node, names, context) {
  var source = object(node)
  var extra = object(context)
  for (var i = 0; i < names.length; i++) {
    var value = source[names[i]]
    if (value === undefined || value === null || value === "") value = extra[names[i]]
    if (value !== undefined && value !== null && value !== "") return value
  }
  return ""
}

function modelMatches(match, node) {
  var model = safeText(nodeValue(node, ["model", "modelName", "model_name"], {}), "").toLowerCase()
  if (match.model && model !== String(match.model).toLowerCase()) return false
  var tokens = uniqueTokens(nodeValue(node, ["modelTokens", "model_tokens"], {}))
  if (match.modelTokens && match.modelTokens.length > 0) {
    var haystack = (model + " " + tokens.join(" ")).toLowerCase()
    for (var i = 0; i < match.modelTokens.length; i++) if (haystack.indexOf(match.modelTokens[i].toLowerCase()) < 0) return false
  }
  return true
}

function matches(entry, node, context) {
  var item = object(entry)
  if (item.enabled === false) return false
  var match = object(item.match)
  var source = object(node)
  var extra = object(context)
  if (match.category && token(source.category) !== match.category) return false
  if (match.transport && token(nodeValue(source, ["transport", "connection", "protocol"], extra)) !== match.transport) return false
  if (match.formFactorRole && token(nodeValue(source, ["formFactorRole", "form_factor_role", "formFactor"], extra)) !== match.formFactorRole) return false
  if (match.driverFamily && token(nodeValue(source, ["driverFamily", "driver_family", "driver"], extra)) !== match.driverFamily) return false
  if (match.bus && token(nodeValue(source, ["bus"], extra)) !== match.bus) return false
  if (match.kernelFamily && token(nodeValue(source, ["kernelFamily", "kernel_family", "kernel"], extra)) !== match.kernelFamily) return false
  var caps = capabilityMap(source)
  for (var i = 0; i < array(match.capabilitiesAll).length; i++) if (!caps[match.capabilitiesAll[i]]) return false
  if (array(match.capabilitiesAny).length > 0) {
    var any = false
    for (var j = 0; j < match.capabilitiesAny.length; j++) if (caps[match.capabilitiesAny[j]]) { any = true; break }
    if (!any) return false
  }
  return modelMatches(match, source)
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    enabled: true,
    available: false,
    source: "none",
    matchedCount: 0,
    entries: 0,
    applied: [],
    automaticMappingApplied: false,
    criticalMappingBlocked: 0,
    revision: 0,
    reason: "no-quirks-configured"
  }
}

function evaluate(database, graph, context) {
  var db = normalizeDatabase(database)
  var source = object(graph)
  var nodes = array(source.nodes)
  var applied = []
  var critical = 0
  for (var i = 0; i < db.entries.length && applied.length < MAX_APPLIED; i++) {
    var entry = db.entries[i]
    for (var n = 0; n < nodes.length && applied.length < MAX_APPLIED; n++) {
      var node = object(nodes[n])
      if (!matches(entry, node, context)) continue
      var isCritical = entry.criticalMapping === true
      if (isCritical) critical++
      applied.push({
        id: entry.id,
        deviceId: safeGraphId(node.id),
        category: CATEGORIES.indexOf(token(node.category)) >= 0 ? token(node.category) : "unknown",
        knownIssue: entry.knownIssue,
        workaround: entry.workaround,
        documentation: entry.documentation,
        testedVersion: entry.testedVersion,
        criticalMapping: isCritical,
        visible: true,
        applied: false,
        reason: isCritical ? "critical-mapping-requires-confirmation" : "matched-diagnostics-only"
      })
    }
  }
  return {
    schemaVersion: SCHEMA_VERSION,
    enabled: db.enabled,
    available: db.entries.length > 0,
    source: db.source,
    matchedCount: applied.length,
    entries: db.entries.length,
    applied: applied,
    automaticMappingApplied: false,
    criticalMappingBlocked: critical,
    revision: db.revision,
    reason: applied.length > 0 ? "quirks-matched" : db.entries.length > 0 ? "no-quirk-match" : "no-quirks-configured"
  }
}

function apply(graph, database, context) {
  return { graph: graph, state: evaluate(database, graph, context) }
}

function summary(value) {
  var source = object(value)
  var rows = array(source.applied).slice(0, MAX_APPLIED).map(function(row) {
    var item = object(row)
    return {
      id: safeId(item.id),
      deviceId: safeGraphId(item.deviceId),
      category: CATEGORIES.indexOf(token(item.category)) >= 0 ? token(item.category) : "unknown",
      knownIssue: safeText(item.knownIssue, ""),
      workaround: safeText(item.workaround, ""),
      documentation: safeText(item.documentation, ""),
      testedVersion: safeText(item.testedVersion, ""),
      criticalMapping: item.criticalMapping === true,
      visible: true,
      applied: false,
      reason: item.criticalMapping === true ? "critical-mapping-requires-confirmation" : "matched-diagnostics-only"
    }
  }).filter(function(row) { return row.id !== "" })
  return {
    schemaVersion: SCHEMA_VERSION,
    enabled: source.enabled !== false,
    available: source.available === true,
    source: source.source === "config" ? "config" : "none",
    matchedCount: Math.min(MAX_APPLIED, Math.max(0, Math.floor(number(source.matchedCount, rows.length)))),
    entries: Math.min(MAX_ENTRIES, Math.max(0, Math.floor(number(source.entries, 0)))),
    applied: rows,
    automaticMappingApplied: false,
    criticalMappingBlocked: Math.min(MAX_APPLIED, Math.max(0, Math.floor(number(source.criticalMappingBlocked, 0)))),
    revision: Math.max(0, Math.floor(number(source.revision, 0))),
    reason: string(source.reason || "no-quirks-configured")
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_ENTRIES: MAX_ENTRIES,
  MAX_APPLIED: MAX_APPLIED,
  normalizeEntry: normalizeEntry,
  normalizeDatabase: normalizeDatabase,
  matches: matches,
  evaluate: evaluate,
  apply: apply,
  emptyState: emptyState,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
