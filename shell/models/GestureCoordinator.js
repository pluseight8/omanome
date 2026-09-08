// Pure, event-driven gesture arbitration for Omanome multitasking.
//
// This module only owns gesture intent and preview state. It never talks to
// Hyprland, starts a process, samples a pointer, or stores window metadata.
// The service may execute the returned action once, after end().

var SCHEMA_VERSION = 1
var MAX_FINGERS = 4
var MAX_PATTERNS = 32
var MAX_ACTIONS = 8
var ACTIVE_PHASES = ["armed", "tracking"]
var OWNERS = ["edge-swipe", "workspace-swipe", "overview-swipe", "dock-reveal", "back", "quick-settings", "notifications"]
var ACTIONS = ["dock", "overview", "quick-settings", "notifications", "back", "workspace-next", "workspace-previous", "disabled"]

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function finite(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, finite(value, minimum)))
}

function text(value) { return String(value === undefined || value === null ? "" : value).toLowerCase().trim() }

function bool(value) { return value === true }

function boundedPatterns(values) {
  var list = Array.isArray(values) ? values : []
  var result = []
  for (var i = 0; i < list.length && result.length < MAX_PATTERNS; i++) {
    var value = String(list[i] || "").trim()
    if (value && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function matchesPattern(value, pattern) {
  var wanted = String(pattern || "").trim()
  if (!wanted) return false
  var escaped = wanted.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\*/g, ".*")
  try { return new RegExp("^" + escaped + "$", "i").test(String(value || "")) } catch (error) { return false }
}

function matchesAny(values, patterns) {
  var list = Array.isArray(values) ? values : []
  var rules = boundedPatterns(patterns)
  for (var i = 0; i < list.length; i++) {
    for (var j = 0; j < rules.length; j++) if (matchesPattern(list[i], rules[j])) return true
  }
  return false
}

function normalizeInputKind(value) {
  var kind = text(value || "touch")
  if (kind === "touchscreen" || kind === "finger" || kind === "touch") return "touch"
  if (kind === "pen" || kind === "stylus") return "stylus"
  if (kind === "trackpad" || kind === "touch-pad" || kind === "touchpad") return "touchpad"
  if (kind === "pointer" || kind === "mouse") return "mouse"
  return "keyboard"
}

function normalizeEdge(value) {
  var edge = text(value)
  return ["top", "bottom", "left", "right"].indexOf(edge) >= 0 ? edge : ""
}

function normalizeOwner(value) {
  var owner = text(value)
  return OWNERS.indexOf(owner) >= 0 ? owner : ""
}

function normalizeAction(value, fallback) {
  var action = text(value).replace(/_/g, "-")
  if (action === "quicksettings" || action === "quick-settings") action = "quick-settings"
  if (action === "notification" || action === "notifications") action = "notifications"
  if (action === "workspace" || action === "next") action = "workspace-next"
  if (action === "previous" || action === "prev") action = "workspace-previous"
  if (ACTIONS.indexOf(action) >= 0) return action
  return fallback || "disabled"
}

function normalizePolicy(value, fallback) {
  var policy = text(value).replace(/_/g, "-")
  if (["disable", "disabled", "suppress", "suppress-in-fullscreen", "disable-fullscreen"].indexOf(policy) >= 0) return "disable"
  if (["system-edges-only", "system-edge-only", "system"].indexOf(policy) >= 0) return "system-edges-only"
  if (["always", "allow", "never"].indexOf(policy) >= 0) return "always"
  return fallback || "disable"
}

function profile(raw, exists, defaults) {
  var source = object(raw)
  var base = defaults || {}
  var threshold = clamp(finite(source.thresholdPx !== undefined ? source.thresholdPx : source.threshold, base.thresholdPx || 96), 20, 600)
  var movement = clamp(finite(source.movementThresholdPx !== undefined ? source.movementThresholdPx : source.movementThreshold, base.movementThresholdPx || 18), 4, 96)
  return {
    enabled: exists ? source.enabled !== false : base.enabled !== false,
    edgeSwipe: source.edgeSwipe !== false && base.edgeSwipe !== false,
    workspaceSwipe: source.workspaceSwipe !== false && base.workspaceSwipe !== false,
    overviewSwipe: source.overviewSwipe !== false && base.overviewSwipe !== false,
    dockReveal: source.dockReveal !== false && base.dockReveal !== false,
    quickSettings: source.quickSettings !== false && base.quickSettings !== false,
    back: source.back !== false && base.back !== false,
    allowStylus: source.allowStylus === true,
    threeFingerAction: normalizeAction(source.threeFingerAction || base.threeFingerAction, "workspace-next"),
    fourFingerAction: normalizeAction(source.fourFingerAction || base.fourFingerAction, "workspace-next"),
    movementThresholdPx: movement,
    thresholdPx: Math.max(movement, threshold),
    velocityThreshold: clamp(finite(source.velocityThreshold !== undefined ? source.velocityThreshold : source.velocity, base.velocityThreshold || 0.35), 0.05, 3),
    longDistancePx: clamp(finite(source.longDistancePx !== undefined ? source.longDistancePx : source.longDistance, base.longDistancePx || threshold * 1.5), threshold, 900),
    inertia: source.inertia !== undefined ? source.inertia !== false : base.inertia !== false
  }
}

function normalizeConfig(config) {
  var source = object(config)
  var legacy = source.touchscreen === undefined ? source : object(source.touchscreen)
  var padExists = source.touchpad !== undefined
  var bottom = object(source.bottomEdge)
  var top = object(source.topEdge)
  var side = object(source.sideEdge)
  var touchscreenDefaults = {
    enabled: source.enabled !== false,
    edgeSwipe: true,
    workspaceSwipe: source.workspaceSwipe !== false,
    overviewSwipe: source.overviewSwipe !== false,
    dockReveal: source.dockReveal !== false,
    quickSettings: source.quickSettings !== false,
    back: source.back !== false,
    threeFingerAction: source.threeFingerAction || "workspace-next",
    fourFingerAction: source.fourFingerAction || "workspace-next",
    thresholdPx: source.thresholdPx || source.threshold || 96,
    movementThresholdPx: source.movementThresholdPx || source.movementThreshold || 18,
    velocityThreshold: source.velocityThreshold || source.velocity || 0.35,
    inertia: source.inertia !== false
  }
  var touchpadDefaults = {
    enabled: false,
    edgeSwipe: false,
    workspaceSwipe: false,
    overviewSwipe: false,
    dockReveal: false,
    quickSettings: false,
    back: false,
    threeFingerAction: "workspace-next",
    fourFingerAction: "workspace-next",
    thresholdPx: 96,
    movementThresholdPx: 18,
    velocityThreshold: 0.45,
    inertia: false
  }
  var touchscreen = profile(legacy, source.touchscreen !== undefined, touchscreenDefaults)
  var touchpad = profile(source.touchpad, padExists, touchpadDefaults)
  if (source.touchscreenOnly === true && !padExists) touchpad.enabled = false
  return {
    schemaVersion: SCHEMA_VERSION,
    enabled: source.enabled !== false,
    edgeLock: source.edgeLock !== false,
    touchLock: source.touchLock === true || source.locked === true,
    presentationMode: source.presentationMode === true,
    fullscreenPolicy: normalizePolicy(source.fullscreenPolicy || source.conflictPolicy, "disable"),
    drawingPolicy: text(source.drawingPolicy || "suppress") === "allow" ? "allow" : "suppress",
    gamePolicy: text(source.gamePolicy || "suppress") === "allow" ? "allow" : "suppress",
    drawingApps: boundedPatterns(source.drawingApps),
    gameApps: boundedPatterns(source.gameApps),
    bottomEdge: {
      short: normalizeAction(bottom.short || source.bottomShort, "dock"),
      long: normalizeAction(bottom.long || source.bottomLong, "overview"),
      direct: normalizeAction(bottom.direct || source.bottomDirect, "disabled")
    },
    topEdge: { action: normalizeAction(top.action || source.topAction, "quick-settings") },
    sideEdge: {
      left: normalizeAction(side.left || source.leftAction, "back"),
      right: normalizeAction(side.right || source.rightAction, "back")
    },
    backShortcut: String(source.backShortcut || "").trim(),
    touchscreen: touchscreen,
    touchpad: touchpad
  }
}

function windowValues(source) {
  var item = object(source)
  var nested = object(item.window || item.activeWindow)
  return [
    item.appId, item.app_id, item.class, item.className, item.initialClass, item.windowClass,
    nested.appId, nested.app_id, nested.class, nested.className, nested.initialClass, nested.windowClass
  ].filter(function(value) { return value !== undefined && value !== null && String(value) !== "" })
}

function normalizeContext(context, config) {
  var source = object(context)
  var item = object(source.window || source.activeWindow)
  var values = windowValues(source)
  if (values.length === 0) values = windowValues(item)
  var fullscreen = source.fullscreen === true || source.fullscreenClient === true || Number(source.fullscreen) > 0 || Number(item.fullscreen) > 0
  var drawing = source.drawing === true || source.drawingApp === true || source.appRuleDrawing === true || matchesAny(values, config && config.drawingApps)
  var game = source.game === true || source.gameMode === true || source.appRuleGame === true || matchesAny(values, config && config.gameApps)
  return {
    fullscreen: fullscreen,
    game: game,
    drawing: drawing,
    osk: source.osk === true || source.oskOpen === true || source.textInputFocus === true,
    overviewOpen: source.overviewOpen === true || source.overview === true,
    floatingDrag: source.floatingDrag === true || source.windowDrag === true,
    stylus: source.stylus === true || normalizeInputKind(source.inputKind) === "stylus",
    appRuleDisabled: source.appRuleDisabled === true || source.disableGestures === true,
    touchLocked: source.touchLocked === true,
    presentationMode: source.presentationMode === true,
    systemEdge: source.systemEdge === true,
    backAvailable: source.backAvailable === true,
    backShortcut: String(source.backShortcut || "").trim(),
    reservedOwner: normalizeOwner(source.reservedOwner || source.activeOwner)
  }
}

function profileFor(config, inputKind) {
  var kind = normalizeInputKind(inputKind)
  if (kind === "touchpad") return config.touchpad
  if (kind === "touch" || kind === "stylus") return config.touchscreen
  return null
}

function featureEnabled(owner, profileValue) {
  if (!profileValue) return false
  if (owner === "edge-swipe") return profileValue.edgeSwipe
  if (owner === "workspace-swipe") return profileValue.workspaceSwipe
  if (owner === "overview-swipe") return profileValue.overviewSwipe
  if (owner === "dock-reveal") return profileValue.dockReveal
  if (owner === "back") return profileValue.back
  if (owner === "quick-settings" || owner === "notifications") return profileValue.quickSettings
  return false
}

function suppressed(owner, inputKind, config, contextValue) {
  var profileValue = profileFor(config, inputKind)
  if (!profileValue || profileValue.enabled === false) return "input-profile-disabled"
  if (normalizeInputKind(inputKind) === "stylus" && profileValue.allowStylus !== true) return "stylus-reserved"
  if (config.enabled === false) return "gestures-disabled"
  if (config.touchLock || contextValue.touchLocked) return "touch-gestures-locked"
  if (config.presentationMode || contextValue.presentationMode) return "presentation-mode"
  if (!featureEnabled(owner, profileValue)) return "owner-disabled"
  if (contextValue.appRuleDisabled) return "app-rule-disabled"
  if (contextValue.fullscreen) {
    if (config.fullscreenPolicy === "disable") return "fullscreen-suppressed"
    if (config.fullscreenPolicy === "system-edges-only" && contextValue.systemEdge !== true) return "fullscreen-system-edge-only"
  }
  if (contextValue.game && config.gamePolicy !== "allow") return "game-suppressed"
  if (contextValue.drawing && config.drawingPolicy !== "allow") return "drawing-app-suppressed"
  if (contextValue.floatingDrag && owner !== "quick-settings" && owner !== "notifications") return "floating-drag-reserved"
  if (contextValue.osk && ["edge-swipe", "workspace-swipe", "overview-swipe", "dock-reveal", "back"].indexOf(owner) >= 0)
    return "osk-reserved"
  if (contextValue.overviewOpen && ["edge-swipe", "overview-swipe", "dock-reveal"].indexOf(owner) >= 0)
    return "overview-reserved"
  if (contextValue.reservedOwner && contextValue.reservedOwner !== owner) return "owner-reserved"
  if (owner === "back" && !contextValue.backAvailable && !contextValue.backShortcut && !config.backShortcut)
    return "back-backend-unavailable"
  return ""
}

function actionForEdge(edge, config, event) {
  var side = normalizeEdge(edge)
  var source = object(event)
  if (side === "bottom") {
    if (source.direct === true || text(source.mode) === "direct") return config.bottomEdge.direct
    return ""
  }
  if (side === "top") return config.topEdge.action
  if (side === "left") return config.sideEdge.left
  if (side === "right") return config.sideEdge.right
  return ""
}

function ownerFromAction(action) {
  if (action === "dock") return "dock-reveal"
  if (action === "overview") return "overview-swipe"
  if (action === "quick-settings") return "quick-settings"
  if (action === "notifications") return "notifications"
  if (action === "back") return "back"
  return ""
}

function directionForDelta(dx, dy) {
  if (Math.abs(dx) < 0.001 && Math.abs(dy) < 0.001) return ""
  if (Math.abs(dx) >= Math.abs(dy)) return dx < 0 ? "left" : "right"
  return dy < 0 ? "up" : "down"
}

function expectedDirection(edge) {
  if (edge === "bottom") return "up"
  if (edge === "top") return "down"
  if (edge === "left") return "right"
  if (edge === "right") return "left"
  return ""
}

function edgeFromEvent(event, config) {
  var source = object(event)
  var explicit = normalizeEdge(source.edge || source.startEdge)
  if (explicit) return explicit
  if (config.edgeLock !== true) return ""
  var point = object(source.point)
  var width = finite(source.width, 0)
  var height = finite(source.height, 0)
  var edgeWidth = clamp(finite(source.edgeWidth, 8), 1, 160)
  if (width > 0 && height > 0) {
    if (finite(point.x, 0) <= edgeWidth) return "left"
    if (finite(point.x, 0) >= width - edgeWidth) return "right"
    if (finite(point.y, 0) <= edgeWidth) return "top"
    if (finite(point.y, 0) >= height - edgeWidth) return "bottom"
  }
  return ""
}

function pointFor(event) {
  var source = object(event)
  var point = object(source.point)
  return { x: finite(point.x !== undefined ? point.x : source.x, 0), y: finite(point.y !== undefined ? point.y : source.y, 0) }
}

function fingersFor(value) { return Math.round(clamp(value || 1, 1, MAX_FINGERS)) }

function ownerFor(event, config, context) {
  var source = object(event)
  var settings = normalizeConfig(config)
  var inputKind = normalizeInputKind(source.inputKind || source.kind || "touch")
  var ctx = normalizeContext(Object.assign({}, context || {}, source.context || {}, { inputKind: inputKind }), settings)
  var profileValue = profileFor(settings, inputKind)
  if (!profileValue || profileValue.enabled === false) return { ok: false, owner: "", inputKind: inputKind, reason: "input-profile-disabled" }
  var edge = edgeFromEvent(source, settings)
  var fingers = fingersFor(source.fingers || source.touchCount || 1)
  var owner = normalizeOwner(source.owner)
  var action = ""

  if (!owner && fingers >= 4) {
    var four = profileValue.fourFingerAction
    owner = four === "overview" ? "overview-swipe" : (four === "workspace-next" || four === "workspace-previous" ? "workspace-swipe" : ownerFromAction(four))
  }
  if (!owner && fingers === 3) {
    var three = profileValue.threeFingerAction
    owner = three === "overview" ? "overview-swipe" : (three === "workspace-next" || three === "workspace-previous" ? "workspace-swipe" : ownerFromAction(three))
  }
  if (!owner && edge) {
    if (edge === "bottom") owner = "edge-swipe"
    else owner = ownerFromAction(actionForEdge(edge, settings, source))
  }
  if (!owner && source.gestureAction) owner = ownerFromAction(normalizeAction(source.gestureAction, "disabled"))
  if (!owner) return { ok: false, owner: "", inputKind: inputKind, edge: edge, fingers: fingers, reason: "no-owner" }
  if (owner === "edge-swipe" && edge !== "bottom" && edge !== "top" && edge !== "left" && edge !== "right")
    return { ok: false, owner: owner, inputKind: inputKind, edge: edge, fingers: fingers, reason: "edge-required" }
  var reason = suppressed(owner, inputKind, settings, ctx)
  if (reason) return { ok: false, owner: owner, inputKind: inputKind, edge: edge, fingers: fingers, reason: reason }
  if (ctx.reservedOwner && ctx.reservedOwner !== owner)
    return { ok: false, owner: owner, inputKind: inputKind, edge: edge, fingers: fingers, reason: "owner-reserved" }
  return {
    ok: true,
    owner: owner,
    inputKind: inputKind,
    edge: edge,
    fingers: fingers,
    action: action,
    profile: profileValue,
    context: ctx,
    reason: "owner-reserved"
  }
}

function emptyState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    phase: "idle",
    owner: "",
    inputKind: "",
    edge: "",
    fingers: 0,
    start: { x: 0, y: 0 },
    point: { x: 0, y: 0 },
    distance: 0,
    velocity: 0,
    direction: "",
    directionValid: true,
    progress: 0,
    canCommit: false,
    startedAt: 0,
    endedAt: 0,
    reason: "idle",
    action: null,
    preview: null,
    config: normalizeConfig({}),
    context: normalizeContext({}, normalizeConfig({}))
  }
}

function active(state) { return !!state && ACTIVE_PHASES.indexOf(String(state.phase || "")) >= 0 }

function timestamp(now, fallback) {
  var value = finite(now, fallback || 0)
  return value >= 0 ? value : (fallback || 0)
}

function movement(state, event, now) {
  var source = object(event)
  var point = pointFor(source)
  var start = object(state.start)
  var dx = point.x - finite(start.x, 0)
  var dy = point.y - finite(start.y, 0)
  var edge = String(state.edge || "")
  var signed = edge === "bottom" ? -dy : edge === "top" ? dy : edge === "left" ? dx : edge === "right" ? -dx : 0
  var distance = edge ? Math.max(0, signed) : Math.sqrt(dx * dx + dy * dy)
  var direction = edge ? expectedDirection(edge) : directionForDelta(dx, dy)
  var expected = expectedDirection(edge)
  var directionValid = !edge || distance < finite(state.profile && state.profile.movementThresholdPx, 18) || direction === expected
  var previousAt = finite(state.lastAt, state.startedAt)
  var currentAt = timestamp(now, previousAt)
  var elapsed = Math.max(1, currentAt - previousAt)
  var previousDistance = finite(state.distance, 0)
  var velocity = finite(source.velocity, NaN)
  if (!isFinite(velocity)) velocity = Math.abs(distance - previousDistance) / elapsed
  velocity = clamp(Math.abs(velocity), 0, 8)
  var profileValue = state.profile || {}
  var threshold = Math.max(finite(profileValue.thresholdPx, 96), finite(profileValue.movementThresholdPx, 18))
  var inertialDistance = distance
  if (profileValue.inertia !== false && velocity >= finite(profileValue.velocityThreshold, 0.35))
    inertialDistance = Math.min(threshold * 1.18, distance + velocity * 120)
  var progress = clamp(inertialDistance / threshold, 0, 1)
  var canCommit = directionValid && distance >= finite(profileValue.movementThresholdPx, 18) &&
    (distance >= threshold || (profileValue.inertia !== false && inertialDistance >= threshold) || velocity >= finite(profileValue.velocityThreshold, 0.35))
  return { point: point, distance: distance, velocity: velocity, direction: direction, directionValid: directionValid, progress: progress, canCommit: canCommit, now: currentAt }
}

function previewFor(state) {
  return {
    owner: String(state.owner || ""),
    inputKind: String(state.inputKind || ""),
    edge: String(state.edge || ""),
    fingers: Number(state.fingers || 0),
    distance: Number(state.distance || 0),
    velocity: Number(state.velocity || 0),
    direction: String(state.direction || ""),
    directionValid: state.directionValid !== false,
    progress: Number(state.progress || 0),
    canCommit: state.canCommit === true,
    actionHint: String(state.actionHint || "")
  }
}

function cloneState(state) {
  var source = state && typeof state === "object" ? state : emptyState()
  return JSON.parse(JSON.stringify(source))
}

function begin(event, config, context, now, existingState) {
  var source = object(event)
  var settings = normalizeConfig(config)
  var point = pointFor(source)
  var current = existingState || null
  if (active(current)) {
    var reserved = cloneState(current)
    reserved.phase = "suppressed"
    reserved.reason = "owner-reserved"
    reserved.canCommit = false
    reserved.preview = previewFor(reserved)
    return reserved
  }
  var decision = ownerFor(source, settings, context)
  var base = emptyState()
  base.config = settings
  base.context = decision.context || normalizeContext(context, settings)
  base.inputKind = decision.inputKind || normalizeInputKind(source.inputKind || source.kind)
  base.edge = decision.edge || edgeFromEvent(source, settings)
  base.fingers = decision.fingers || fingersFor(source.fingers || source.touchCount || 1)
  base.start = point
  base.point = point
  base.startedAt = timestamp(now, 0)
  base.lastAt = base.startedAt
  base.owner = decision.owner || ""
  base.profile = decision.profile || profileFor(settings, base.inputKind) || {}
  base.actionHint = base.owner === "edge-swipe" ? actionForEdge(base.edge, settings, source) : ""
  if (!decision.ok) {
    base.phase = "suppressed"
    base.reason = decision.reason || "gesture-rejected"
    base.owner = decision.owner || ""
    base.canCommit = false
    base.preview = previewFor(base)
    return base
  }
  base.phase = "armed"
  base.reason = "owner-reserved"
  base.preview = previewFor(base)
  return base
}

function update(state, event, now) {
  if (!active(state)) return state || emptyState()
  var next = cloneState(state)
  var move = movement(next, event, now)
  next.point = move.point
  next.distance = move.distance
  next.velocity = move.velocity
  next.direction = move.direction
  next.directionValid = move.directionValid
  next.progress = move.progress
  next.canCommit = move.canCommit
  next.lastAt = move.now
  if (move.distance >= finite(next.profile && next.profile.movementThresholdPx, 18)) next.phase = "tracking"
  next.reason = !move.directionValid ? "wrong-direction" : (move.canCommit ? "commit-ready" : (next.phase === "tracking" ? "threshold-pending" : "waiting-for-movement"))
  next.preview = previewFor(next)
  return next
}

function actionFor(state, event, context) {
  var settings = state.config || normalizeConfig({})
  var source = object(event)
  var ctx = normalizeContext(Object.assign({}, state.context || {}, context || {}), settings)
  var action = ""
  if (state.owner === "edge-swipe") {
    if (state.edge === "bottom") {
      if (source.direct === true || text(source.mode) === "direct") action = settings.bottomEdge.direct
      else action = state.distance >= finite(state.profile.longDistancePx, 144) ? settings.bottomEdge.long : settings.bottomEdge.short
    } else action = actionForEdge(state.edge, settings, source)
  } else if (state.owner === "workspace-swipe") {
    action = state.direction === "left" || state.direction === "up" ? "workspace-previous" : "workspace-next"
  } else if (state.owner === "overview-swipe") action = "overview"
  else if (state.owner === "dock-reveal") action = "dock"
  else if (state.owner === "quick-settings") action = "quick-settings"
  else if (state.owner === "notifications") action = "notifications"
  else if (state.owner === "back") action = "back"
  action = normalizeAction(action, "disabled")
  if (action === "disabled") return { ok: false, action: action, reason: "action-disabled" }
  if (action === "back" && !ctx.backAvailable && !ctx.backShortcut && !settings.backShortcut)
    return { ok: false, action: action, reason: "back-backend-unavailable" }
  var result = { ok: true, type: "gesture", action: action, owner: state.owner, direction: state.direction, inputKind: state.inputKind }
  if (action === "back") {
    result.backend = ctx.backAvailable === true ? "backend" : "shortcut"
    result.shortcut = ctx.backShortcut || settings.backShortcut || ""
  }
  return result
}

function end(state, event, context, now) {
  if (!active(state)) return { ok: false, state: state || emptyState(), action: null, reason: "gesture-not-active" }
  var next = update(state, event, now)
  var currentContext = normalizeContext(Object.assign({}, next.context || {}, context || {}), next.config || normalizeConfig({}))
  var conflict = suppressed(next.owner, next.inputKind, next.config || normalizeConfig({}), currentContext)
  if (conflict && conflict !== "back-backend-unavailable") {
    next.phase = "cancelled"
    next.endedAt = next.lastAt
    next.action = null
    next.canCommit = false
    next.reason = conflict
    next.preview = previewFor(next)
    return { ok: false, state: next, action: null, reason: conflict }
  }
  if (!next.canCommit) {
    next.phase = "cancelled"
    next.endedAt = next.lastAt
    next.action = null
    next.reason = next.directionValid ? "threshold-not-reached" : "wrong-direction"
    next.preview = previewFor(next)
    return { ok: false, state: next, action: null, reason: next.reason }
  }
  var action = actionFor(next, event, context)
  next.endedAt = next.lastAt
  next.action = action.ok ? action : null
  next.phase = action.ok ? "committed" : "cancelled"
  next.reason = action.ok ? "committed" : action.reason
  next.canCommit = action.ok
  next.preview = previewFor(next)
  return { ok: action.ok, state: next, action: action.ok ? action : null, reason: next.reason }
}

function cancel(state, reason) {
  var next = cloneState(state || emptyState())
  if (next.phase === "committed") return next
  next.phase = "cancelled"
  next.canCommit = false
  next.action = null
  next.reason = String(reason || "cancelled")
  next.preview = previewFor(next)
  return next
}

function availableOwners(config, context, inputKind) {
  var result = []
  var settings = normalizeConfig(config)
  var kind = normalizeInputKind(inputKind || "touch")
  for (var i = 0; i < OWNERS.length; i++) {
    var owner = OWNERS[i]
    var reason = suppressed(owner, kind, settings, normalizeContext(context, settings))
    if (!reason) result.push(owner)
  }
  return result.slice(0, MAX_ACTIONS)
}

function summary(state) {
  var source = state || emptyState()
  return {
    phase: String(source.phase || "idle"),
    active: active(source),
    owner: String(source.owner || ""),
    inputKind: String(source.inputKind || ""),
    edge: String(source.edge || ""),
    fingers: Number(source.fingers || 0),
    distance: Number(source.distance || 0),
    velocity: Number(source.velocity || 0),
    direction: String(source.direction || ""),
    progress: Number(source.progress || 0),
    canCommit: source.canCommit === true,
    reason: String(source.reason || ""),
    action: source.action ? { action: String(source.action.action || ""), backend: String(source.action.backend || ""), shortcut: String(source.action.shortcut || "") } : null
  }
}

var api = {
  SCHEMA_VERSION: SCHEMA_VERSION,
  MAX_FINGERS: MAX_FINGERS,
  OWNERS: OWNERS,
  ACTIONS: ACTIONS,
  normalizeConfig: normalizeConfig,
  normalizeContext: normalizeContext,
  normalizeInputKind: normalizeInputKind,
  ownerFor: ownerFor,
  availableOwners: availableOwners,
  emptyState: emptyState,
  active: active,
  begin: begin,
  update: update,
  end: end,
  cancel: cancel,
  summary: summary
}
if (typeof module !== "undefined") module.exports = api
