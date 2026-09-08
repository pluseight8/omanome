// Bounded, metadata-only matching for launch-to-slot requests.
//
// A request deliberately keeps no title or window-content data. Matching is
// driven by compositor identity (address/PID/app id) and an optional launch
// timestamp supplied by a foreign-toplevel or Hyprland event. The service
// calls resolve() when that event updates the client list; it never polls.

var MATCHER_SCHEMA_VERSION = 1
var DEFAULT_TIMEOUT_MS = 12000
var MAX_TIMEOUT_MS = 15000

function text(value) { return String(value === undefined || value === null ? "" : value).trim() }
function lower(value) { return text(value).toLowerCase() }
function number(value, fallback) { var result = Number(value); return isFinite(result) ? result : Number(fallback || 0) }
function integer(value, fallback) { var result = Math.floor(number(value, fallback)); return isFinite(result) ? result : Math.floor(Number(fallback || 0)) }
function clone(value) { return JSON.parse(JSON.stringify(value)) }

function appId(windowOrId) {
  if (typeof windowOrId === "string") return lower(windowOrId).replace(/\.desktop$/, "")
  var item = windowOrId && typeof windowOrId === "object" ? windowOrId : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  return lower(foreign.appId || foreign.app_id || foreign.class || foreign.className || foreign.initialClass || item.appId || item.class).replace(/\.desktop$/, "")
}

function address(window) {
  var item = window && typeof window === "object" ? window : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  return text(foreign.address || item.address)
}

function pid(window) {
  var item = window && typeof window === "object" ? window : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  var value = integer(foreign.pid !== undefined ? foreign.pid : item.pid, 0)
  return value > 0 ? value : 0
}

function timestamp(window) {
  var item = window && typeof window === "object" ? window : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  var value = foreign.launchTimestamp
  if (value === undefined) value = foreign.launch_timestamp
  if (value === undefined) value = foreign.createdAt
  if (value === undefined) value = foreign.created_at
  if (value === undefined) value = foreign.startTime
  if (value === undefined) value = item.launchTimestamp
  var result = number(value, 0)
  return result > 0 ? result : 0
}

function identity(window) {
  var id = appId(window)
  var valueAddress = address(window)
  var valuePid = pid(window)
  if (valueAddress) return "address:" + valueAddress
  if (valuePid > 0 && id) return "pid:" + valuePid + ":" + id
  if (valuePid > 0) return "pid:" + valuePid
  return id ? "app:" + id : ""
}

function metadata(window) {
  return {
    id: identity(window),
    appId: appId(window),
    address: address(window),
    pid: pid(window),
    launchTimestamp: timestamp(window),
    hasForeignToplevel: !!(window && window.wayland)
  }
}

function unique(values) {
  var seen = {}
  var result = []
  var list = Array.isArray(values) ? values : []
  for (var i = 0; i < list.length; i++) {
    var value = text(list[i])
    if (!value || seen[value]) continue
    seen[value] = true
    result.push(value)
  }
  return result
}

function snapshot(windows) {
  var list = Array.isArray(windows) ? windows : []
  var identities = []
  var addresses = []
  var pids = []
  var appIds = []
  for (var i = 0; i < list.length; i++) {
    var item = metadata(list[i])
    if (item.id) identities.push(item.id)
    if (item.address) addresses.push(item.address)
    if (item.pid > 0) pids.push(item.pid)
    if (item.appId) appIds.push(item.appId)
  }
  return {
    schemaVersion: MATCHER_SCHEMA_VERSION,
    identities: unique(identities),
    addresses: unique(addresses),
    pids: unique(pids.map(function(value) { return String(value) })),
    appIds: unique(appIds)
  }
}

function boundedTimeout(value) {
  var candidate = integer(value, DEFAULT_TIMEOUT_MS)
  return Math.max(500, Math.min(MAX_TIMEOUT_MS, candidate))
}

function begin(targetAppId, existingWindows, now, options) {
  var settings = options && typeof options === "object" ? options : {}
  var startedAt = Math.max(0, number(now, Date.now()))
  var timeoutMs = boundedTimeout(settings.timeoutMs)
  var target = appId(targetAppId)
  return {
    schemaVersion: MATCHER_SCHEMA_VERSION,
    appId: target,
    startedAt: startedAt,
    timeoutMs: timeoutMs,
    deadline: startedAt + timeoutMs,
    status: target ? "pending" : "blocked",
    reason: target ? "waiting-for-client-event" : "application-identity-required",
    existing: snapshot(existingWindows),
    expectedPid: Math.max(0, integer(settings.expectedPid, 0)),
    expectedWorkspace: settings.workspaceId === undefined ? null : integer(settings.workspaceId, 0),
    expectedMonitor: text(settings.monitorName || settings.monitor || ""),
    attempts: 0,
    matchedId: ""
  }
}

function contains(list, value) { return Array.isArray(list) && list.indexOf(value) >= 0 }

function isNew(item, existing) {
  if (!item.id) return false
  // App id alone is not a safe launch identity: two same-app windows can
  // legitimately share it, and a title must never fill that gap.
  if (!item.address && item.pid <= 0) return false
  if (contains(existing.identities, item.id)) return false
  if (item.address && contains(existing.addresses, item.address)) return false
  if (item.pid > 0 && contains(existing.pids, String(item.pid))) return false
  return true
}

function workspaceId(window) {
  var item = window && typeof window === "object" ? window : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  var workspace = foreign.workspace || item.workspace
  if (workspace && typeof workspace === "object") return integer(workspace.id, 0)
  return integer(foreign.workspaceId !== undefined ? foreign.workspaceId : item.workspaceId, 0)
}

function monitorName(window) {
  var item = window && typeof window === "object" ? window : {}
  var foreign = item.wayland && typeof item.wayland === "object" ? item.wayland : item
  return text(foreign.monitorName || foreign.monitor || foreign.output || item.monitorName || item.monitor)
}

function score(item, request, window) {
  var result = 0
  if (request.expectedPid > 0 && item.pid === request.expectedPid) result += 1000
  if (item.launchTimestamp > 0 && item.launchTimestamp >= request.startedAt) result += 100
  if (item.hasForeignToplevel) result += 20
  if (request.expectedWorkspace !== null && workspaceId(window) === request.expectedWorkspace) result += 10
  if (request.expectedMonitor && monitorName(window) === request.expectedMonitor) result += 10
  return result
}

function matchWindow(request, windows, now) {
  var source = request && typeof request === "object" ? request : {}
  var current = Math.max(0, number(now, Date.now()))
  if (source.status !== "pending") return { ok: false, status: source.status || "blocked", reason: source.reason || "not-pending", windowId: "" }
  if (current >= number(source.deadline, 0)) return { ok: false, status: "timeout", reason: "launch-timeout", windowId: "" }
  var list = Array.isArray(windows) ? windows : []
  var existing = source.existing || {}
  var candidates = []
  for (var i = 0; i < list.length; i++) {
    var item = metadata(list[i])
    if (item.appId !== text(source.appId).toLowerCase()) continue
    if (!isNew(item, existing)) continue
    candidates.push({ index: i, item: item, window: list[i], score: score(item, source, list[i]) })
  }
  candidates.sort(function(left, right) {
    if (right.score !== left.score) return right.score - left.score
    return left.index - right.index
  })
  if (candidates.length === 0) return { ok: false, status: "pending", reason: "client-not-found", windowId: "" }
  var selected = candidates[0]
  return { ok: true, status: "matched", reason: "new-client-matched", windowId: selected.item.id, index: selected.index, metadata: selected.item }
}

function resolve(request, windows, now) {
  var source = clone(request || {})
  source.attempts = integer(source.attempts, 0) + 1
  var result = matchWindow(source, windows, now)
  source.status = result.status
  source.reason = result.reason
  source.matchedId = result.windowId || ""
  return { request: source, result: result }
}

var api = {
  MATCHER_SCHEMA_VERSION: MATCHER_SCHEMA_VERSION,
  DEFAULT_TIMEOUT_MS: DEFAULT_TIMEOUT_MS,
  MAX_TIMEOUT_MS: MAX_TIMEOUT_MS,
  appId: appId,
  address: address,
  pid: pid,
  timestamp: timestamp,
  identity: identity,
  metadata: metadata,
  snapshot: snapshot,
  boundedTimeout: boundedTimeout,
  begin: begin,
  matchWindow: matchWindow,
  resolve: resolve
}
if (typeof module !== "undefined") module.exports = api
