function text(value) { return String(value === undefined || value === null ? "" : value).toLowerCase() }

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, Number(value)))
}

function clientIdentity(client) {
  var item = client || {}
  return [item.class, item.className, item.appId, item.app_id, item.title, item.initialClass, item.initialTitle]
    .filter(function(value) { return value !== undefined && value !== null && String(value) !== "" })
    .map(function(value) { return text(value) })
}

function matchesPattern(client, pattern) {
  var wanted = text(pattern).trim()
  if (!wanted) return false
  var escaped = wanted.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\*/g, ".*")
  var expression
  try { expression = new RegExp("^" + escaped + "$", "i") } catch (error) { return false }
  var values = clientIdentity(client)
  for (var i = 0; i < values.length; i++) if (expression.test(values[i])) return true
  return false
}

function isFullscreen(client) {
  var item = client || {}
  if (item.fullscreen === true || item.fullscreenClient === true) return true
  if (Number(item.fullscreen) > 0 || Number(item.fullscreenClient) > 0) return true
  return text(item.fullscreen) === "true" || text(item.fullscreenClient) === "true"
}

function shouldDisableWorkspaceSwipe(clients, config) {
  var settings = config || {}
  if (settings.disableOnFullscreen === false || text(settings.conflictPolicy || "disable-fullscreen") === "never") return false
  var list = Array.isArray(clients) ? clients : []
  var allow = Array.isArray(settings.fullscreenAllowList) ? settings.fullscreenAllowList : []
  var deny = Array.isArray(settings.fullscreenDenyList) ? settings.fullscreenDenyList : []
  for (var i = 0; i < list.length; i++) {
    if (!isFullscreen(list[i])) continue
    for (var d = 0; d < deny.length; d++) if (matchesPattern(list[i], deny[d])) return true
    if (allow.length === 0) return true
    var allowed = false
    for (var a = 0; a < allow.length; a++) if (matchesPattern(list[i], allow[a])) { allowed = true; break }
    if (!allowed) return true
  }
  return false
}

function targetSize(config, inputKind) {
  var settings = config || {}
  var kind = text(inputKind || "mouse")
  if (kind === "mouse" || kind === "touchpad") return 40
  if (kind === "stylus") return clamp(settings.touchTarget || 48, 48, 60)
  if (kind === "touch") return settings.largeUi === true ? 64 : clamp(settings.touchTarget || 48, 48, 56)
  return clamp(settings.touchTarget || 48, 48, 72)
}

function workspaceSwipeEnabled(config, clients) {
  var settings = config || {}
  return settings.enabled !== false && !shouldDisableWorkspaceSwipe(clients, settings)
}

var api = {
  clamp: clamp,
  clientIdentity: clientIdentity,
  matchesPattern: matchesPattern,
  isFullscreen: isFullscreen,
  shouldDisableWorkspaceSwipe: shouldDisableWorkspaceSwipe,
  targetSize: targetSize,
  workspaceSwipeEnabled: workspaceSwipeEnabled
}
if (typeof module !== "undefined") module.exports = api
