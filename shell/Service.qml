import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "models/Config.js" as Config
import "models/Clipboard.js" as ClipboardModel
import "models/Companion.js" as CompanionModel
import "models/Effects.js" as EffectsModel
import "models/Performance.js" as PerformanceModel
import "models/AppRules.js" as AppRulesModel
import "models/Cube.js" as CubeModel
import "models/Wobbly.js" as WobblyModel
import "models/ForceQuit.js" as ForceQuitModel
import "models/I18n.js" as I18n
import "models/QuickSettings.js" as QuickSettingsModel
import "models/Stylus.js" as StylusModel
import "models/Touch.js" as TouchModel

// Omanome's one shared service. It is deliberately headless: all visible
// surfaces are summoned through the existing Omarchy shell host, so Omanome
// never starts a second Quickshell instance or replaces the Omarchy bar.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string configDir: configHome + "/omanome"
  readonly property string stateDir: stateHome + "/omanome"
  readonly property string configPath: configDir + "/config.json"
  readonly property string clipboardPath: stateDir + "/clipboard.json"
  property string pluginRoot: ""

  property var config: Config.defaults()
  property bool configReady: false
  property bool _loadingConfig: false
  property bool safeMode: false
  property bool annotationVisible: false

  property var devices: []
  property var monitors: []
  property var clients: []
  property var stylusDevices: []
  property var keyboardDevices: []
  property bool hasTouchscreen: false
  property bool hasStylus: false
  property bool hasPhysicalKeyboard: false
  property bool hyprlandAvailable: false
  property bool wtypeAvailable: false
  // A persistent virtual-input companion is optional. Keep this explicit so
  // the OSK never presents cursor/prediction features as available when only
  // one-shot wtype is installed.
  property bool inputBackendAvailable: false
  property var companionState: CompanionModel.normalize({})
  property var effectBackend: ({ hyprlandAvailable: false, backend: "hyprland-layer-rule", layerRulesAvailable: false, livePreviewAvailable: false, livePreviewBackend: "quickshell-screencopy", livePreviewProtocol: "hyprland-toplevel-export-v1", livePreviewReason: "not probed", external: { desktopCube: false, desktopCubeBackend: "none" } })
  // ScreencopyView reports compositor-owned frames asynchronously. Keeping a
  // keyed registry lets the shell expose a truthful capability without a
  // timer, screenshot file, or per-frame IPC poll.
  property var livePreviewReports: ({})
  property var livePreviewState: ({ available: false, backend: "quickshell-screencopy", protocol: "hyprland-toplevel-export-v1", activeStreams: 0, reason: "waiting for compositor-owned ScreencopyView content" })
  property var effectCapabilities: EffectsModel.capabilityState({}, {})
  property var performanceState: PerformanceModel.snapshot({}, {})
  property var forceQuitState: ({ active: false, phase: "idle", target: null, message: "" })
  property string blurRuleSignature: ""
  property string lastInput: "keyboard"
  property string detectedMode: "desktop"
  property string lastError: ""
  property int stateRevision: 0

  property var clipboardHistory: []
  property bool clipboardWatching: false
  property string captureScript: ""
  property var notificationService: null
  property var quickState: ({ wifi: false, bluetooth: false, airplane: false, volume: true, microphone: true, nightLight: false, dnd: false, rotationLock: false, recording: false, powerProfile: "balanced" })
  property var systemState: ({ wifiAvailable: false, wifiEnabled: false, wifiConnected: false, airplane: false, wifiSsid: "", wifiSignal: -1, bluetoothAvailable: false, bluetoothPowered: false, volumeAvailable: false, volume: 0, volumeMuted: false, microphoneAvailable: false, microphoneVolume: 0, microphoneMuted: false, brightnessAvailable: false, brightness: 0, powerProfileAvailable: false, powerProfile: "balanced", batteryAvailable: false, batteryPercent: -1, batteryState: "unknown", nightLightAvailable: false, nightLightEnabled: false, dndAvailable: false, dnd: false, rotationAvailable: false, rotationSensorAvailable: false, rotationDbusAvailable: false, rotationAccelerometerAvailable: false, rotationSensorBackend: "manual", rotationLock: false, recordingAvailable: false, recording: false })
  property var wifiNetworks: []
  property var bluetoothDevices: []
  property var audioDevices: []
  property string orientation: "normal"
  property int rotationTransform: 0
  property int pendingRotationTransform: -1
  property int queuedRotationTransform: -1
  property var rotationRollback: ({ touch: 0, tablet: 0, monitors: [] })
  property var rotationTargets: []

  signal stateUpdated()
  signal configUpdated(string path)

  function tr(key, fallback) {
    var language = String(cfg("general.language", "system"))
    if (language === "system") language = String(Quickshell.env("LANG") || "en")
    return I18n.text(language, key, fallback)
  }

  function cfg(path, fallback) {
    return Config.get(root.config, path, fallback)
  }

  function sourcePath(relative) {
    var base = root.pluginRoot
    if (!base && root.manifest && root.manifest.__sourceDir) base = String(root.manifest.__sourceDir)
    if (!base) {
      var url = String(Qt.resolvedUrl("../"))
      base = url.indexOf("file://") === 0 ? url.substring(7) : url
    }
    return base.replace(/\/$/, "") + "/" + relative
  }

  function reloadPaths() {
    root.pluginRoot = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : root.pluginRoot
    root.captureScript = root.sourcePath("input/clipboard-capture.sh")
    forceQuitTermProcess.command = ["bash", root.sourcePath("input/force-quit.sh")]
    forceQuitKillProcess.command = ["bash", root.sourcePath("input/force-quit.sh")]
  }

  function refreshIntegrations() {
    if (root.shell && typeof root.shell.firstPartyServiceFor === "function")
      root.notificationService = root.cfg("notifications.enabled", true) ? root.shell.firstPartyServiceFor("omarchy.notifications") : null
  }

  function refreshEffectBackend() {
    if (!effectsInfoProcess.running) effectsInfoProcess.running = true
  }

  function previewRequested() {
    if (root.cfg("altTab.livePreview", "auto") === "never" || root.safeMode === true) return false
    if (root.systemState.batteryState === "discharging" && root.cfg("performance.disableOnBattery", true) === true) return false
    return true
  }

  function previewBudgetAllows(surface, ordinal) {
    if (!root.previewRequested()) return false
    var context = root.performanceContext()
    if (context.fullscreen && context.disableOnFullscreen) return false
    var limit = Math.max(1, Math.min(5, Math.floor(Number(root.cfg("altTab.previewStreams", 3)))))
    if (context.batterySaver) limit = 1
    if (String(surface || "") === "dock") limit = Math.min(limit, 2)
    if (String(surface || "") === "overview") limit = Math.min(limit, 3)
    return Number(ordinal) >= 0 && Number(ordinal) < limit
  }

  function reportLivePreview(key, available) {
    var id = String(key || "")
    if (!id) return
    var reports = {}
    for (var existing in root.livePreviewReports) reports[existing] = root.livePreviewReports[existing]
    var value = available === true
    if (reports[id] === value) return
    reports[id] = value
    var active = 0
    var any = false
    for (var report in reports) {
      if (reports[report] === true) { active++; any = true }
    }
    root.livePreviewReports = reports
    root.livePreviewState = {
      available: any,
      backend: "quickshell-screencopy",
      protocol: "hyprland-toplevel-export-v1",
      activeStreams: active,
      reason: any ? "compositor-owned live stream" : "waiting for compositor-owned ScreencopyView content"
    }
    var backend = {}
    for (var field in root.effectBackend) backend[field] = root.effectBackend[field]
    backend.livePreviewAvailable = any
    backend.livePreviewBackend = root.livePreviewState.backend
    backend.livePreviewProtocol = root.livePreviewState.protocol
    backend.livePreviewReason = root.livePreviewState.reason
    root.effectBackend = backend
    root.stateRevision++
    root.stateUpdated()
  }

  function activeClient() {
    var list = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < list.length; i++) if (list[i] && (list[i].focused === true || Number(list[i].focusHistoryID) === 0)) return list[i]
    return list.length > 0 ? list[0] : {}
  }

  function fullscreenActive() {
    var list = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < list.length; i++) if (list[i] && (list[i].fullscreen === true || Number(list[i].fullscreen) > 0)) return true
    return false
  }

  function performanceContext() {
    var performance = root.cfg("performance", {})
    var batteryState = String(root.systemState.batteryState || "unknown").toLowerCase()
    var batterySaver = performance.disableOnBattery !== false && batteryState === "discharging"
    return {
      batterySaver: batterySaver,
      fullscreen: root.fullscreenActive(),
      disableOnFullscreen: performance.disableOnFullscreen !== false,
      highGpuThreshold: Number(performance.highGpuThreshold || 0.85),
      reducedMotion: root.cfg("general.reduceMotion", false) === true || root.cfg("animations.reducedMotion", false) === true,
      reduceBlurWithMotion: root.cfg("blur.reduceBlurWithMotion", true) !== false,
      backendAvailable: root.effectBackend.layerRulesAvailable === true && root.safeMode !== true
    }
  }

  function appRuleDecision() {
    var rules = root.cfg("applicationRules.rules", [])
    if (root.cfg("applicationRules.enabled", true) === false) rules = []
    return AppRulesModel.decision(rules, root.activeClient(), { inputKind: root.lastInput })
  }

  function surfaceBlur(surface) {
    var result = EffectsModel.effectiveBlur(root.cfg("blur", {}), String(surface || "settings"), root.performanceContext())
    var decision = root.appRuleDecision()
    if (decision.disableBlur) result.enabled = false
    result.ruleDisabled = decision.disableBlur
    return result
  }

  function surfaceOpacity(surface, fallback) {
    var result = root.surfaceBlur(surface)
    return result.enabled && result.backendAvailable ? Number(result.opacity) : Number(fallback)
  }

  function surfaceBlurEnabled(surface) {
    var result = root.surfaceBlur(surface)
    return result.enabled === true && result.backendAvailable === true
  }

  function cubeState() {
    return CubeModel.state(root.cfg("cube", {}), root.effectCapabilities)
  }

  function wobblyState() {
    return WobblyModel.state(root.cfg("wobbly", {}), root.effectCapabilities, root.activeClient())
  }

  function cubeEval(action, value) {
    var state = root.cubeState()
    var expression = CubeModel.lua(action, value)
    if (!state.available || !expression) {
      root.lastError = state.reason
      return false
    }
    return root.execute(["hyprctl", "eval", expression])
  }

  function cubeToggle() { return root.cubeEval("toggle") }
  function cubeOverview(visible) { return root.cubeEval("overview", Boolean(visible)) }
  function cubeRotate(direction) { return root.cubeEval("rotate", direction) }
  function cubePitch(value) { return root.cubeEval("pitch", value) }
  function cubeWorkspace(direction) { return root.cubeEval("workspace", direction) }
  function cubeSelect(index) { return root.cubeEval("select", index) }

  function forceQuitBegin() {
    if (root.cfg("forceQuit.enabled", true) !== true) {
      root.lastError = "Force Quit is disabled in settings"
      return false
    }
    root.forceQuitState = { active: true, phase: "selecting", target: null, message: "Select a window to close" }
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function forceQuitCancel() {
    if (forceQuitTermProcess.running) forceQuitTermProcess.running = false
    if (forceQuitKillProcess.running) forceQuitKillProcess.running = false
    root.forceQuitState = { active: false, phase: "cancelled", target: null, message: "Force Quit cancelled" }
    root.stateRevision++
    root.stateUpdated()
  }

  function forceQuitSelect(window) {
    if (!root.forceQuitState.active) root.forceQuitBegin()
    var target = ForceQuitModel.target(window)
    var settings = ForceQuitModel.normalize(root.cfg("forceQuit", {}))
    if (!target.selectable || target.protectedByApp) {
      root.forceQuitState = { active: true, phase: "error", target: target, message: target.protectedReason || "Window process could not be identified safely" }
    } else {
      root.forceQuitState = { active: true, phase: "confirm", target: target, message: "Confirm closing " + target.title + " (" + settings.policy + ")" }
    }
    root.stateRevision++
    root.stateUpdated()
    return target.selectable && !target.protectedByApp
  }

  function forceQuitComplete(message) {
    root.forceQuitState = { active: true, phase: "done", target: root.forceQuitState.target, message: String(message || "Force Quit completed") }
    root.stateRevision++
    root.stateUpdated()
  }

  function updateForceQuitTerm(raw, exitCode) {
    var result = root.parseJson(raw, null)
    if (exitCode !== 0 || !result || result.ok !== true) {
      root.forceQuitState = { active: true, phase: "error", target: root.forceQuitState.target, message: "SIGTERM was not permitted for the selected process" }
    } else if (result.alive === true && ForceQuitModel.requiresKill(root.forceQuitState.effectivePolicy || "")) {
      root.forceQuitState = { active: true, phase: "kill", target: root.forceQuitState.target, effectivePolicy: root.forceQuitState.effectivePolicy, message: "The app did not exit; sending SIGKILL" }
      forceQuitKillProcess.command = ["bash", root.sourcePath("input/force-quit.sh"), "kill", String(root.forceQuitState.target.pid)]
      forceQuitKillProcess.running = true
    } else if (result.alive === true) {
      root.forceQuitComplete("SIGTERM sent; the process is still running")
    } else {
      root.forceQuitComplete("The selected process exited after SIGTERM")
    }
    root.stateRevision++
    root.stateUpdated()
  }

  function updateForceQuitKill(raw, exitCode) {
    var result = root.parseJson(raw, null)
    if (exitCode !== 0 || !result || result.ok !== true) {
      root.forceQuitState = { active: true, phase: "error", target: root.forceQuitState.target, message: "SIGKILL was not permitted for the selected process" }
    } else {
      root.forceQuitComplete(result.alive === false ? "The selected process was terminated" : "The process is still running")
    }
    root.stateRevision++
    root.stateUpdated()
  }

  function forceQuitConfirm() {
    var state = root.forceQuitState
    var target = state.target
    if (!state.active || !target || !target.window) return false
    if (target.protectedByApp && !root.cfg("forceQuit.allowProtectedOverride", false)) {
      root.forceQuitState = { active: true, phase: "error", target: target, message: "Protected session process" }
      return false
    }
    var settings = ForceQuitModel.normalize(root.cfg("forceQuit", {}))
    var effectivePolicy = settings.policy === "ask" ? "graceful-term-kill" : settings.policy
    var item = ForceQuitModel.foreign(target.window)
    if (item && typeof item.close === "function") item.close()
    if (effectivePolicy === "graceful-only" || target.pid <= 0 || !ForceQuitModel.requiresTerm(effectivePolicy)) {
      root.forceQuitComplete(target.pid > 0 ? "Close request sent to the selected window" : "Close request sent; process PID is unavailable")
      return true
    }
    root.forceQuitState = { active: true, phase: "term", target: target, effectivePolicy: effectivePolicy, message: "Waiting for the graceful close request" }
    forceQuitTermProcess.command = ["bash", root.sourcePath("input/force-quit.sh"), "term", String(target.pid), String(settings.termTimeoutMs)]
    forceQuitTermProcess.running = true
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function applyBlurRules() {
    if (!root.hyprlandAvailable || root.effectBackend.layerRulesAvailable !== true) return false
    var context = root.performanceContext()
    var rules = root.safeMode ? [] : EffectsModel.layerRules(root.cfg("blur", {}), root.effectBackend, context)
    var commands = []
    var namespaces = {}
    for (var surfaceIndex = 0; surfaceIndex < EffectsModel.SURFACES.length; surfaceIndex++) {
      var names = EffectsModel.NAMESPACE_BY_SURFACE[EffectsModel.SURFACES[surfaceIndex]] || []
      for (var nameIndex = 0; nameIndex < names.length; nameIndex++) namespaces[names[nameIndex]] = true
    }
    for (var namespace in namespaces) commands.push("keyword layerrule unset,namespace:" + namespace)
    for (var i = 0; i < rules.length; i++) if (rules[i].enabled) commands.push("keyword layerrule " + rules[i].rule)
    var signature = JSON.stringify({ rules: commands, mode: root.safeMode })
    if (signature === root.blurRuleSignature) return true
    root.blurRuleSignature = signature
    return commands.length > 0 ? root.execute(["hyprctl", "--batch", commands.join(";")]) : false
  }

  function updateEffectBackend(raw) {
    var parsed = root.parseJson(raw, null)
    if (!parsed || typeof parsed !== "object") {
      root.lastError = "Effect backend probe returned invalid state"
      return
    }
    var backend = {}
    for (var field in parsed) backend[field] = parsed[field]
    backend.livePreviewAvailable = root.livePreviewState.available === true
    backend.livePreviewBackend = root.livePreviewState.backend
    backend.livePreviewProtocol = root.livePreviewState.protocol
    backend.livePreviewReason = root.livePreviewState.reason
    root.effectBackend = backend
    root.companionState = CompanionModel.normalize(parsed.companion || {})
    root.effectCapabilities = EffectsModel.capabilityState(root.companionState.capabilities, parsed.external || {})
    if (parsed.hyprlandAvailable === true) root.hyprlandAvailable = true
    root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
    root.applyBlurRules()
    root.stateRevision++
    root.stateUpdated()
  }

  function ensureDirectories() {
    directoryProcess.command = ["mkdir", "-p", root.configDir, root.stateDir, root.stateDir + "/clipboard-images"]
    directoryProcess.running = true
  }

  function loadConfig(raw) {
    root._loadingConfig = true
    root.config = Config.load(raw)
    root.safeMode = false
    root._loadingConfig = false
    root.configReady = true
    if (root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false))
      root.stopClipboardWatchers()
    else
      root.startClipboardWatchers()
    root.detectedMode = root.computeMode()
    if (root.hyprlandAvailable) root.applyTouchIntegration()
    root.refreshRotationBackend()
    root.refreshEffectBackend()
    root.stateRevision++
    root.stateUpdated()
  }

  function saveConfig() {
    if (!root.configReady || root._loadingConfig) return
    root.config.schemaVersion = 1
    configWriteDebounce.restart()
  }

  function setConfig(path, value) {
    root.config = Config.set(root.config, path, value)
    root.saveConfig()
    root.configUpdated(String(path))
    if (String(path).indexOf("clipboard.") === 0 || String(path).indexOf("privacy.clipboard") === 0) {
      if (root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false)) root.stopClipboardWatchers()
      else root.startClipboardWatchers()
      root.pruneClipboard()
    }
    if (String(path).indexOf("general.mode") === 0 || String(path).indexOf("tabletMode.") === 0) root.detectedMode = root.computeMode()
    if (String(path).indexOf("touch.") === 0) root.applyTouchIntegration()
    if (String(path).indexOf("rotation.") === 0) root.refreshRotationBackend()
    if (String(path).indexOf("notifications.enabled") === 0) root.refreshIntegrations()
    if (String(path).indexOf("blur.") === 0 || String(path).indexOf("performance.") === 0 || String(path).indexOf("effects.") === 0 || String(path).indexOf("applicationRules.") === 0 || String(path).indexOf("animations.") === 0) {
      root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
      root.applyBlurRules()
    }
    root.stateRevision++
    root.stateUpdated()
  }

  function resetConfig() {
    root.config = Config.defaults()
    root.saveConfig()
    root.startClipboardWatchers()
    root.detectedMode = root.computeMode()
    root.refreshRotationBackend()
    root.blurRuleSignature = ""
    root.applyBlurRules()
    root.stateRevision++
    root.stateUpdated()
  }

  function applyProfile(profile) {
    var name = String(profile || "Desktop")
    var next = Config.set(root.config, "general.profile", name)
    if (name === "Tablet") {
      next = Config.set(next, "general.mode", "tablet")
      next = Config.set(next, "tabletMode.touchTarget", 52)
      next = Config.set(next, "keyboard.mode", "standard")
    } else if (name === "Stylus") {
      next = Config.set(next, "general.mode", "hybrid")
      next = Config.set(next, "stylus.enabled", true)
    } else if (name === "Performance" || name === "Battery Saver") {
      next = Config.set(next, "general.reduceMotion", true)
      next = Config.set(next, "blur.enabled", false)
      next = Config.set(next, "wobbly.enabled", false)
      next = Config.set(next, "cube.enabled", false)
    } else if (name === "GNOME-like") {
      next = Config.set(next, "general.mode", "hybrid")
      next = Config.set(next, "overview.style", "gnome")
      next = Config.set(next, "altTab.style", "gnome")
    } else {
      next = Config.set(next, "general.mode", "automatic")
    }
    root.config = next
    root.saveConfig()
    root.detectedMode = root.computeMode()
    root.stateRevision++
    root.stateUpdated()
  }

  function computeMode() {
    if (root.cfg("tabletMode.enabled", true) !== true) return "desktop"
    var requested = String(root.cfg("general.mode", "automatic"))
    if (requested !== "automatic") return requested
    if (root.lastInput === "touch" && root.cfg("tabletMode.autoFromTouch", true) === true) return "tablet"
    if (root.lastInput === "stylus" && root.cfg("tabletMode.autoFromStylus", true) === true && root.cfg("stylus.enabled", true) === true) return "tablet"
    return root.hasTouchscreen ? "hybrid" : "desktop"
  }

  function recordInput(kind) {
    var value = String(kind || "keyboard")
    if (["touch", "stylus", "mouse", "keyboard", "touchpad"].indexOf(value) < 0) value = "keyboard"
    root.lastInput = value
    root.detectedMode = root.computeMode()
    root.stateRevision++
  }

  function parseJson(text, fallback) {
    try { return JSON.parse(String(text || "")) } catch (error) { return fallback }
  }

  function refreshSystemState() {
    if (!systemStateProcess.running) systemStateProcess.running = true
  }

  function updateSystemState(raw) {
    var parsed = root.parseJson(raw, null)
    if (!parsed || typeof parsed !== "object") {
      root.lastError = "Quick Settings backend returned invalid state"
      return
    }
    var next = {}
    for (var key in parsed) next[key] = parsed[key]
    next.rotationLock = root.cfg("rotation.lock", false) === true
    next.recording = recorderProcess.running || parsed.recording === true
    next.nightLightEnabled = nightLightProcess.running || parsed.nightLightEnabled === true
    var notification = root.notificationService
    next.dndAvailable = Boolean(notification && typeof notification.setDoNotDisturb === "function")
    if (next.dndAvailable && notification && notification.doNotDisturb !== undefined)
      next.dnd = Boolean(notification.doNotDisturb)
    root.systemState = next
    root.quickState = QuickSettingsModel.stateFromSystem(next)
    root.refreshRotationBackend()
    root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
    root.applyBlurRules()
    root.stateRevision++
    root.stateUpdated()
  }

  function scanWifi() {
    if (!wifiScanProcess.running) wifiScanProcess.running = true
  }

  function updateWifiScan(raw) {
    var parsed = root.parseJson(raw, [])
    root.wifiNetworks = Array.isArray(parsed) ? parsed : []
    root.stateRevision++
    root.stateUpdated()
  }

  function scanBluetooth() {
    if (!bluetoothScanProcess.running) bluetoothScanProcess.running = true
  }

  function updateBluetoothScan(raw) {
    var parsed = root.parseJson(raw, [])
    root.bluetoothDevices = Array.isArray(parsed) ? parsed : []
    root.stateRevision++
    root.stateUpdated()
  }

  function scanAudio() {
    if (!audioScanProcess.running) audioScanProcess.running = true
  }

  function updateAudioDevices(raw) {
    var parsed = root.parseJson(raw, [])
    root.audioDevices = Array.isArray(parsed) ? parsed : []
    root.stateRevision++
    root.stateUpdated()
  }

  function setAudioDefault(kind, id) {
    var type = String(kind || "")
    var value = Math.floor(Number(id))
    var available = type === "sink" ? root.systemState.volumeAvailable : root.systemState.microphoneAvailable
    if ((type !== "sink" && type !== "source") || !isFinite(value) || value <= 0 || !available) return false
    var started = root.execute(["wpctl", "set-default", String(value)])
    if (started) systemRefresh.restart()
    return started
  }

  function connectWifi(ssid, password) {
    var network = String(ssid || "")
    if (!network || !root.systemState.wifiAvailable) return false
    var args = ["nmcli", "device", "wifi", "connect", network]
    var secret = String(password || "")
    if (secret) args.push("password", secret)
    var started = root.execute(args)
    if (started) systemRefresh.restart()
    return started
  }

  function connectBluetooth(address) {
    var mac = String(address || "")
    if (!mac || !root.systemState.bluetoothAvailable) return false
    var started = root.execute(["bluetoothctl", "connect", mac])
    if (started) systemRefresh.restart()
    return started
  }

  function disconnectBluetooth(address) {
    var mac = String(address || "")
    if (!mac || !root.systemState.bluetoothAvailable) return false
    var started = root.execute(["bluetoothctl", "disconnect", mac])
    if (started) systemRefresh.restart()
    return started
  }

  function setVolume(value) {
    if (!root.systemState.volumeAvailable) return false
    var level = Math.max(0, Math.min(150, Math.round(Number(value) * 100)))
    var started = root.execute(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", level + "%"])
    if (started) systemRefresh.restart()
    return started
  }

  function setMicrophoneVolume(value) {
    if (!root.systemState.microphoneAvailable) return false
    var level = Math.max(0, Math.min(150, Math.round(Number(value) * 100)))
    var started = root.execute(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", level + "%"])
    if (started) systemRefresh.restart()
    return started
  }

  function setBrightness(value) {
    if (!root.systemState.brightnessAvailable) return false
    var level = Math.max(0, Math.min(100, Math.round(Number(value))))
    var started = root.execute(["brightnessctl", "set", level + "%"])
    if (started) systemRefresh.restart()
    return started
  }

  function toggleAnnotation() {
    if (!root.cfg("stylus.annotation", true)) {
      root.lastError = "Annotation is disabled in stylus settings"
      return false
    }
    root.annotationVisible = !root.annotationVisible
    root.stateRevision++
    root.stateUpdated()
    return root.annotationVisible
  }

  function annotationScreenshot(copyToClipboard) {
    if (copyToClipboard) {
      Util.execDetached("grim - | wl-copy --type image/png")
      return true
    }
    Util.execDetached("mkdir -p \"$HOME/Pictures/Screenshots\" && grim \"$HOME/Pictures/Screenshots/omanome-annotation-$(date +%Y%m%d-%H%M%S).png\"")
    return true
  }

  function setDoNotDisturb(value) {
    var notification = root.notificationService
    if (!notification || typeof notification.setDoNotDisturb !== "function") {
      root.lastError = "Do-not-disturb backend unavailable"
      return false
    }
    notification.setDoNotDisturb(Boolean(value))
    root.setConfig("notifications.doNotDisturb", Boolean(value))
    root.refreshSystemState()
    return true
  }

  function toggleNotificationMute(app) {
    var name = String(app || "")
    if (!name) return false
    var list = root.cfg("notifications.perAppMute", [])
    list = Array.isArray(list) ? list.slice() : []
    var index = list.indexOf(name)
    if (index >= 0) list.splice(index, 1)
    else list.push(name)
    root.setConfig("notifications.perAppMute", list)
    return true
  }

  function rotationTransformFor(value) {
    var name = String(value || "normal").toLowerCase()
    if (name === "right-up" || name === "portrait") return 1
    if (name === "bottom-up" || name === "landscape-flipped") return 2
    if (name === "left-up" || name === "portrait-flipped") return 3
    return 0
  }

  function rotationDeviceOutput(device) {
    var item = device || {}
    var value = item.output || item.mappedOutput || item.mapped_output || item.belongsTo || item.belongs_to || ""
    if (value && typeof value === "object") value = value.name || value.id || ""
    return String(value || "")
  }

  function rotationTargetMonitors() {
    var outputs = Array.isArray(root.monitors) ? root.monitors : []
    if (outputs.length === 0) return []
    var source = root.devices || {}
    var groups = [source.touch, source.touchDevices, source.touchdevices, source.tablets, source.tabletTools, source.tablettools]
    var mappedNames = []
    for (var g = 0; g < groups.length; g++) {
      var group = Array.isArray(groups[g]) ? groups[g] : []
      for (var i = 0; i < group.length; i++) {
        var mapped = rotationDeviceOutput(group[i])
        if (mapped && mappedNames.indexOf(mapped) < 0) mappedNames.push(mapped)
      }
    }
    var mappedTargets = []
    for (var m = 0; m < outputs.length; m++) {
      var outputName = String(outputs[m] && outputs[m].name || "")
      if (outputName && mappedNames.indexOf(outputName) >= 0) mappedTargets.push(outputs[m])
    }
    if (mappedTargets.length > 0) return mappedTargets
    var focused = outputs.filter(function(item) { return item && (item.focused === true || item.active === true) })
    if (focused.length > 0) return focused
    var primary = outputs.filter(function(item) { return item && item.primary === true })
    if (primary.length > 0) return primary.slice(0, 1)
    return outputs.slice(0, 1)
  }

  function rotationMonitorState(monitors) {
    var result = []
    var list = Array.isArray(monitors) ? monitors : []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var name = String(item.name || "")
      if (!name) continue
      var transform = Number(item.transform)
      if (!isFinite(transform) || transform < 0 || transform > 3) transform = root.rotationTransform
      result.push({ name: name.replace(/[;,]/g, ""), transform: Math.floor(transform) })
    }
    return result
  }

  function rotationBatch(value, monitorStates) {
    var commands = []
    if (root.cfg("rotation.transformTouch", true))
      commands.push("keyword input:touchdevice:transform " + String(value))
    if (root.cfg("rotation.transformStylus", true))
      commands.push("keyword input:tablet:transform " + String(value))
    var list = Array.isArray(monitorStates) ? monitorStates : []
    for (var i = 0; i < list.length; i++) {
      var name = String(list[i] && list[i].name || "").replace(/[;,]/g, "")
      if (name) commands.push("keyword monitor " + name + ",transform," + String(value))
    }
    return commands.join(";")
  }

  function rotationRollbackBatch() {
    var previous = root.rotationRollback || {}
    var commands = []
    if (root.cfg("rotation.transformTouch", true))
      commands.push("keyword input:touchdevice:transform " + String(Number(previous.touch) || 0))
    if (root.cfg("rotation.transformStylus", true))
      commands.push("keyword input:tablet:transform " + String(Number(previous.tablet) || 0))
    var monitors = Array.isArray(previous.monitors) ? previous.monitors : []
    for (var i = 0; i < monitors.length; i++) {
      var item = monitors[i] || {}
      var name = String(item.name || "").replace(/[;,]/g, "")
      if (name) commands.push("keyword monitor " + name + ",transform," + String(Number(item.transform) || 0))
    }
    return commands.join(";")
  }

  function finishRotation(success) {
    if (success) {
      root.rotationTransform = root.pendingRotationTransform
      root.lastError = ""
    } else {
      root.rotationTransform = Number(root.rotationRollback.previous) || root.rotationTransform
      root.lastError = "Rotation transform failed; previous monitor and input transforms were restored"
    }
    root.pendingRotationTransform = -1
    root.rotationTargets = []
    root.stateRevision++
    root.stateUpdated()
    if (root.queuedRotationTransform >= 0) {
      var queued = root.queuedRotationTransform
      root.queuedRotationTransform = -1
      Qt.callLater(function() { root.applyRotation(queued) })
    }
  }

  function applyRotation(transform) {
    if (!root.hyprlandAvailable || !root.systemState.rotationAvailable) return false
    var value = Math.max(0, Math.min(3, Math.floor(Number(transform))))
    if (rotationApplyProcess.running || rotationRollbackProcess.running) {
      root.queuedRotationTransform = value
      return false
    }
    var targets = root.rotationTargetMonitors()
    var states = root.rotationMonitorState(targets)
    if (states.length === 0) {
      root.lastError = "Rotation requires a dynamic monitor target"
      return false
    }
    var command = root.rotationBatch(value, states)
    if (!command) return false
    root.rotationRollback = {
      previous: root.rotationTransform,
      touch: Number(root.systemState.touchTransform) || 0,
      tablet: Number(root.systemState.tabletTransform) || 0,
      monitors: states
    }
    root.rotationTargets = states.map(function(item) { return item.name })
    root.pendingRotationTransform = value
    rotationApplyProcess.command = ["hyprctl", "--batch", command]
    rotationApplyProcess.running = true
    return true
  }

  function updateOrientation(line) {
    var value = String(line || "").toLowerCase()
    var next = ""
    if (value.indexOf("right-up") >= 0) next = "right-up"
    else if (value.indexOf("left-up") >= 0) next = "left-up"
    else if (value.indexOf("bottom-up") >= 0) next = "bottom-up"
    else if (value.indexOf("normal") >= 0) next = "normal"
    if (!next) return
    root.orientation = next
    if (root.cfg("rotation.orientation", "auto") === "auto" && !root.cfg("rotation.lock", false))
      root.applyRotation(root.rotationTransformFor(next))
  }

  function setRotationOrientation(value) {
    var next = String(value || "auto").toLowerCase()
    var allowed = ["auto", "landscape", "portrait", "landscape-flipped", "portrait-flipped"]
    if (allowed.indexOf(next) < 0) return false
    if (next === "auto" && !root.systemState.rotationSensorAvailable) {
      root.lastError = "Auto rotation requires monitor-sensor or iio-sensor-proxy D-Bus"
      return false
    }
    root.setConfig("rotation.orientation", next)
    if (next !== "auto") {
      root.orientation = next
      return root.applyRotation(root.rotationTransformFor(next))
    }
    root.refreshRotationBackend()
    return true
  }

  function refreshRotationBackend() {
    if (!root.configReady || !root.cfg("rotation.enabled", true)) {
      if (rotationProcess.running) rotationProcess.running = false
      return
    }
    var automatic = root.cfg("rotation.orientation", "auto") === "auto"
    var available = root.systemState.rotationSensorAvailable === true
    if (automatic && available && !root.cfg("rotation.lock", false)) {
      if (!rotationProcess.running) rotationProcess.running = true
    } else if (rotationProcess.running) {
      rotationProcess.running = false
    }
  }

  function refreshDevices() {
    if (!devicesProcess.running) devicesProcess.running = true
    if (!monitorsProcess.running) monitorsProcess.running = true
    if (!clientsProcess.running) clientsProcess.running = true
  }

  function updateDevices(raw) {
    var parsed = parseJson(raw, {})
    root.devices = parsed
    var touches = []
    var styluses = []
    var groups = [
      { items: parsed.touch, role: "touch" },
      { items: parsed.touchDevices, role: "touch" },
      { items: parsed.touchdevices, role: "touch" },
      { items: parsed.tablets, role: "tablet" },
      { items: parsed.tabletTools, role: "tablet-tool" },
      { items: parsed.tablettools, role: "tablet-tool" }
    ]
    for (var g = 0; g < groups.length; g++) {
      var group = Array.isArray(groups[g].items) ? groups[g].items : []
      for (var i = 0; i < group.length; i++) {
        var item = group[i] || {}
        if (groups[g].role === "touch" && StylusModel.isTouchscreen(item, groups[g].role)) touches.push(item)
        if (StylusModel.isStylus(item, groups[g].role)) styluses.push(item)
      }
    }
    root.hasTouchscreen = touches.length > 0
    root.stylusDevices = styluses
    root.hasStylus = styluses.length > 0
    root.keyboardDevices = StylusModel.classifyKeyboards(parsed.keyboards)
    root.hasPhysicalKeyboard = root.keyboardDevices.length > 0
    root.detectedMode = root.computeMode()
    root.stateRevision++
    root.stateUpdated()
  }

  function updateMonitors(raw) {
    root.monitors = parseJson(raw, [])
    root.stateRevision++
    root.stateUpdated()
  }

  function updateClients(raw) {
    root.clients = parseJson(raw, [])
    if (root.hyprlandAvailable) root.applyTouchIntegration()
    root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
    root.applyBlurRules()
    root.stateRevision++
    root.stateUpdated()
  }

  function statusObject() {
    return {
      version: root.manifest ? String(root.manifest.version || "0.5.0") : "0.5.0",
      quickshell: String(Quickshell.env("QUICKSHELL_VERSION") || "host-provided"),
      service: "ready",
      safeMode: root.safeMode,
      mode: root.detectedMode,
      requestedMode: root.cfg("general.mode", "automatic"),
      lastInput: root.lastInput,
      hasTouchscreen: root.hasTouchscreen,
      hasStylus: root.hasStylus,
      stylusCount: root.stylusDevices.length,
      physicalKeyboard: root.hasPhysicalKeyboard,
      physicalKeyboardCount: root.keyboardDevices.length,
      touch: {
        workspaceSwipe: TouchModel.workspaceSwipeEnabled(root.cfg("touch", {}), root.clients),
        fullscreenConflict: TouchModel.shouldDisableWorkspaceSwipe(root.clients, root.cfg("touch", {})),
        mouseTarget: TouchModel.targetSize(root.cfg("tabletMode", {}), "mouse"),
        touchTarget: TouchModel.targetSize({ touchTarget: root.cfg("tabletMode.touchTarget", 48), largeUi: root.cfg("general.largeUi", false) }, "touch"),
        stylusTarget: TouchModel.targetSize({ touchTarget: root.cfg("tabletMode.touchTarget", 48) }, "stylus")
      },
      hyprland: root.hyprlandAvailable,
      wtype: root.wtypeAvailable,
      inputBackend: root.inputBackendAvailable,
      rotation: {
        available: root.systemState.rotationAvailable === true,
        sensor: root.systemState.rotationSensorAvailable === true,
        sensorBackend: String(root.systemState.rotationSensorBackend || "manual"),
        dbus: root.systemState.rotationDbusAvailable === true,
        accelerometer: root.systemState.rotationAccelerometerAvailable === true,
        targets: root.rotationTargets.slice(),
        orientation: root.orientation,
        locked: root.cfg("rotation.lock", false) === true
      },
      configPath: root.configPath,
      clipboardEntries: root.clipboardHistory.length,
      effects: {
        blur: root.effectBackend.layerRulesAvailable === true,
        livePreview: root.livePreviewState.available === true,
        wobblyWindows: root.effectCapabilities.wobblyWindows === true,
        desktopCube: root.effectCapabilities.desktopCube === true,
        desktopCubeBackend: String(root.effectCapabilities.desktopCubeBackend || "none"),
        companion: root.companionState,
        backend: root.effectBackend.backend || "none",
        reason: root.livePreviewState.reason || root.companionState.reason || "Effect backend unavailable"
      },
      wobbly: root.wobblyState(),
      cube: root.cubeState(),
      forceQuit: root.forceQuitState,
      performance: root.performanceState,
      preview: {
        available: root.livePreviewState.available === true,
        backend: root.livePreviewState.backend,
        protocol: root.livePreviewState.protocol,
        activeStreams: root.livePreviewState.activeStreams,
        reason: root.livePreviewState.reason
      }
    }
  }

  function statusJson() {
    return JSON.stringify(root.statusObject())
  }

  function open(view) {
    if (root.shell && root.manifest && typeof root.shell.summon === "function")
      return root.shell.summon(String(root.manifest.id), JSON.stringify({ view: String(view || "overview") }))
    return false
  }

  function toggle(view) {
    if (root.shell && root.manifest && typeof root.shell.toggle === "function")
      return root.shell.toggle(String(root.manifest.id), JSON.stringify({ view: String(view || "overview") }))
    return false
  }

  function execute(argv) {
    var command = Array.isArray(argv) ? argv : []
    if (command.length === 0) return false
    Util.execArgv(command)
    return true
  }

  function dispatch(action) {
    return root.execute(["hyprctl", "dispatch"].concat(String(action || "").split(" ")))
  }

  function launchApp(desktopId) {
    var id = String(desktopId || "").replace(/\.desktop$/, "")
    if (!id) return false
    root.rememberRecentApp(id)
    Util.execArgv(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
    return true
  }

  function listConfig(path) {
    var value = root.cfg(path, [])
    return Array.isArray(value) ? value.slice() : []
  }

  function setListMembership(path, value, enabled) {
    var id = String(value || "").replace(/\.desktop$/, "")
    if (!id) return false
    var list = listConfig(path)
    var index = list.indexOf(id)
    if (enabled && index < 0) list.push(id)
    if (!enabled && index >= 0) list.splice(index, 1)
    root.setConfig(path, list)
    return true
  }

  function isFavoriteApp(id) {
    return listConfig("launcher.favorites").indexOf(String(id || "").replace(/\.desktop$/, "")) >= 0
  }

  function toggleFavoriteApp(id) {
    var key = String(id || "").replace(/\.desktop$/, "")
    return setListMembership("launcher.favorites", key, !root.isFavoriteApp(key))
  }

  function rememberRecentApp(id) {
    var key = String(id || "").replace(/\.desktop$/, "")
    if (!key) return
    var recent = listConfig("launcher.recentApplications").filter(function(item) { return item !== key })
    recent.unshift(key)
    root.setConfig("launcher.recentApplications", recent.slice(0, 24))
  }

  function moveWindowToWorkspace(window, workspaceId) {
    var id = Math.max(1, Math.floor(Number(workspaceId || 1)))
    var address = window && window.address ? String(window.address) : ""
    var request = "movetoworkspace " + id
    if (address) request += ",address:" + address
    return root.dispatch(request)
  }

  function iconPath(icon) {
    var value = String(icon || "application-x-executable")
    if (value.indexOf("/") >= 0 || value.indexOf("file://") === 0) return value
    return Quickshell.iconPath(value, true)
  }

  function keyName(key) {
    var value = String(key || "")
    if (value === "Backspace") return "BackSpace"
    if (value === "Enter") return "Return"
    if (value === "Space") return "space"
    if (value === "Tab") return "Tab"
    if (value === "Esc") return "Escape"
    if (value === "Caps") return "Caps_Lock"
    if (value === "Control") return "Control_L"
    if (value === "Alt") return "Alt_L"
    if (value === "Super") return "Super_L"
    if (value === "←") return "Left"
    if (value === "↑") return "Up"
    if (value === "↓") return "Down"
    if (value === "→") return "Right"
    if (value === "PageUp") return "Page_Up"
    if (value === "PageDown") return "Page_Down"
    return value
  }

  function sendKey(key, shifted) {
    if (!root.wtypeAvailable || root.cfg("keyboard.enabled", true) !== true) return false
    var value = String(key || "")
    var named = keyName(value)
    if (value.length === 1 && !shifted) return root.execute(["wtype", "--", value])
    if (value.length === 1 && shifted) return root.typeText(value.toUpperCase())
    return root.execute(["wtype", "-k", named])
  }

  function sendModifiedKey(key, modifiers) {
    if (!root.wtypeAvailable || root.cfg("keyboard.enabled", true) !== true) return false
    var value = String(key || "")
    if (!value) return false
    var args = ["wtype"]
    var active = Array.isArray(modifiers) ? modifiers : []
    for (var i = 0; i < active.length; i++) {
      var modifier = String(active[i] || "")
      if (modifier) args.push("-M", modifier)
    }
    if (value.length === 1 && value.charCodeAt(0) < 128) args.push("-k", root.keyName(value))
    else args.push("--", value)
    for (var j = active.length - 1; j >= 0; j--) {
      var release = String(active[j] || "")
      if (release) args.push("-m", release)
    }
    return root.execute(args)
  }

  function typeText(text) {
    if (!root.wtypeAvailable || root.cfg("keyboard.enabled", true) !== true) return false
    var value = String(text || "")
    if (!value) return false
    return root.execute(["wtype", "--", value])
  }

  function saveClipboard() {
    if (!root.configReady || root.cfg("clipboard.persist", true) === false) return
    var settings = root.cfg("clipboard", {})
    clipboardFile.setText(JSON.stringify(ClipboardModel.persistable(root.clipboardHistory, settings), null, 2) + "\n")
  }

  function clipboardSettings() {
    return root.cfg("clipboard", {})
  }

  function clipboardSourceApp() {
    var client = root.activeClient() || {}
    return String(client.appId || client.class || client.initialClass || client.initial_class || "")
  }

  function pruneClipboard() {
    var next = ClipboardModel.prune(root.clipboardHistory, root.clipboardSettings())
    if (JSON.stringify(next) === JSON.stringify(root.clipboardHistory)) return false
    root.clipboardHistory = next
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function loadClipboard(raw) {
    var result = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) {
        for (var i = 0; i < parsed.length; i++) {
          var item = ClipboardModel.normalize(parsed[i])
          if (item) result.push(item)
        }
      }
    } catch (error) {
      result = []
    }
    root.clipboardHistory = ClipboardModel.prune(result, root.clipboardSettings())
    root.stateRevision++
    root.stateUpdated()
  }

  function addClipboardJson(line) {
    if (root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false)) return
    var entry = ClipboardModel.parse(line)
    if (!entry) return
    var sourceApp = root.clipboardSourceApp()
    if (ClipboardModel.excludedApp(sourceApp, root.cfg("clipboard.excludedApps", []))) return
    entry.sourceApp = sourceApp
    if (!entry.capturedAt) entry.capturedAt = new Date().toISOString()
    root.clipboardHistory = ClipboardModel.add(root.clipboardHistory, entry, root.cfg("clipboard.historyLimit", 100))
    root.clipboardHistory = ClipboardModel.prune(root.clipboardHistory, root.clipboardSettings())
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
  }

  function clipboardEntry(index) {
    var n = Number(index)
    return n >= 0 && n < root.clipboardHistory.length ? root.clipboardHistory[n] : null
  }

  function copyClipboard(index) {
    var entry = root.clipboardEntry(index)
    if (!entry || entry.type !== "text") return false
    if (copyProcess.running) copyProcess.running = false
    copyProcess.secret = entry.text
    copyProcess.command = ["wl-copy", "--type", "text/plain"]
    copyProcess.running = true
    return true
  }

  function pasteClipboard(index) {
    if (!root.copyClipboard(index)) return false
    Qt.callLater(function() { root.sendKey("v", false) })
    return true
  }

  function clearClipboard() {
    root.clipboardHistory = []
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
  }

  function clearClipboardUnpinned() {
    var next = ClipboardModel.clearUnpinned(root.clipboardHistory)
    if (JSON.stringify(next) === JSON.stringify(root.clipboardHistory)) return false
    root.clipboardHistory = next
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function toggleClipboardPin(index) {
    root.clipboardHistory = ClipboardModel.togglePin(root.clipboardHistory, index)
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function editClipboardText(index, text) {
    var next = ClipboardModel.editText(root.clipboardHistory, index, text)
    if (JSON.stringify(next) === JSON.stringify(root.clipboardHistory)) return false
    root.clipboardHistory = next
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function setClipboardTags(index, tags) {
    var next = ClipboardModel.setTags(root.clipboardHistory, index, tags)
    if (JSON.stringify(next) === JSON.stringify(root.clipboardHistory)) return false
    root.clipboardHistory = next
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function removeClipboard(index) {
    var n = Number(index)
    if (n < 0 || n >= root.clipboardHistory.length) return false
    var next = root.clipboardHistory.slice()
    next.splice(n, 1)
    root.clipboardHistory = next
    root.saveClipboard()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function startClipboardWatchers() {
    if (!root.configReady || !root.cfg("clipboard.enabled", true) || root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false)) return
    if (!root.captureScript) root.reloadPaths()
    root.clipboardWatching = true
    if (!textWatch.running) textWatch.running = true
    if (!imageWatch.running) imageWatch.running = true
  }

  function stopClipboardWatchers() {
    root.clipboardWatching = false
    if (textWatch.running) textWatch.running = false
    if (imageWatch.running) imageWatch.running = false
    clipboardRestart.stop()
  }

  function quickAction(name) {
    var key = String(name || "")
    var current = root.quickState[key]
    var value = !Boolean(current)
    var started = false
    if (key === "wifi") {
      if (!root.systemState.wifiAvailable) { root.lastError = "Wi-Fi backend unavailable"; return false }
      started = root.execute(["nmcli", "radio", "wifi", root.systemState.wifiEnabled ? "off" : "on"])
    } else if (key === "bluetooth") {
      if (!root.systemState.bluetoothAvailable) { root.lastError = "Bluetooth backend unavailable"; return false }
      started = root.execute(["bluetoothctl", "power", root.systemState.bluetoothPowered ? "off" : "on"])
    } else if (key === "airplane") {
      if (!root.systemState.wifiAvailable) { root.lastError = "Radio backend unavailable"; return false }
      started = root.execute(["nmcli", "radio", "all", root.systemState.airplane ? "on" : "off"])
    } else if (key === "volume") {
      if (!root.systemState.volumeAvailable) { root.lastError = "Audio backend unavailable"; return false }
      started = root.execute(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", root.systemState.volumeMuted ? "0" : "1"])
    } else if (key === "microphone") {
      if (!root.systemState.microphoneAvailable) { root.lastError = "Microphone backend unavailable"; return false }
      started = root.execute(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", root.systemState.microphoneMuted ? "0" : "1"])
    } else if (key === "nightLight") {
      if (!root.systemState.nightLightAvailable) { root.lastError = "Night-light backend unavailable"; return false }
      if (nightLightProcess.running) nightLightProcess.running = false
      else { nightLightProcess.command = ["hyprsunset", "--temperature", "4000"]; nightLightProcess.running = true }
      started = true
    } else if (key === "powerProfile") {
      if (!root.systemState.powerProfileAvailable) { root.lastError = "Power-profile backend unavailable"; return false }
      var profile = QuickSettingsModel.cyclePowerProfile(root.systemState.powerProfile)
      started = root.execute(["powerprofilesctl", "set", profile])
    } else if (key === "rotationLock") {
      if (!root.systemState.rotationAvailable) { root.lastError = "Rotation backend unavailable"; return false }
      root.setConfig("rotation.lock", value)
      started = true
    } else if (key === "dnd") {
      started = root.setDoNotDisturb(value)
    } else if (key === "lock") {
      started = root.execute(["loginctl", "lock-session"])
    } else if (key === "screenshot") {
      Util.execDetached("mkdir -p \"$HOME/Pictures/Screenshots\" && grim \"$HOME/Pictures/Screenshots/omanome-$(date +%Y%m%d-%H%M%S).png\"")
      started = true
    } else if (key === "recording") {
      if (recorderProcess.running) recorderProcess.running = false
      else {
        recorderProcess.command = ["bash", "-c", "mkdir -p \"$HOME/Videos/Screencasts\"; exec wf-recorder -f \"$HOME/Videos/Screencasts/omanome-$(date +%Y%m%d-%H%M%S).mkv\""]
        recorderProcess.running = true
      }
      started = true
    } else if (key === "desktopCube" || key === "cube") {
      started = root.cubeToggle()
    } else if (key === "forceQuit") {
      started = root.forceQuitBegin()
      if (started) root.open("forcequit")
    } else {
      return false
    }
    if (started) {
      root.stateRevision++
      root.stateUpdated()
      systemRefresh.restart()
    }
    return started
  }

  function applyHyprSetting(path, value) {
    if (!root.hyprlandAvailable) return false
    return root.execute(["hyprctl", "keyword", String(path), String(value)])
  }

  function applyTouchIntegration() {
    var touchConfig = root.cfg("touch", {})
    var enabled = TouchModel.workspaceSwipeEnabled(touchConfig, root.clients)
    root.applyHyprSetting("gestures:workspace_swipe_touch", enabled)
    if (!enabled) return
    root.applyHyprSetting("gestures:workspace_swipe_distance", Math.max(1, Number(root.cfg("touch.threshold", 96))))
    root.applyHyprSetting("gestures:workspace_swipe_min_speed_to_force", Math.max(1, Math.round(Number(root.cfg("touch.velocity", 0.35)) * 100)))
    root.applyHyprSetting("gestures:workspace_swipe_touch_invert", root.cfg("touch.invert", false))
  }

  Process {
    id: directoryProcess
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "Could not create Omanome user directories"
      else initialConfigSave.restart()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: {
      root.loadConfig("")
      initialConfigSave.restart()
    }
  }

  Timer {
    id: configWriteDebounce
    interval: 180
    repeat: false
    onTriggered: configFile.setText(JSON.stringify(root.config, null, 2) + "\n")
  }

  FileView {
    id: clipboardFile
    path: root.clipboardPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadClipboard(text())
    onLoadFailed: root.loadClipboard("[]")
  }

  Process {
    id: devicesProcess
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateDevices(text) }
    onExited: function(exitCode) {
      root.hyprlandAvailable = exitCode === 0 || root.hyprlandAvailable
      if (exitCode === 0) root.applyTouchIntegration()
    }
  }

  Process {
    id: monitorsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateMonitors(text) }
  }

  Process {
    id: clientsProcess
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateClients(text) }
  }

  Process {
    id: systemStateProcess
    command: ["bash", root.sourcePath("input/system-state.sh")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateSystemState(text) }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "Quick Settings state probe failed"
    }
  }

  Process {
    id: effectsInfoProcess
    command: ["bash", root.sourcePath("input/effects-info.sh")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateEffectBackend(text) }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "Effect backend probe failed"
    }
  }

  Process {
    id: forceQuitTermProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateForceQuitTerm(text, 0) }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.updateForceQuitTerm("", exitCode)
    }
  }

  Process {
    id: forceQuitKillProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateForceQuitKill(text, 0) }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.updateForceQuitKill("", exitCode)
    }
  }

  Process {
    id: wifiScanProcess
    command: ["bash", root.sourcePath("input/wifi-scan.sh")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateWifiScan(text) }
  }

  Process {
    id: bluetoothScanProcess
    command: ["bash", root.sourcePath("input/bluetooth-scan.sh")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBluetoothScan(text) }
  }

  Process {
    id: audioScanProcess
    command: ["bash", root.sourcePath("input/audio-devices.sh")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateAudioDevices(text) }
  }

  Process {
    id: rotationApplyProcess
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.finishRotation(true)
        return
      }
      var rollback = root.rotationRollbackBatch()
      if (rollback) {
        rotationRollbackProcess.command = ["hyprctl", "--batch", rollback]
        rotationRollbackProcess.running = true
      } else {
        root.finishRotation(false)
      }
    }
  }

  Process {
    id: rotationRollbackProcess
    onExited: function() { root.finishRotation(false) }
  }

  Process {
    id: rotationProcess
    command: ["bash", root.sourcePath("input/rotation-monitor.sh")]
    stdout: SplitParser { onRead: function(line) { root.updateOrientation(line) } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.systemState.rotationSensorAvailable) root.lastError = "Rotation sensor backend stopped"
      root.refreshRotationBackend()
    }
  }

  Process {
    id: nightLightProcess
    command: ["hyprsunset", "--temperature", "4000"]
    onExited: {
      root.refreshSystemState()
    }
  }

  Process {
    id: wtypeCheck
    command: ["bash", "-c", "command -v wtype >/dev/null 2>&1"]
    onExited: function(exitCode) { root.wtypeAvailable = exitCode === 0 }
  }

  Process {
    id: textWatch
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    stdout: SplitParser { onRead: function(line) { root.addClipboardJson(line) } }
    onExited: function() { if (root.clipboardWatching) clipboardRestart.restart() }
  }

  Process {
    id: imageWatch
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    stdout: SplitParser { onRead: function(line) { root.addClipboardJson(line) } }
    onExited: function() { if (root.clipboardWatching) clipboardRestart.restart() }
  }

  Process {
    id: copyProcess
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret)
      secret = ""
    }
  }

  Process {
    id: recorderProcess
    onExited: {
      var next = {}
      for (var existing in root.quickState) next[existing] = root.quickState[existing]
      next.recording = false
      root.quickState = next
      root.stateRevision++
    }
  }

  Timer {
    id: clipboardRestart
    interval: 1000
    onTriggered: root.startClipboardWatchers()
  }

  Timer {
    id: clipboardMaintenance
    interval: 300000
    repeat: true
    running: root.configReady && root.cfg("clipboard.enabled", true)
    onTriggered: root.pruneClipboard()
  }

  Timer {
    id: integrationRefresh
    interval: 2000
    repeat: true
    running: root.notificationService === null
    onTriggered: root.refreshIntegrations()
  }

  Timer {
    id: systemRefresh
    interval: 4000
    repeat: true
    running: root.configReady
    onTriggered: root.refreshSystemState()
  }

  Timer {
    id: effectRefresh
    interval: 15000
    repeat: true
    running: root.configReady
    onTriggered: root.refreshEffectBackend()
  }

  Timer {
    id: initialConfigSave
    interval: 300
    repeat: false
    onTriggered: root.saveConfig()
  }

  Loader {
    id: dockLoader
    active: root.configReady && root.cfg("dock.enabled", true)
    source: Qt.resolvedUrl("views/Dock.qml")
    onLoaded: if (item && "service" in item) item.service = root
  }

  Loader {
    id: windowControlsLoader
    active: root.configReady && root.cfg("windowControls.enabled", true)
    source: Qt.resolvedUrl("views/WindowControls.qml")
    onLoaded: if (item && "service" in item) item.service = root
  }

  Loader {
    id: annotationLoader
    active: root.annotationVisible
    source: Qt.resolvedUrl("views/Annotation.qml")
    onLoaded: {
      if (item && "service" in item) item.service = root
    }
  }

  Timer {
    id: deviceRefresh
    interval: 10000
    repeat: true
    running: root.configReady
    onTriggered: root.refreshDevices()
  }

  IpcHandler {
    target: "io.omanome.shell"

    function ping(): string { return "ok" }
    function status(): string { return root.statusJson() }
    function open(view: string): string { return root.open(view || "overview") ? "ok" : "unavailable" }
    function toggle(view: string): string { return root.toggle(view || "overview") ? "ok" : "unavailable" }
    function input(text: string): string { return root.typeText(text) ? "ok" : "unavailable" }
    function key(keyName: string): string { return root.sendKey(keyName, false) ? "ok" : "unavailable" }
    function set(path: string, valueJson: string): string {
      try { root.setConfig(path, JSON.parse(valueJson)); return "ok" } catch (error) { return "invalid value" }
    }
    function reset(): string { root.resetConfig(); return "ok" }
    function reload(): string { root.refreshDevices(); return "ok" }
    function recordInput(kind: string): string { root.recordInput(kind); return root.detectedMode }
    function quickAction(action: string): string { return root.quickAction(action) ? "on" : "off" }
    function forceQuit(): string { return root.forceQuitBegin() ? "select" : "unavailable" }
    function cube(action: string): string {
      var value = String(action || "toggle")
      if (value === "toggle") return root.cubeToggle() ? "ok" : "unavailable"
      if (value === "left" || value === "right" || value === "previous" || value === "next") return root.cubeWorkspace(value) ? "ok" : "unavailable"
      if (value === "overview") return root.cubeOverview(true) ? "ok" : "unavailable"
      return "invalid"
    }
  }

  Component.onCompleted: {
    root.reloadPaths()
    root.refreshIntegrations()
    root.ensureDirectories()
    root.refreshDevices()
    root.refreshSystemState()
    root.refreshEffectBackend()
    wtypeCheck.running = true
  }
}
