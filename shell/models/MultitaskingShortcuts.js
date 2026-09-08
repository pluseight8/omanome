// Shortcut declarations are user-owned hints for Hyprland bindings.  Omanome
// never installs or replaces a global binding from this model.

var SCHEMA_VERSION = 1
var ACTIONS = ["snap-left", "snap-right", "next-layout", "toggle-float", "create-pair", "break-pair", "move-pair-workspace"]
var DEFAULTS = {
  "snap-left": "SUPER+ALT+LEFT",
  "snap-right": "SUPER+ALT+RIGHT",
  "next-layout": "SUPER+ALT+L",
  "toggle-float": "SUPER+ALT+F",
  "create-pair": "SUPER+ALT+P",
  "break-pair": "SUPER+ALT+SHIFT+P",
  "move-pair-workspace": "SUPER+ALT+W"
}
var MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"]
var MODIFIER_ALIASES = { META: "SUPER", WIN: "SUPER", CONTROL: "CTRL", CMD: "SUPER", OPTION: "ALT" }

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {} }
function text(value) { return String(value === undefined || value === null ? "" : value).trim() }

function keyName(value) {
  var key = text(value).toUpperCase()
  if (key === "ESC") key = "ESCAPE"
  if (key === "SPACEBAR") key = "SPACE"
  if (key === "ARROWLEFT") key = "LEFT"
  if (key === "ARROWRIGHT") key = "RIGHT"
  if (key === "ARROWUP") key = "UP"
  if (key === "ARROWDOWN") key = "DOWN"
  return key
}

function parse(value) {
  var parts = text(value).split("+").map(function(item) { return text(item) }).filter(Boolean)
  var modifiers = []
  var key = ""
  for (var i = 0; i < parts.length; i++) {
    var token = keyName(parts[i])
    token = MODIFIER_ALIASES[token] || token
    if (MODIFIERS.indexOf(token) >= 0 && key === "") {
      if (modifiers.indexOf(token) < 0) modifiers.push(token)
    } else if (!key) key = token
  }
  modifiers.sort()
  return { modifiers: modifiers, key: key }
}

function canonical(value) {
  var parsed = typeof value === "object" && value !== null ? value : parse(value)
  var modifiers = Array.isArray(parsed.modifiers) ? parsed.modifiers.map(function(item) { return MODIFIER_ALIASES[keyName(item)] || keyName(item) }).filter(function(item) { return MODIFIERS.indexOf(item) >= 0 }) : []
  modifiers = modifiers.filter(function(item, index) { return modifiers.indexOf(item) === index }).sort()
  var key = keyName(parsed.key)
  return modifiers.concat(key ? [key] : []).join("+")
}

function normalizeMap(source, includeDefaults) {
  var input = object(source)
  var result = {}
  for (var i = 0; i < ACTIONS.length; i++) {
    var action = ACTIONS[i]
    var value = input[action] !== undefined ? input[action] : (includeDefaults ? DEFAULTS[action] : "")
    result[action] = canonical(value)
  }
  return result
}

function externalCanonical(bind) {
  var source = object(bind)
  var modifiers = []
  if (Array.isArray(source.modifiers)) modifiers = source.modifiers.slice()
  else if (Array.isArray(source.mods)) modifiers = source.mods.slice()
  else if (source.mod !== undefined) modifiers = text(source.mod).split(/[+\s,]+/).filter(Boolean)
  else if (source.modmask !== undefined) {
    var mask = Number(source.modmask)
    var bits = [[1, "SHIFT"], [4, "CTRL"], [8, "ALT"], [64, "SUPER"]]
    for (var i = 0; i < bits.length; i++) if (isFinite(mask) && (mask & bits[i][0])) modifiers.push(bits[i][1])
  }
  return canonical({ modifiers: modifiers, key: source.key || source.trigger || source.keycode || "" })
}

function externalLabel(bind) {
  var source = object(bind)
  return text(source.dispatcher || source.description || source.arg || "Hyprland binding").slice(0, 96)
}

function report(multitasking, existing, external) {
  var configured = normalizeMap(multitasking, false)
  var baseline = object(existing)
  var occupied = {}
  var conflicts = []
  Object.keys(baseline).forEach(function(name) {
    var value = canonical(baseline[name])
    if (value) occupied[value] = "Omanome: " + name
  })
  var reverse = {}
  ACTIONS.forEach(function(action) {
    var binding = configured[action]
    if (!binding) return
    if (reverse[binding]) conflicts.push({ type: "duplicate", action: action, other: reverse[binding], binding: binding, source: "multitasking" })
    reverse[binding] = action
    if (occupied[binding]) conflicts.push({ type: "existing", action: action, binding: binding, source: occupied[binding] })
  })
  var externalKnown = Array.isArray(external)
  var externalBindings = []
  if (externalKnown) {
    for (var i = 0; i < external.length; i++) {
      var externalBinding = externalCanonical(external[i])
      if (!externalBinding) continue
      externalBindings.push({ binding: externalBinding, label: externalLabel(external[i]) })
      ACTIONS.forEach(function(action) {
        if (configured[action] && configured[action] === externalBinding)
          conflicts.push({ type: "external", action: action, binding: externalBinding, source: externalLabel(external[i]) })
      })
    }
  }
  return { schemaVersion: SCHEMA_VERSION, status: externalKnown ? "checked" : "not-checked", bindings: configured, conflicts: conflicts.slice(0, ACTIONS.length * 2), externalCount: externalBindings.length, externalBindings: externalBindings.slice(0, 64), reason: externalKnown ? (conflicts.length > 0 ? "conflicts-found" : "no-conflicts") : "external-bindings-not-checked" }
}

function emptyState() { return { schemaVersion: SCHEMA_VERSION, status: "not-checked", bindings: normalizeMap({}, true), conflicts: [], externalCount: 0, externalBindings: [], reason: "external-bindings-not-checked" } }

function summary(state) {
  var source = object(state)
  return { schemaVersion: SCHEMA_VERSION, status: text(source.status || "not-checked"), conflictCount: Array.isArray(source.conflicts) ? source.conflicts.length : 0, externalCount: Number(source.externalCount || 0), reason: text(source.reason || "external-bindings-not-checked"), bindings: normalizeMap(source.bindings || {}, false) }
}

var api = { SCHEMA_VERSION: SCHEMA_VERSION, ACTIONS: ACTIONS, DEFAULTS: DEFAULTS, parse: parse, canonical: canonical, normalizeMap: normalizeMap, externalCanonical: externalCanonical, report: report, emptyState: emptyState, summary: summary }
if (typeof module !== "undefined") module.exports = api
