function defaults() {
  return {
    schemaVersion: 1,
    general: { mode: "automatic", profile: "Desktop", language: "system", reduceMotion: false, largeUi: false },
    appearance: { theme: "follow-omarchy", accent: "follow-omarchy", radius: 18, opacity: 0.96 },
    tabletMode: { enabled: true, touchTarget: 48, autoFromTouch: true, autoFromStylus: true, physicalKeyboardExit: true },
    touch: { enabled: true, edgeWidth: 36, threshold: 96, velocity: 0.35, inertia: true, invert: false, threeFingerAction: "workspace", fourFingerAction: "overview" },
    stylus: { enabled: true, pressureCurve: "linear", pressureMin: 0.0, pressureMax: 1.0, palmRejection: "automatic", palmBackend: "native-first", hoverCursor: true, showOskOnTextField: "ask", annotation: true, buttonMap: { primary: "right-click", secondary: "middle-click", tertiary: "annotation", eraser: "eraser" } },
    windowControls: { enabled: true, show: "tablet", minTarget: 48, style: "gnome", autoHide: true, autoHideDelay: 1800, position: "top-right", opacity: 0.94 },
    quickSettings: { wifi: true, bluetooth: true, airplane: true, volume: true, microphone: true, brightness: true, nightLight: true, powerProfile: true, theme: true, dnd: true, rotation: true, keyboard: true, stylus: true, screenshot: true, recording: true, lock: true, power: true },
    dock: { enabled: true, position: "bottom", mode: "floating", iconSize: 48, minIconSize: 40, maxIconSize: 64, dynamicSizing: true, autohide: true, autohideMode: "intelligent", revealByPointer: true, revealByTouch: true, edgePressure: 12, revealDelay: 120, hideDelay: 650, dodgeMode: "active-window", fullscreenHide: true, margin: 18, padding: 10, spacing: 8, radius: 22, monitor: "active", workspaceIsolation: false, monitorIsolation: false, backgroundOpacity: 0.82, blur: true, shadow: true, border: true, borderOpacity: 0.34, indicatorStyle: "dot", animation: "slide", clickAction: "activate-or-launch", middleClickAction: "new-window", scrollAction: "workspace" },
    overview: { enabled: true, style: "gnome", animationDuration: 180, blur: true, showAllWorkspaces: true, showDock: true, workspaceMode: "dynamic", fixedWorkspaceCount: 5, workspaceOrientation: "horizontal", search: true },
    launcher: { enabled: true, categories: true, favorites: [], favoritesFirst: true, folders: [], showRecent: true, recentApplications: [], dragReorder: true, contextMenu: true, gridColumns: 6 },
    keyboard: { enabled: true, layout: "auto", mode: "standard", showNumberRow: true, showModifierRow: true, showNavigationRow: true, showFunctionRow: false, capsLock: true, symbols: true, suggestions: true, autocorrect: false, learning: false, haptic: true, sound: false, autoShow: true, height: 300, toolbar: true, toolbarOverflow: true, keyPopup: true, keyPopupScale: 1.25, keyPopupDuration: 180, longPress: true, longPressDelay: 360, repeatDelay: 420, repeatRate: 55, spaceCursor: true, swipeLayerSwitch: true, floating: { x: 0.5, y: 0.72, width: 0.82, snap: true }, split: { gap: 24, blockWidth: 0.43, vertical: 0.72, thumbReach: 0.62, symmetric: true }, oneHanded: { width: 0.72, offset: 0.04, scale: 0.92 }, emojiCategory: "recent", emojiRecent: [], suggestionLocale: "auto" },
    clipboard: { enabled: true, historyLimit: 100, retentionDays: 30, persist: true, persistPinnedOnly: false, clearOnLogout: false, excludedApps: [], privateMode: false },
    notifications: { enabled: true, groupByApp: true, history: true, doNotDisturb: false },
    altTab: { style: "coverflow", groupByApp: true, scope: "current-workspace", perspective: 0.8, animationDuration: 160 },
    blur: { enabled: true, dock: true, overview: true, launcher: true, quickSettings: true, notificationCenter: true, clipboard: true, osk: true, settings: true, radius: 18, brightness: 0.85, saturation: 1.1, noise: 0.02 },
    effects: { wobblyWindows: false, desktopCube: false, disableOnBattery: true, disableOnFullscreen: true, performanceMode: "balanced" },
    rotation: { enabled: true, lock: false, orientation: "auto", sensor: "auto", transformTouch: true, transformStylus: true },
    privacy: { clipboardPrivate: false, neverLogClipboard: true, telemetry: false, updateChecks: true },
    shortcuts: { overview: "SUPER", launcher: "SUPER+SPACE", quickSettings: "SUPER+Q", clipboard: "SUPER+V", keyboard: "SUPER+K", forceQuit: "SUPER+ESC" },
    updates: { channel: "stable", automaticInstall: false, notify: true, rollbackRetention: 2 }
  }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function merge(base, overlay) {
  var result = clone(base)
  if (!isObject(overlay)) return result
  Object.keys(overlay).forEach(function(key) {
    if (isObject(result[key]) && isObject(overlay[key])) result[key] = merge(result[key], overlay[key])
    else result[key] = overlay[key]
  })
  return result
}

function migrate(raw) {
  if (!isObject(raw)) return defaults()
  var source = clone(raw)
  var version = Number(source.schemaVersion || 1)
  if (version > 1) return defaults()

  // Version 0 used the early prototype names. Keep this migration explicit so
  // a future schema can be added without silently changing user intent.
  if (source.tablet && !source.tabletMode) source.tabletMode = source.tablet
  if (source.osk && !source.keyboard) source.keyboard = source.osk
  if (source.schemaVersion === undefined) source.schemaVersion = 1
  source.schemaVersion = 1
  return merge(defaults(), source)
}

function load(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    return migrate(parsed)
  } catch (error) {
    return defaults()
  }
}

function get(config, path, fallback) {
  var parts = String(path || "").split(".")
  var current = config
  for (var i = 0; i < parts.length; i++) {
    if (!current || current[parts[i]] === undefined) return fallback
    current = current[parts[i]]
  }
  return current
}

function set(config, path, value) {
  var result = clone(config || defaults())
  var parts = String(path || "").split(".")
  var current = result
  for (var i = 0; i < parts.length - 1; i++) {
    if (!isObject(current[parts[i]])) current[parts[i]] = {}
    current = current[parts[i]]
  }
  current[parts[parts.length - 1]] = value
  result.schemaVersion = 1
  return result
}

function isValid(config) {
  return isObject(config) && Number(config.schemaVersion) === 1
}

var api = { defaults: defaults, migrate: migrate, load: load, get: get, set: set, isValid: isValid }
if (typeof module !== "undefined") module.exports = api
