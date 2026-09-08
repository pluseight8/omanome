var CURRENT_SCHEMA_VERSION = 2

function defaults() {
  return {
    schemaVersion: CURRENT_SCHEMA_VERSION,
    general: { mode: "automatic", profile: "Desktop", language: "system", reduceMotion: false, largeUi: false, inputDebounceMs: 320 },
    appearance: { theme: "follow-omarchy", accent: "follow-omarchy", radius: 18, opacity: 0.96, density: "comfortable" },
    controlCenter: { enabled: true, masterEnabled: true, suspended: false, widget: { enabled: true, position: "right", clickAction: "control-center", rightClickAction: "context-menu", longPressAction: "context-menu", showLabel: false }, compactToggles: ["master", "mode", "gestures", "osk", "rotation"], visibleModules: ["touch-mode", "tablet-ui", "osk", "gestures", "snap-assist", "split-view", "dock", "window-controls", "rotation", "stylus", "notifications", "clipboard", "effects"], moduleOrder: ["touch-mode", "tablet-ui", "osk", "gestures", "snap-assist", "split-view", "dock", "window-controls", "rotation", "stylus", "notifications", "clipboard", "effects"], osd: { enabled: true, compact: true, durationMs: 2600 } },
    adaptive: { enabled: true, profile: "auto", automaticTransitions: true, externalKeyboardPolicy: "hybrid", unknownKeyboardPolicy: "hybrid", transition: { enabled: true, debounceMs: 260, stabilityMs: 420, durationMs: 260, oskPolicy: "hide-on-attach", showOsd: true }, profiles: { custom: { mode: "auto", featureOverrides: {}, componentBehavior: {} } }, deviceRules: [], dockedMode: { enabled: true, trigger: "external-monitor-and-keyboard", profile: "desktop", keepTouch: true, restoreAutoState: true, rotation: "preserve", debounceMs: 180, stabilityMs: 260 } },
    tabletMode: { enabled: true, touchTarget: 48, autoFromTouch: true, autoFromStylus: true, physicalKeyboardExit: true, transitionDuration: 180, dockPreference: "adaptive", windowControls: "touch", gestures: true, posture: { auto: true, debounceMs: 320, minimumDwellMs: 900, laptopSuppressAutoShow: true, autoRotateInLaptop: false } },
    input: { schemaVersion: 1, nativeBackend: "auto", allowWtypeFallback: true, suppressOskOnPhysicalKeyboard: true, suppressOskOnDetachableKeyboard: true, suppressOskOnBluetoothKeyboard: true, deviceHotplug: true, safeModeDisableNative: false, defaultOutput: "", deviceMappings: {} },
    onboarding: { completed: false, skipped: false, version: 1, privacyAcknowledged: false },
    accessibility: { touchTargetSize: "default", textScale: 1.0, highContrast: false, reducedMotion: false, reduceTransparency: false, screenReaderHints: true },
    touch: { enabled: true, edgeWidth: 36, threshold: 96, velocity: 0.35, inertia: true, invert: false, threeFingerAction: "workspace", fourFingerAction: "overview", conflictPolicy: "disable-fullscreen", disableOnFullscreen: true, fullscreenAllowList: [], fullscreenDenyList: [], adaptiveTargetMode: "automatic" },
    stylus: { enabled: true, pressureCurve: "linear", pressureMin: 0.0, pressureMax: 1.0, palmRejection: "automatic", palmBackend: "native-first", handwritingEnabled: true, recognitionProvider: "none", hoverCursor: true, showOskOnTextField: "ask", annotation: true, buttonMap: { primary: "right-click", secondary: "middle-click", tertiary: "annotation", eraser: "eraser" } },
    windowControls: { enabled: true, show: "tablet", minTarget: 48, style: "gnome", autoHide: true, autoHideDelay: 1800, position: "top-right", opacity: 0.94 },
    quickSettings: { wifi: true, bluetooth: true, airplane: true, volume: true, microphone: true, brightness: true, nightLight: true, powerProfile: true, theme: true, dnd: true, rotation: true, keyboard: true, stylus: true, screenshot: true, recording: true, lock: true, power: true },
    dock: { enabled: true, position: "bottom", mode: "floating", iconSize: 48, minIconSize: 40, maxIconSize: 64, dynamicSizing: true, runningApplications: true, showLauncher: true, showSettings: false, showTrash: false, multipleWindowAction: "cycle", autohide: true, autohideMode: "intelligent", revealByPointer: true, revealByTouch: true, edgePressure: 12, revealDelay: 120, hideDelay: 650, dodgeMode: "active-window", fullscreenHide: true, margin: 18, padding: 10, spacing: 8, radius: 22, monitor: "active", workspaceIsolation: false, monitorIsolation: false, backgroundOpacity: 0.82, blur: true, shadow: true, border: true, borderOpacity: 0.34, indicatorStyle: "dot", animation: "slide", clickAction: "activate-or-launch", middleClickAction: "new-window", scrollAction: "workspace" },
    overview: { enabled: true, style: "gnome", animationDuration: 180, blur: true, showAllWorkspaces: false, showDock: true, workspaceMode: "dynamic", fixedWorkspaceCount: 5, workspaceOrientation: "horizontal", search: true },
    launcher: { enabled: true, categories: true, favorites: [], favoritesFirst: true, folders: [], showRecent: true, recentApplications: [], dragReorder: true, contextMenu: true, gridColumns: 6 },
    multitasking: { enabled: true, gap: 12, minimumWindowSize: { width: 320, height: 240 }, layouts: [], customLayouts: [], tabletSwitcher: { enabled: true, mode: "automatic", scope: "current-workspace", maxCards: 32, closeOnSwipe: false, touchSwipe: true, swipeThresholdPx: 96, swipeVelocity: 0.5, closeThresholdPx: 120, selectedScale: 1.0, sideScale: 0.92, sideOpacity: 0.76 }, layoutPersistence: { enabled: true, recentEnabled: true, maxRecent: 12, maxSaved: 32, saved: [], recent: [] }, snapAssist: { enabled: true, dwellMs: 220, movementThreshold: 18, stylusDwellMs: 120, preview: true, edgeZones: true, sensitivity: 1.0, portraitLayouts: true, autoSecondWindowPicker: true }, splitView: { enabled: true, divider: true, defaultRatio: "50/50", rememberRatio: true, autoConvertOnRotation: true, autoHide: true, autoHideMs: 1800, handleSize: 48 }, floating: { enabled: true, miniEnabled: true, pictureInPicture: true, keepAbove: true, edgeSnap: true, rememberPosition: true, perMonitor: true, resizeHandle: true }, gestures: { enabled: true, workspaceSwipe: true, overviewSwipe: true, dockReveal: true, back: true, quickSettings: true, touchscreenOnly: true, edgeLock: true, conflictPolicy: "suppress-in-fullscreen", fullscreenPolicy: "disable", drawingPolicy: "suppress", gamePolicy: "suppress", drawingApps: [], gameApps: [], touchLock: false, presentationMode: false, backShortcut: "", bottomEdge: { short: "dock", long: "overview", direct: "disabled" }, topEdge: { action: "quick-settings" }, sideEdge: { left: "back", right: "back" }, touchscreen: { enabled: true, edgeSwipe: true, workspaceSwipe: true, overviewSwipe: true, dockReveal: true, quickSettings: true, back: true, threeFingerAction: "workspace", fourFingerAction: "workspace", thresholdPx: 96, movementThresholdPx: 18, velocityThreshold: 0.35, inertia: true, allowStylus: false }, touchpad: { enabled: false, edgeSwipe: false, workspaceSwipe: false, overviewSwipe: false, dockReveal: false, quickSettings: false, back: false, thresholdPx: 96, movementThresholdPx: 18, velocityThreshold: 0.45, inertia: false } }, workspaceNavigation: { mode: "swipe", showOverlay: true, activateEmpty: true }, multiMonitor: { enabled: true, hotplugRecovery: true }, groups: [], sessionRestore: "ask", closePolicy: "keep", monitorPolicy: "active", duplicatePolicy: "ask", launchTimeoutMs: 12000, maxGroups: 32, experimentalWindowThrow: false, shortcuts: { "snap-left": "SUPER+ALT+LEFT", "snap-right": "SUPER+ALT+RIGHT", "next-layout": "SUPER+ALT+L", "toggle-float": "SUPER+ALT+F", "create-pair": "SUPER+ALT+P", "break-pair": "SUPER+ALT+SHIFT+P", "move-pair-workspace": "SUPER+ALT+W" } },
    keyboard: { enabled: true, layout: "auto", mode: "standard", showNumberRow: true, showModifierRow: true, showNavigationRow: true, showFunctionRow: false, capsLock: true, symbols: true, suggestions: true, autocorrect: false, learning: false, haptic: true, sound: false, autoShow: true, height: 300, toolbar: true, toolbarOverflow: true, keyPopup: true, keyPopupScale: 1.25, keyPopupDuration: 180, longPress: true, longPressDelay: 360, repeatDelay: 420, repeatRate: 55, spaceCursor: true, swipeLayerSwitch: true, floating: { x: 0.5, y: 0.72, width: 0.82, snap: true }, split: { gap: 24, blockWidth: 0.43, vertical: 0.72, thumbReach: 0.62, symmetric: true }, oneHanded: { width: 0.72, offset: 0.04, scale: 0.92 }, emojiCategory: "recent", emojiRecent: [], suggestionLocale: "auto" },
    clipboard: { enabled: true, historyLimit: 100, retentionDays: 30, persist: true, persistPinnedOnly: false, maxStorageMb: 256, pinning: true, tags: true, clearOnLogout: false, excludedApps: [], privateMode: false },
    notifications: { enabled: true, groupByApp: true, history: true, timestamps: true, actions: true, maxHistory: 200, perAppMute: [], doNotDisturb: false },
    altTab: { style: "coverflow", modes: ["coverflow", "carousel", "gnome", "grid", "compact"], groupByApp: true, scope: "current-workspace", perspective: 0.8, angle: 28, spacing: 0.18, scale: 0.82, selectedScale: 1.0, sideOpacity: 0.68, dimBackground: 0.54, reflection: false, shadow: true, showIcon: true, showTitle: true, showMetadata: true, livePreview: "auto", previewStreams: 3, touchSwipe: true, touchFling: true, stylusPreciseSelection: true, animationDuration: 160 },
    blur: { enabled: true, backend: "hyprland-layer-rule", quality: "balanced", batteryQuality: "battery-saver", fullscreenQuality: "battery-saver", highGpuQuality: "performance", highGpuThreshold: 0.85, reduceBlurWithMotion: true, dock: true, overview: true, launcher: true, quickSettings: true, notificationCenter: true, clipboard: true, osk: true, settings: true, radius: 18, passes: 2, opacity: 0.9, brightness: 0.85, saturation: 1.1, noise: 0.02, vibrancy: 0.06, tint: "", border: true, shadow: true, surfaces: { dock: { enabled: true }, overview: { enabled: true }, launcher: { enabled: true }, quickSettings: { enabled: true }, notifications: { enabled: true }, clipboard: { enabled: true }, altTab: { enabled: true }, osk: { enabled: true }, settings: { enabled: true }, windowControls: { enabled: true }, annotation: { enabled: true } } },
    effects: { enabled: true, wobblyWindows: false, desktopCube: false, companionPolicy: "auto", existingCubeBackend: "detect", disableOnBattery: true, disableOnFullscreen: true, performanceMode: "balanced" },
    animations: { enabled: true, preset: "GNOME", speedMultiplier: 1.0, durationScale: 1.0, easing: "standard", springStrength: 0.65, reducedMotion: false, overview: true, dockHoverZoom: true, dockHoverScale: 1.2, dockReveal: true, notificationEntry: true },
    performance: { mode: "balanced", qualityPreset: "balanced", adaptiveQuality: true, highGpuThreshold: 0.85, gpuLoadSource: "backend-only", disableOnBattery: true, disableOnFullscreen: true, fullscreenPolicy: "battery-saver", autoDisableOnFrameBudget: false },
    applicationRules: { enabled: true, rules: [] },
    wobbly: { enabled: false, profile: "subtle", stiffness: 0.72, friction: 0.78, damping: 0.62, mass: 1.0, gridResolution: 8, maxVertices: 1024, maxDeformation: 0.035, edgeResistance: 0.82, velocityInfluence: 0.45, snapStrength: 0.7, onMove: true, onResize: true, onMaximize: true, onOpen: false, onClose: false, excludeFullscreen: true, excludeGames: true, excludeSteam: true, excludeVr: true, excludeDrawingApps: true, excludeMaximized: true, allowXwayland: false, excludedApps: [] },
    cube: { enabled: false, backend: "detect", monitorMode: "active-monitor", perspective: 0.82, fieldOfView: 62, radius: 1.0, faceSpacing: 0.0, background: "wallpaper", opacity: 1.0, zoom: 1.0, parallax: 0.5, reflection: false, caps: true, wrapAround: false, animationDuration: 420, easing: "spring", touchInteractive: true, touchpadOverride: false, mouseDrag: true, stylusDrag: true },
    forceQuit: { enabled: true, policy: "graceful-term-kill", gracefulTimeoutMs: 1500, termTimeoutMs: 1000, protectSessionProcesses: true, allowProtectedOverride: false, includeFlatpak: true, includeContainers: false, cancelOnEscape: true, cancelOnRightClick: true, cancelButton: true, stylusSecondaryButton: true },
    rotation: { enabled: true, lock: false, orientation: "auto", sensor: "auto", outputPolicy: "mapped", transformTouch: true, transformStylus: true, orientationDebounceMs: 550, minimumDwellMs: 1000 },
    privacy: { clipboardPrivate: false, neverLogClipboard: true, telemetry: false, updateChecks: true },
    shortcuts: { overview: "SUPER", launcher: "SUPER+SPACE", quickSettings: "SUPER+Q", clipboard: "SUPER+V", keyboard: "SUPER+K", forceQuit: "SUPER+ESC" },
    updates: { channel: "stable", automaticInstall: false, notify: true, rollbackRetention: 3, checkTimeoutSeconds: 8, healthTimeoutSeconds: 5 },
    recovery: { autoRollback: true, safeModeOnCrash: true, maxCrashAttempts: 2, preserveFailedUpdates: true },
    diagnostics: { logLevel: "info", supportBundleRetention: 3, redactPaths: true, includeSystemCommands: true }
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

function migrationStepZeroToOne(source, report) {
  // Version 0 used the early prototype names. Keep this migration explicit so
  // a future schema can be added without silently changing user intent.
  if (source.tablet && !source.tabletMode) source.tabletMode = source.tablet
  if (source.osk && !source.keyboard) source.keyboard = source.osk
  // A pre-0.6 config already represents a configured installation. Do not
  // interrupt upgrades with first-run onboarding; only a genuinely new config
  // created from defaults should see the setup flow.
  if (source.onboarding === undefined) source.onboarding = { completed: true, skipped: true, version: 1, privacyAcknowledged: false }
  source.schemaVersion = 1
  report.applied.push("0->1")
}

function migrationStepOneToTwo(source, report) {
  if (source.onboarding === undefined) source.onboarding = { completed: true, skipped: true, version: 1, privacyAcknowledged: false }
  if (!isObject(source.updates)) source.updates = {}
  if (source.updates.channel === undefined) source.updates.channel = "stable"
  if (["stable", "beta", "main", "nightly"].indexOf(source.updates.channel) < 0) source.updates.channel = "stable"
  if (source.updates.automaticInstall === undefined) source.updates.automaticInstall = false
  if (source.updates.notify === undefined) source.updates.notify = true
  if (source.updates.rollbackRetention === undefined) source.updates.rollbackRetention = 3
  if (source.updates.checkTimeoutSeconds === undefined) source.updates.checkTimeoutSeconds = 8
  if (source.updates.healthTimeoutSeconds === undefined) source.updates.healthTimeoutSeconds = 5
  if (!isObject(source.recovery)) source.recovery = {}
  if (source.recovery.autoRollback === undefined) source.recovery.autoRollback = true
  if (source.recovery.safeModeOnCrash === undefined) source.recovery.safeModeOnCrash = true
  if (source.recovery.maxCrashAttempts === undefined) source.recovery.maxCrashAttempts = 2
  if (source.recovery.preserveFailedUpdates === undefined) source.recovery.preserveFailedUpdates = true
  if (!isObject(source.diagnostics)) source.diagnostics = {}
  if (source.diagnostics.logLevel === undefined) source.diagnostics.logLevel = "info"
  if (source.diagnostics.supportBundleRetention === undefined) source.diagnostics.supportBundleRetention = 3
  if (source.diagnostics.redactPaths === undefined) source.diagnostics.redactPaths = true
  if (source.diagnostics.includeSystemCommands === undefined) source.diagnostics.includeSystemCommands = true
  if (!isObject(source.performance)) source.performance = {}
  if (source.performance.mode === undefined && source.performance.qualityPreset !== undefined) {
    source.performance.mode = source.performance.qualityPreset
    report.applied.push("performance-mode-from-quality-preset")
  }
  source.schemaVersion = 2
  report.applied.push("1->2")
}

function normalizeInputConfig(source, report) {
  var changed = false
  if (!isObject(source.input)) source.input = {}
  if (source.input.schemaVersion === undefined) { source.input.schemaVersion = 1; changed = true }
  if (source.input.nativeBackend === undefined) { source.input.nativeBackend = "auto"; changed = true }
  if (source.input.allowWtypeFallback === undefined) { source.input.allowWtypeFallback = true; changed = true }
  if (source.input.suppressOskOnPhysicalKeyboard === undefined) { source.input.suppressOskOnPhysicalKeyboard = true; changed = true }
  if (source.input.suppressOskOnDetachableKeyboard === undefined) { source.input.suppressOskOnDetachableKeyboard = true; changed = true }
  if (source.input.suppressOskOnBluetoothKeyboard === undefined) { source.input.suppressOskOnBluetoothKeyboard = true; changed = true }
  if (source.input.deviceHotplug === undefined) { source.input.deviceHotplug = true; changed = true }
  if (source.input.safeModeDisableNative === undefined) { source.input.safeModeDisableNative = false; changed = true }
  if (source.input.defaultOutput === undefined) { source.input.defaultOutput = ""; changed = true }
  if (!isObject(source.input.deviceMappings)) { source.input.deviceMappings = {}; changed = true }
  if (!isObject(source.tabletMode)) source.tabletMode = {}
  if (!isObject(source.tabletMode.posture)) source.tabletMode.posture = {}
  if (source.tabletMode.posture.auto === undefined) { source.tabletMode.posture.auto = true; changed = true }
  if (source.tabletMode.posture.debounceMs === undefined) { source.tabletMode.posture.debounceMs = 320; changed = true }
  if (source.tabletMode.posture.minimumDwellMs === undefined) { source.tabletMode.posture.minimumDwellMs = 900; changed = true }
  if (source.tabletMode.posture.laptopSuppressAutoShow === undefined) { source.tabletMode.posture.laptopSuppressAutoShow = true; changed = true }
  if (source.tabletMode.posture.autoRotateInLaptop === undefined) { source.tabletMode.posture.autoRotateInLaptop = false; changed = true }
  if (changed && report && report.applied.indexOf("input-v1") < 0) report.applied.push("input-v1")
}

function normalizeMultitaskingOneOne(source, report) {
  if (!isObject(source.multitasking)) source.multitasking = {}
  var multitasking = source.multitasking
  var defaultsMultitasking = defaults().multitasking
  var changed = false
  var sections = ["tabletSwitcher", "layoutPersistence", "shortcuts"]
  for (var i = 0; i < sections.length; i++) {
    var key = sections[i]
    if (!isObject(multitasking[key])) {
      multitasking[key] = clone(defaultsMultitasking[key])
      changed = true
    }
  }
  var tablet = multitasking.tabletSwitcher
  var tabletDefaults = defaultsMultitasking.tabletSwitcher
  Object.keys(tabletDefaults).forEach(function(key) {
    if (tablet[key] === undefined) { tablet[key] = clone(tabletDefaults[key]); changed = true }
  })
  var persistence = multitasking.layoutPersistence
  var persistenceDefaults = defaultsMultitasking.layoutPersistence
  Object.keys(persistenceDefaults).forEach(function(key) {
    if (persistence[key] === undefined) { persistence[key] = clone(persistenceDefaults[key]); changed = true }
  })
  var shortcuts = multitasking.shortcuts
  var shortcutDefaults = defaultsMultitasking.shortcuts
  Object.keys(shortcutDefaults).forEach(function(key) {
    if (shortcuts[key] === undefined) { shortcuts[key] = shortcutDefaults[key]; changed = true }
  })
  if (changed && report && report.applied.indexOf("multitasking-1.1-defaults") < 0) report.applied.push("multitasking-1.1-defaults")
}

function fillMissing(target, template) {
  var changed = false
  if (!isObject(target) || !isObject(template)) return changed
  Object.keys(template).forEach(function(key) {
    if (target[key] === undefined) {
      target[key] = clone(template[key])
      changed = true
    } else if (isObject(target[key]) && isObject(template[key])) {
      if (fillMissing(target[key], template[key])) changed = true
    }
  })
  return changed
}

function legacyAdaptiveProfile(source) {
  var profile = String(isObject(source.general) ? source.general.profile || "" : "").toLowerCase().replace(/[\s_]+/g, "-")
  if (profile === "automatic" || profile === "default") return "auto"
  if (["desktop", "tablet", "hybrid", "presentation", "gaming", "custom"].indexOf(profile) >= 0) return profile
  if (profile === "stylus" || profile === "gnome-like") return "hybrid"
  return "auto"
}

function normalizeAdaptiveOneTwo(source, report) {
  var templates = defaults()
  var changed = false
  var hadAdaptive = isObject(source.adaptive)
  var hadControlCenter = isObject(source.controlCenter)
  if (!hadControlCenter) {
    source.controlCenter = clone(templates.controlCenter)
    changed = true
  } else if (fillMissing(source.controlCenter, templates.controlCenter)) changed = true
  if (!hadAdaptive) {
    source.adaptive = clone(templates.adaptive)
    source.adaptive.profile = legacyAdaptiveProfile(source)
    changed = true
  } else if (fillMissing(source.adaptive, templates.adaptive)) changed = true
  if (!isObject(source.controlCenter.widget)) {
    source.controlCenter.widget = clone(templates.controlCenter.widget)
    changed = true
  }
  var positions = ["left", "center", "right"]
  if (positions.indexOf(String(source.controlCenter.widget.position || "right")) < 0) {
    source.controlCenter.widget.position = "right"
    changed = true
  }
  if (!Array.isArray(source.controlCenter.compactToggles)) {
    source.controlCenter.compactToggles = clone(templates.controlCenter.compactToggles)
    changed = true
  }
  if (!Array.isArray(source.controlCenter.visibleModules)) {
    source.controlCenter.visibleModules = clone(templates.controlCenter.visibleModules)
    changed = true
  }
  if (!Array.isArray(source.controlCenter.moduleOrder)) {
    source.controlCenter.moduleOrder = clone(templates.controlCenter.moduleOrder)
    changed = true
  }
  if (!Array.isArray(source.adaptive.deviceRules)) {
    source.adaptive.deviceRules = []
    changed = true
  }
  if (!isObject(source.adaptive.dockedMode)) {
    source.adaptive.dockedMode = clone(templates.adaptive.dockedMode)
    changed = true
  } else if (fillMissing(source.adaptive.dockedMode, templates.adaptive.dockedMode)) changed = true
  if (changed && report && report.applied.indexOf("adaptive-1.2-defaults") < 0) report.applied.push("adaptive-1.2-defaults")
}

function migrateDetailed(raw) {
  if (!isObject(raw)) return { ok: false, reason: "invalid-root", config: null, applied: [] }
  var source = clone(raw)
  var version = source.schemaVersion === undefined ? 0 : Number(source.schemaVersion)
  if (!isFinite(version) || Math.floor(version) !== version || version < 0)
    return { ok: false, reason: "invalid-schema-version", config: null, applied: [] }
  if (version > CURRENT_SCHEMA_VERSION)
    return { ok: false, reason: "future-schema", schemaVersion: version, config: null, applied: [] }
  var report = { ok: true, from: version, to: CURRENT_SCHEMA_VERSION, applied: [] }
  if (version < 1) migrationStepZeroToOne(source, report)
  if (source.schemaVersion < 2) migrationStepOneToTwo(source, report)
  if (!isObject(source.performance)) source.performance = {}
  if (source.performance.mode === undefined && source.performance.qualityPreset !== undefined) {
    source.performance.mode = source.performance.qualityPreset
    report.applied.push("performance-mode-from-quality-preset")
  }
  normalizeInputConfig(source, report)
  normalizeMultitaskingOneOne(source, report)
  normalizeAdaptiveOneTwo(source, report)
  return { ok: true, config: merge(defaults(), source), from: version, to: CURRENT_SCHEMA_VERSION, applied: report.applied, migrated: report.applied.length > 0 }
}

function loadDetailed(raw) {
  if (String(raw || "").trim() === "") return { ok: true, config: defaults(), from: CURRENT_SCHEMA_VERSION, to: CURRENT_SCHEMA_VERSION, applied: [], migrated: false, fresh: true }
  try {
    var parsed = JSON.parse(String(raw || ""))
    return migrateDetailed(parsed)
  } catch (error) {
    return { ok: false, reason: "invalid-json", config: null, applied: [], error: String(error) }
  }
}

function migrate(raw) {
  var result = migrateDetailed(raw)
  return result.ok ? result.config : defaults()
}

function load(raw) {
  var result = loadDetailed(raw)
  return result.ok ? result.config : defaults()
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
  result.schemaVersion = CURRENT_SCHEMA_VERSION
  return result
}

function isValid(config) {
  return isObject(config) && Number(config.schemaVersion) === CURRENT_SCHEMA_VERSION
}

var api = { CURRENT_SCHEMA_VERSION: CURRENT_SCHEMA_VERSION, defaults: defaults, migrate: migrate, migrateDetailed: migrateDetailed, load: load, loadDetailed: loadDetailed, get: get, set: set, isValid: isValid }
if (typeof module !== "undefined") module.exports = api
