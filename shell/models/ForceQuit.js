var POLICIES = ["ask", "graceful-only", "graceful-term", "graceful-term-kill"]

function object(value) { return value && typeof value === "object" ? value : {} }

function foreign(window) {
  var item = object(window)
  return item.wayland || item.foreign || item
}

function normalize(config) {
  var source = object(config)
  var policy = String(source.policy || "graceful-term-kill")
  if (POLICIES.indexOf(policy) < 0) policy = "graceful-term-kill"
  return {
    enabled: source.enabled !== false,
    policy: policy,
    gracefulTimeoutMs: Math.max(0, Math.min(10000, Number(source.gracefulTimeoutMs || 1500))),
    termTimeoutMs: Math.max(0, Math.min(10000, Number(source.termTimeoutMs || 1000))),
    protectSessionProcesses: source.protectSessionProcesses !== false,
    allowProtectedOverride: source.allowProtectedOverride === true,
    includeFlatpak: source.includeFlatpak !== false,
    includeContainers: source.includeContainers === true,
    cancelOnEscape: source.cancelOnEscape !== false,
    cancelOnRightClick: source.cancelOnRightClick !== false,
    cancelButton: source.cancelButton !== false,
    stylusSecondaryButton: source.stylusSecondaryButton !== false
  }
}

function pid(window) {
  var item = object(window)
  var ipc = object(item.lastIpcObject)
  var raw = item.pid !== undefined ? item.pid : (ipc.pid !== undefined ? ipc.pid : object(foreign(window)).pid)
  var value = Number(raw)
  return isFinite(value) && value > 0 ? Math.floor(value) : 0
}

function appId(window) {
  var item = foreign(window)
  return String(item.appId || item.app_id || window && window.appId || "unknown")
}

function title(window) {
  var item = foreign(window)
  return String(item.title || window && window.title || appId(window))
}

function workspace(window) {
  var item = object(window)
  var value = item.workspace || object(item.lastIpcObject).workspace
  return value && typeof value === "object" ? Number(value.id || 0) : Number(value || 0)
}

function protectedReason(window) {
  var value = appId(window).toLowerCase()
  if (value.indexOf("hyprland") >= 0) return "Hyprland"
  if (value.indexOf("omarchy-shell") >= 0 || value.indexOf("omarchy_shell") >= 0) return "Omarchy shell"
  if (value.indexOf("omanome") >= 0) return "Omanome"
  if (value.indexOf("systemd") >= 0) return "systemd user session"
  if (value.indexOf("quickshell") >= 0) return "Quickshell host"
  return ""
}

function target(window) {
  var reason = protectedReason(window)
  return {
    window: window,
    pid: pid(window),
    appId: appId(window),
    title: title(window),
    workspace: workspace(window),
    protectedByApp: reason !== "",
    protectedReason: reason,
    selectable: reason === "" && (pid(window) > 0 || typeof foreign(window).close === "function")
  }
}

function candidates(windows) {
  var list = Array.isArray(windows) ? windows : []
  return list.filter(function(item) { return item && foreign(item).minimized !== true }).map(target)
}

function requiresTerm(policy) { return policy === "graceful-term" || policy === "graceful-term-kill" }
function requiresKill(policy) { return policy === "graceful-term-kill" }

var api = { POLICIES: POLICIES, normalize: normalize, foreign: foreign, pid: pid, appId: appId, title: title, workspace: workspace, protectedReason: protectedReason, target: target, candidates: candidates, requiresTerm: requiresTerm, requiresKill: requiresKill }
if (typeof module !== "undefined") module.exports = api
