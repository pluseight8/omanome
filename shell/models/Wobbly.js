function object(value) { return value && typeof value === "object" ? value : {} }

function normalize(config) {
  var source = object(config)
  return {
    enabled: source.enabled === true,
    profile: String(source.profile || "subtle"),
    excludeFullscreen: source.excludeFullscreen !== false,
    excludeGames: source.excludeGames !== false,
    excludeSteam: source.excludeSteam !== false,
    excludeVr: source.excludeVr !== false,
    excludeDrawingApps: source.excludeDrawingApps !== false,
    excludeMaximized: source.excludeMaximized !== false,
    excludedApps: Array.isArray(source.excludedApps) ? source.excludedApps.map(String) : []
  }
}

function excluded(config, window) {
  var options = normalize(config)
  var item = object(window)
  var appId = String(item.appId || item.class || item.initialClass || "").toLowerCase()
  if (options.excludeFullscreen && (item.fullscreen === true || Number(item.fullscreen) > 0)) return "fullscreen"
  if (options.excludeMaximized && item.maximized === true) return "maximized"
  if (options.excludeSteam && (appId.indexOf("steam") >= 0 || appId.indexOf("gamescope") >= 0)) return "steam/game"
  if (options.excludeVr && (appId.indexOf("vr") >= 0 || appId.indexOf("openxr") >= 0)) return "vr"
  if (options.excludeGames && (appId.indexOf("game") >= 0 || appId.indexOf("wine") >= 0)) return "game"
  if (options.excludeDrawingApps && (appId.indexOf("krita") >= 0 || appId.indexOf("inkscape") >= 0 || appId.indexOf("gimp") >= 0)) return "drawing app"
  for (var i = 0; i < options.excludedApps.length; i++) if (appId === options.excludedApps[i].toLowerCase()) return "configured app"
  return ""
}

function state(config, capability, window) {
  var options = normalize(config)
  var reason = excluded(config, window)
  var available = object(capability).wobblyWindows === true
  return {
    configured: options.enabled,
    available: available,
    enabled: options.enabled && available && !reason,
    reason: !options.enabled ? "disabled in configuration" : (!available ? "no native compositor renderer loaded" : (reason || "native compositor renderer"))
  }
}

var api = { normalize: normalize, excluded: excluded, state: state }
if (typeof module !== "undefined") module.exports = api
