function bool(value) {
  return value === true
}

function normalizeSignals(signals) {
  var source = signals && typeof signals === "object" ? signals : {}
  return {
    touchscreen: bool(source.touchscreen),
    stylus: bool(source.stylus),
    stylusProximity: bool(source.stylusProximity),
    physicalKeyboard: bool(source.physicalKeyboard),
    detachableKeyboard: bool(source.detachableKeyboard),
    bluetoothKeyboard: bool(source.bluetoothKeyboard),
    tabletSwitchAvailable: bool(source.tabletSwitchAvailable),
    tabletSwitchActive: bool(source.tabletSwitchActive),
    posture: String(source.posture || "").toLowerCase(),
    lidState: String(source.lidState || "").toLowerCase(),
    orientation: String(source.orientation || "landscape"),
    lastInput: String(source.lastInput || "keyboard")
  }
}

function normalizeConfig(config) {
  var source = config && typeof config === "object" ? config : {}
  var tablet = source.tabletMode && typeof source.tabletMode === "object" ? source.tabletMode : {}
  var posture = tablet.posture && typeof tablet.posture === "object" ? tablet.posture : {}
  return {
    enabled: tablet.enabled !== false,
    autoFromTouch: tablet.autoFromTouch !== false,
    autoFromStylus: tablet.autoFromStylus !== false,
    physicalKeyboardExit: tablet.physicalKeyboardExit !== false,
    postureAuto: posture.auto !== false,
    debounceMs: Math.max(80, Number(posture.debounceMs || 320)),
    minimumDwellMs: Math.max(0, Number(posture.minimumDwellMs || 900)),
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

  if (c.postureAuto && s.posture === "tablet" && s.touchscreen)
    return { mode: "tablet", reason: "tablet posture", signals: s }
  if (c.postureAuto && (s.posture === "tent" || s.posture === "stand") && s.touchscreen)
    return { mode: "hybrid", reason: s.posture + " posture", signals: s }
  if (c.postureAuto && s.posture === "laptop")
    return { mode: s.touchscreen ? "hybrid" : "desktop", reason: "laptop posture", signals: s }

  var touchRecent = s.lastInput === "touch"
  var stylusRecent = s.lastInput === "stylus" || s.stylusProximity
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

function transitionStrength(signals, config, decision) {
  var s = normalizeSignals(signals)
  var c = normalizeConfig(config)
  if (["desktop", "tablet", "hybrid"].indexOf(c.requested) >= 0) return "explicit"
  if (s.tabletSwitchAvailable || s.posture === "tablet" || s.posture === "laptop" || s.posture === "tent" || s.posture === "stand") return "strong"
  if (s.detachableKeyboard || s.bluetoothKeyboard) return "strong"
  if (decision && decision.reason === "hardware tablet switch") return "strong"
  return "weak"
}

// Apply hysteresis to the mode selected by decide(). Strong hardware/posture
// signals settle quickly; weak recent-input evidence still needs debounce and
// minimum dwell so one accidental touch cannot flip the whole shell.
function transition(signals, config, state, now) {
  var source = state && typeof state === "object" ? state : {}
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var decision = decide(signals, config)
  var wanted = decision.mode
  var current = String(source.current || "")
  if (!current) {
    return {
      changed: true,
      pending: false,
      delayMs: 0,
      decision: decision,
      state: { current: wanted, candidate: "", candidateSince: 0, lastChangedAt: timestamp, reason: decision.reason }
    }
  }
  if (wanted === current) {
    return {
      changed: false,
      pending: false,
      delayMs: 0,
      decision: decision,
      state: { current: current, candidate: "", candidateSince: 0, lastChangedAt: Number(source.lastChangedAt || timestamp), reason: decision.reason }
    }
  }
  var candidate = String(source.candidate || "")
  var candidateSince = Number(source.candidateSince || 0)
  if (candidate !== wanted || !candidateSince) {
    return {
      changed: false,
      pending: true,
      delayMs: normalizeConfig(config).debounceMs,
      decision: decision,
      state: { current: current, candidate: wanted, candidateSince: timestamp, lastChangedAt: Number(source.lastChangedAt || timestamp), reason: "hysteresis: " + decision.reason }
    }
  }
  var c = normalizeConfig(config)
  var strength = transitionStrength(signals, config, decision)
  var debounce = strength === "explicit" ? 0 : (strength === "strong" ? Math.min(c.debounceMs, 180) : c.debounceMs)
  var dwell = strength === "weak" ? c.minimumDwellMs : Math.min(c.minimumDwellMs, 300)
  var elapsedCandidate = Math.max(0, timestamp - candidateSince)
  var elapsedDwell = Math.max(0, timestamp - Number(source.lastChangedAt || 0))
  var remaining = Math.max(debounce - elapsedCandidate, dwell - elapsedDwell)
  if (remaining > 0) {
    return {
      changed: false,
      pending: true,
      delayMs: remaining,
      decision: decision,
      state: { current: current, candidate: wanted, candidateSince: candidateSince, lastChangedAt: Number(source.lastChangedAt || timestamp), reason: "hysteresis: " + decision.reason }
    }
  }
  return {
    changed: true,
    pending: false,
    delayMs: 0,
    decision: decision,
    state: { current: wanted, candidate: "", candidateSince: 0, lastChangedAt: timestamp, reason: decision.reason }
  }
}

function profile(mode, config, responsive) {
  var source = config && typeof config === "object" ? config : {}
  var tablet = source.tabletMode && typeof source.tabletMode === "object" ? source.tabletMode : {}
  var keyboard = source.keyboard && typeof source.keyboard === "object" ? source.keyboard : {}
  var dock = source.dock && typeof source.dock === "object" ? source.dock : {}
  var current = String(mode || "desktop")
  var portrait = responsive && String(responsive.orientation || "") === "portrait"
  var posture = String(responsive && responsive.posture || "").toLowerCase()
  var touchTarget = Number(tablet.touchTarget || 48)
  if (!isFinite(touchTarget)) touchTarget = 48
  var isTabletLike = current === "tablet" || current === "hybrid"
  var dockPreference = String(tablet.dockPreference || "adaptive")
  var dockPosition = String(dock.position || "bottom")
  if (dockPreference === "side" || (dockPreference === "adaptive" && portrait)) dockPosition = "left"
  if (dockPreference === "right") dockPosition = "right"
  if (dockPreference === "bottom") dockPosition = "bottom"
  return {
    mode: current,
    tabletLike: isTabletLike,
    touchTarget: isTabletLike ? Math.max(48, touchTarget) : Math.min(48, touchTarget),
    dockPosition: dockPosition,
    oskAutoShow: keyboard.autoShow !== false && isTabletLike && posture !== "laptop",
    autorotation: posture !== "laptop",
    windowControls: isTabletLike && String(tablet.windowControls || "touch") !== "hidden",
    gestures: isTabletLike && tablet.gestures !== false,
    quickSettingsDensity: isTabletLike ? "large" : "comfortable",
    launcherDensity: isTabletLike ? "comfortable" : "compact"
  }
}

var api = { normalizeSignals: normalizeSignals, decide: decide, transition: transition, profile: profile }
if (typeof module !== "undefined") module.exports = api
