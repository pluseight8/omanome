function object(value) { return value && typeof value === "object" && !Array.isArray(value) ? value : {} }

function matchesPattern(value, pattern) {
  var source = String(pattern || "")
  if (!source) return true
  var text = String(value || "")
  var escaped = source.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\*/g, ".*")
  try { return new RegExp("^" + escaped + "$", "i").test(text) } catch (error) { return false }
}

function matchesRegex(value, pattern) {
  var source = String(pattern || "")
  if (!source) return true
  try { return new RegExp(source, "i").test(String(value || "")) } catch (error) { return false }
}

function matches(rule, window, context) {
  var item = object(window)
  var state = object(context)
  if (!matchesPattern(item.appId || item.app_id || item.desktopId, rule.appId)) return false
  if (!matchesPattern(item.class || item.initialClass || item.windowClass, rule.windowClass)) return false
  if (!matchesRegex(item.title, rule.titleRegex)) return false
  if (rule.fullscreen !== undefined && Boolean(item.fullscreen) !== Boolean(rule.fullscreen)) return false
  if (rule.floating !== undefined && Boolean(item.floating) !== Boolean(rule.floating)) return false
  if (rule.workspace !== undefined && Number(item.workspace && item.workspace.id !== undefined ? item.workspace.id : item.workspace) !== Number(rule.workspace)) return false
  if (!matchesPattern(item.monitorName || item.monitor, rule.monitor)) return false
  if (rule.inputKind && String(rule.inputKind) !== String(state.inputKind || "")) return false
  return true
}

function normalizeRule(rule) {
  var source = object(rule)
  return {
    id: String(source.id || "rule"),
    enabled: source.enabled !== false,
    appId: String(source.appId || ""),
    windowClass: String(source.windowClass || ""),
    titleRegex: String(source.titleRegex || ""),
    fullscreen: source.fullscreen === undefined ? undefined : Boolean(source.fullscreen),
    floating: source.floating === undefined ? undefined : Boolean(source.floating),
    workspace: source.workspace === undefined || source.workspace === "" ? undefined : Number(source.workspace),
    monitor: String(source.monitor || ""),
    inputKind: String(source.inputKind || ""),
    disableBlur: source.disableBlur === true,
    disableWobbly: source.disableWobbly === true,
    disableGestures: source.disableGestures === true,
    disableClipboardCapture: source.disableClipboardCapture === true,
    disableOskAutoshow: source.disableOskAutoshow === true,
    desktopUi: source.desktopUi === true,
    tabletUi: source.tabletUi === true
  }
}

function decision(rules, window, context) {
  var result = { disableBlur: false, disableWobbly: false, disableGestures: false, disableClipboardCapture: false, disableOskAutoshow: false, desktopUi: false, tabletUi: false, matched: [] }
  var list = Array.isArray(rules) ? rules : []
  for (var i = 0; i < list.length; i++) {
    var rule = normalizeRule(list[i])
    if (rule.enabled === false || !matches(rule, window, context)) continue
    result.matched.push(rule.id)
    result.disableBlur = result.disableBlur || rule.disableBlur
    result.disableWobbly = result.disableWobbly || rule.disableWobbly
    result.disableGestures = result.disableGestures || rule.disableGestures
    result.disableClipboardCapture = result.disableClipboardCapture || rule.disableClipboardCapture
    result.disableOskAutoshow = result.disableOskAutoshow || rule.disableOskAutoshow
    result.desktopUi = result.desktopUi || rule.desktopUi
    result.tabletUi = result.tabletUi || rule.tabletUi
  }
  return result
}

var api = { matchesPattern: matchesPattern, matchesRegex: matchesRegex, matches: matches, normalizeRule: normalizeRule, decision: decision }
if (typeof module !== "undefined") module.exports = api
