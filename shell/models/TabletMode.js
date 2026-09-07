function bool(value) {
  return value === true
}

function normalizeSignals(signals) {
  var source = signals && typeof signals === "object" ? signals : {}
  return {
    touchscreen: bool(source.touchscreen),
    stylus: bool(source.stylus),
    physicalKeyboard: bool(source.physicalKeyboard),
    tabletSwitchAvailable: bool(source.tabletSwitchAvailable),
    tabletSwitchActive: bool(source.tabletSwitchActive),
    orientation: String(source.orientation || "landscape"),
    lastInput: String(source.lastInput || "keyboard")
  }
}

function normalizeConfig(config) {
  var source = config && typeof config === "object" ? config : {}
  var tablet = source.tabletMode && typeof source.tabletMode === "object" ? source.tabletMode : {}
  return {
    enabled: tablet.enabled !== false,
    autoFromTouch: tablet.autoFromTouch !== false,
    autoFromStylus: tablet.autoFromStylus !== false,
    physicalKeyboardExit: tablet.physicalKeyboardExit !== false,
    requested: String(source.mode || "automatic")
  }
}

// Auto mode intentionally combines device availability, recent input, a
// hardware mode switch and orientation. It never invents a tablet when no
// touch-capable device exists.
function decide(signals, config) {
  var s = normalizeSignals(signals)
  var c = normalizeConfig(config)
  if (!c.enabled) return { mode: "desktop", reason: "tablet mode disabled", signals: s }
  if (["desktop", "tablet", "hybrid"].indexOf(c.requested) >= 0)
    return { mode: c.requested, reason: "explicit mode", signals: s }
  if (s.tabletSwitchAvailable && s.tabletSwitchActive && s.touchscreen)
    return { mode: "tablet", reason: "hardware tablet switch", signals: s }

  var touchRecent = s.lastInput === "touch"
  var stylusRecent = s.lastInput === "stylus"
  var portrait = s.orientation === "portrait"
  if (touchRecent && c.autoFromTouch)
    return { mode: "tablet", reason: "recent touchscreen input", signals: s }
  if (stylusRecent && c.autoFromStylus && s.stylus)
    return { mode: "tablet", reason: "recent stylus input", signals: s }
  if (s.touchscreen && !s.physicalKeyboard)
    return { mode: "tablet", reason: "touchscreen without physical keyboard", signals: s }
  if (s.touchscreen && portrait && !s.physicalKeyboard)
    return { mode: "tablet", reason: "portrait touchscreen form factor", signals: s }
  if (s.touchscreen) {
    if (c.physicalKeyboardExit && (s.lastInput === "keyboard" || s.lastInput === "mouse" || s.lastInput === "touchpad"))
      return { mode: "hybrid", reason: "physical keyboard or pointer activity", signals: s }
    return { mode: "hybrid", reason: "touchscreen with desktop input", signals: s }
  }
  return { mode: "desktop", reason: "no touchscreen signal", signals: s }
}

function profile(mode, config, responsive) {
  var source = config && typeof config === "object" ? config : {}
  var tablet = source.tabletMode && typeof source.tabletMode === "object" ? source.tabletMode : {}
  var keyboard = source.keyboard && typeof source.keyboard === "object" ? source.keyboard : {}
  var dock = source.dock && typeof source.dock === "object" ? source.dock : {}
  var current = String(mode || "desktop")
  var portrait = responsive && String(responsive.orientation || "") === "portrait"
  var touchTarget = Number(tablet.touchTarget || 48)
  if (!isFinite(touchTarget)) touchTarget = 48
  var isTabletLike = current === "tablet" || current === "hybrid"
  var dockPreference = String(tablet.dockPreference || "adaptive")
  var dockPosition = String(dock.position || "bottom")
  if (dockPreference === "side" || (dockPreference === "adaptive" && portrait)) dockPosition = "left"
  if (dockPreference === "bottom") dockPosition = "bottom"
  return {
    mode: current,
    tabletLike: isTabletLike,
    touchTarget: isTabletLike ? Math.max(48, touchTarget) : Math.min(48, touchTarget),
    dockPosition: dockPosition,
    oskAutoShow: keyboard.autoShow !== false && isTabletLike,
    windowControls: isTabletLike && String(tablet.windowControls || "touch") !== "hidden",
    gestures: isTabletLike && tablet.gestures !== false,
    quickSettingsDensity: isTabletLike ? "large" : "comfortable",
    launcherDensity: isTabletLike ? "comfortable" : "compact"
  }
}

var api = { normalizeSignals: normalizeSignals, decide: decide, profile: profile }
if (typeof module !== "undefined") module.exports = api
