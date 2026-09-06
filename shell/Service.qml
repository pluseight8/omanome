import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "models/Config.js" as Config
import "models/Clipboard.js" as ClipboardModel
import "models/I18n.js" as I18n
import "models/QuickSettings.js" as QuickSettingsModel
import "models/Stylus.js" as StylusModel

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
  property bool hasTouchscreen: false
  property bool hasStylus: false
  property bool hyprlandAvailable: false
  property bool wtypeAvailable: false
  property string lastInput: "keyboard"
  property string detectedMode: "desktop"
  property string lastError: ""
  property int stateRevision: 0

  property var clipboardHistory: []
  property bool clipboardWatching: false
  property string captureScript: ""
  property var notificationService: null
  property var quickState: ({ wifi: false, bluetooth: false, airplane: false, volume: true, microphone: true, nightLight: false, dnd: false, rotationLock: false, recording: false, powerProfile: "balanced" })
  property var systemState: ({ wifiAvailable: false, wifiEnabled: false, wifiConnected: false, airplane: false, wifiSsid: "", wifiSignal: -1, bluetoothAvailable: false, bluetoothPowered: false, volumeAvailable: false, volume: 0, volumeMuted: false, microphoneAvailable: false, microphoneVolume: 0, microphoneMuted: false, brightnessAvailable: false, brightness: 0, powerProfileAvailable: false, powerProfile: "balanced", batteryAvailable: false, batteryPercent: -1, batteryState: "unknown", nightLightAvailable: false, nightLightEnabled: false, dndAvailable: false, dnd: false, rotationAvailable: false, rotationLock: false, recordingAvailable: false, recording: false })
  property var wifiNetworks: []
  property var bluetoothDevices: []
  property var audioDevices: []
  property string orientation: "normal"
  property int rotationTransform: 0

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
  }

  function refreshIntegrations() {
    if (root.shell && typeof root.shell.firstPartyServiceFor === "function")
      root.notificationService = root.cfg("notifications.enabled", true) ? root.shell.firstPartyServiceFor("omarchy.notifications") : null
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
    }
    if (String(path).indexOf("general.mode") === 0 || String(path).indexOf("tabletMode.") === 0) root.detectedMode = root.computeMode()
    if (String(path).indexOf("touch.") === 0) root.applyTouchIntegration()
    if (String(path).indexOf("rotation.") === 0) root.refreshRotationBackend()
    if (String(path).indexOf("notifications.enabled") === 0) root.refreshIntegrations()
    root.stateRevision++
    root.stateUpdated()
  }

  function resetConfig() {
    root.config = Config.defaults()
    root.saveConfig()
    root.startClipboardWatchers()
    root.detectedMode = root.computeMode()
    root.refreshRotationBackend()
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
      next = Config.set(next, "effects.wobblyWindows", false)
      next = Config.set(next, "effects.desktopCube", false)
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

  function rotationTransformFor(value) {
    var name = String(value || "normal").toLowerCase()
    if (name === "right-up" || name === "portrait") return 1
    if (name === "bottom-up" || name === "landscape-flipped") return 2
    if (name === "left-up" || name === "portrait-flipped") return 3
    return 0
  }

  function applyRotation(transform) {
    if (!root.hyprlandAvailable || !root.systemState.rotationAvailable) return false
    var value = Math.max(0, Math.min(3, Math.floor(Number(transform))))
    root.rotationTransform = value
    if (root.cfg("rotation.transformTouch", true)) root.execute(["hyprctl", "keyword", "input:touchdevice:transform", String(value)])
    if (root.cfg("rotation.transformStylus", true)) root.execute(["hyprctl", "keyword", "input:tablet:transform", String(value)])
    var outputs = Array.isArray(root.monitors) ? root.monitors : []
    for (var i = 0; i < outputs.length; i++) {
      var name = String(outputs[i] && outputs[i].name || "")
      if (name) root.execute(["hyprctl", "keyword", "monitor", name + ",transform," + value])
    }
    root.stateRevision++
    root.stateUpdated()
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
      root.lastError = "Auto rotation requires monitor-sensor (iio-sensor-proxy)"
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
    var groups = [parsed.touch, parsed.touchDevices, parsed.touchdevices, parsed.tablets, parsed.tabletTools, parsed.tablettools]
    for (var g = 0; g < groups.length; g++) {
      var group = Array.isArray(groups[g]) ? groups[g] : []
      for (var i = 0; i < group.length; i++) {
        var item = group[i] || {}
        var name = String(item.name || item.device || item.identifier || "")
        var lowered = name.toLowerCase()
        if (g < 3 && StylusModel.isTouchscreen(item)) touches.push(item)
        if (StylusModel.isStylus(item) || (g >= 3 && lowered.indexOf("touchpad") < 0)) styluses.push(item)
      }
    }
    root.hasTouchscreen = touches.length > 0
    root.stylusDevices = styluses
    root.hasStylus = styluses.length > 0
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
    root.stateRevision++
    root.stateUpdated()
  }

  function statusObject() {
    return {
      version: root.manifest ? String(root.manifest.version || "0.1.0") : "0.1.0",
      service: "ready",
      safeMode: root.safeMode,
      mode: root.detectedMode,
      requestedMode: root.cfg("general.mode", "automatic"),
      lastInput: root.lastInput,
      hasTouchscreen: root.hasTouchscreen,
      hasStylus: root.hasStylus,
      stylusCount: root.stylusDevices.length,
      hyprland: root.hyprlandAvailable,
      wtype: root.wtypeAvailable,
      rotation: {
        available: root.systemState.rotationAvailable === true,
        sensor: root.systemState.rotationSensorAvailable === true,
        orientation: root.orientation,
        locked: root.cfg("rotation.lock", false) === true
      },
      configPath: root.configPath,
      clipboardEntries: root.clipboardHistory.length,
      effects: {
        wobblyWindows: false,
        desktopCube: false,
        reason: "No version-pinned Hyprland companion loaded"
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
    clipboardFile.setText(JSON.stringify(root.clipboardHistory, null, 2) + "\n")
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
    root.clipboardHistory = result.slice(0, Number(root.cfg("clipboard.historyLimit", 100)))
    root.stateRevision++
    root.stateUpdated()
  }

  function addClipboardJson(line) {
    if (root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false)) return
    var entry = ClipboardModel.parse(line)
    if (!entry) return
    root.clipboardHistory = ClipboardModel.add(root.clipboardHistory, entry, root.cfg("clipboard.historyLimit", 100))
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
    } else if (key === "forceQuit") {
      started = root.execute(["hyprctl", "kill"])
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
    var enabled = root.cfg("touch.enabled", true)
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
  }

  Component.onCompleted: {
    root.reloadPaths()
    root.refreshIntegrations()
    root.ensureDirectories()
    root.refreshDevices()
    root.refreshSystemState()
    wtypeCheck.running = true
  }
}
