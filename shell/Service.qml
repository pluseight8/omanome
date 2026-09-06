import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "models/Config.js" as Config
import "models/Clipboard.js" as ClipboardModel
import "models/I18n.js" as I18n

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
  property var quickState: ({ wifi: true, bluetooth: true, airplane: false, volume: true, microphone: true, nightLight: false, dnd: false, rotationLock: false, recording: false })

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
      root.notificationService = root.shell.firstPartyServiceFor("omarchy.notifications")
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
    root.stateRevision++
    root.stateUpdated()
  }

  function saveConfig() {
    if (!root.configReady || root._loadingConfig) return
    root.config.schemaVersion = 1
    configFile.setText(JSON.stringify(root.config, null, 2) + "\n")
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
    root.stateRevision++
    root.stateUpdated()
  }

  function resetConfig() {
    root.config = Config.defaults()
    root.saveConfig()
    root.startClipboardWatchers()
    root.detectedMode = root.computeMode()
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
    var requested = String(root.cfg("general.mode", "automatic"))
    if (requested !== "automatic") return requested
    if (root.lastInput === "touch" || root.lastInput === "stylus") return "tablet"
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
        if (g < 3 || lowered.indexOf("touch") >= 0) touches.push(item)
        if (g >= 3 || lowered.indexOf("stylus") >= 0 || lowered.indexOf("tablet") >= 0 || lowered.indexOf("pen") >= 0) styluses.push(item)
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
    Util.execArgv(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
    return true
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
    return value
  }

  function sendKey(key, shifted) {
    if (!root.wtypeAvailable) return false
    var value = String(key || "")
    var named = keyName(value)
    if (value.length === 1 && !shifted) return root.execute(["wtype", "--", value])
    if (value.length === 1 && shifted) return root.typeText(value.toUpperCase())
    return root.execute(["wtype", "-k", named])
  }

  function typeText(text) {
    if (!root.wtypeAvailable) return false
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
    var next = {}
    for (var existing in root.quickState) next[existing] = root.quickState[existing]
    var value = !Boolean(next[key])
    next[key] = value
    root.quickState = next
    if (key === "wifi") root.execute(["nmcli", "radio", "wifi", value ? "on" : "off"])
    else if (key === "bluetooth") root.execute(["bluetoothctl", "power", value ? "on" : "off"])
    else if (key === "airplane") root.execute(["nmcli", "radio", "all", value ? "on" : "off"])
    else if (key === "volume") root.execute(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", value ? "0" : "1"])
    else if (key === "microphone") root.execute(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", value ? "0" : "1"])
    else if (key === "nightLight") root.execute(["hyprctl", "hyprsunset", "temperature", value ? "4000" : "6500"])
    else if (key === "powerProfile") root.execute(["powerprofilesctl", "set", value ? "performance" : "power-saver"])
    else if (key === "rotationLock") root.setConfig("rotation.lock", value)
    else if (key === "dnd") {
      var notification = root.notificationService
      if (notification && typeof notification.setDoNotDisturb === "function") notification.setDoNotDisturb(value)
    }
    else if (key === "lock") root.execute(["loginctl", "lock-session"])
    else if (key === "screenshot") Util.execDetached("mkdir -p \"$HOME/Pictures/Screenshots\" && grim \"$HOME/Pictures/Screenshots/omanome-$(date +%Y%m%d-%H%M%S).png\"")
    else if (key === "recording") {
      if (value) {
        recorderProcess.command = ["bash", "-c", "mkdir -p \"$HOME/Videos/Screencasts\"; exec wf-recorder -f \"$HOME/Videos/Screencasts/omanome-$(date +%Y%m%d-%H%M%S).mkv\""]
        recorderProcess.running = true
      } else if (recorderProcess.running) recorderProcess.running = false
    }
    else if (key === "forceQuit") root.execute(["hyprctl", "kill"])
    root.stateRevision++
    root.stateUpdated()
    return value
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

  Timer {
    id: deviceRefresh
    interval: 5000
    repeat: true
    running: true
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
    wtypeCheck.running = true
  }
}
