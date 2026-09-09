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
import "models/StylusInput.js" as StylusInputModel
import "models/Mapping.js" as MappingModel
import "models/Lifecycle.js" as LifecycleModel
import "models/Rotation.js" as RotationModel
import "models/Touch.js" as TouchModel
import "models/InputDevices.js" as InputDevicesModel
import "models/DeviceGraph.js" as DeviceGraphModel
import "models/DeviceProfiles.js" as DeviceProfilesModel
import "models/KeyboardDevices.js" as KeyboardDevicesModel
import "models/KeyboardTransitions.js" as KeyboardTransitionsModel
import "models/Responsive.js" as ResponsiveModel
import "models/Input.js" as InputModel
import "models/OskPolicy.js" as OskPolicy
import "models/TabletMode.js" as TabletModeModel
import "models/FeatureState.js" as FeatureStateModel
import "models/AdaptiveMode.js" as AdaptiveModeModel
import "models/AdaptiveSettings.js" as AdaptiveSettingsModel
import "models/ModeTransitionCoordinator.js" as ModeTransitionModel
import "models/DockedMode.js" as DockedModeModel
import "models/ProcessPolicy.js" as ProcessPolicy
import "models/LayoutEngine.js" as LayoutEngineModel
import "models/SnapAssist.js" as SnapAssistModel
import "models/SplitView.js" as SplitViewModel
import "models/WindowMatcher.js" as WindowMatcherModel
import "models/WindowGroups.js" as WindowGroupsModel
import "models/FloatingWindows.js" as FloatingWindowsModel
import "models/GestureCoordinator.js" as GestureCoordinatorModel
import "models/MonitorRecovery.js" as MonitorRecoveryModel
import "models/TabletSwitcher.js" as TabletSwitcherModel
import "models/LayoutPersistence.js" as LayoutPersistenceModel
import "models/WorkspaceSwitcher.js" as WorkspaceSwitcherModel
import "models/MultitaskingShortcuts.js" as MultitaskingShortcutsModel

// Omanome's one shared service. It is deliberately headless: all visible
// surfaces are summoned through the existing Omarchy shell host, so Omanome
// never starts a second Quickshell instance or replaces the Omarchy bar.
Item {
  id: root

  property var shell: null
  property var panel: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string configDir: configHome + "/omanome"
  readonly property string stateDir: stateHome + "/omanome"
  readonly property string configPath: configDir + "/config.json"
  readonly property string clipboardPath: stateDir + "/clipboard.json"
  readonly property string processOwner: "io.omanome.shell"
  readonly property string processRegistryPath: stateDir + "/processes.json"
  property string pluginRoot: ""
  property bool directoriesReady: false
  property bool processRegistryReady: false
  property var ownedProcesses: []
  property var processRestartHistory: ({})
  property var processCounters: ({ spawnedTotal: 0, eventsReceived: 0, failedExits: 0, configWrites: 0, clipboardWrites: 0, helperRestarts: 0, coalescedRequests: 0, spawnWindowStartedAt: 0, spawnWindowCount: 0, subprocessRatePerMinute: 0 })
  property var clipboardRestartState: ({ consecutiveFailures: 0, startedAt: 0, blocked: false })
  readonly property var clipboardRestartPolicy: ({ initialDelayMs: 1000, maxDelayMs: 30000, maxConsecutiveFailures: 5, stableAfterMs: 30000 })
  property var rotationRestartState: ({ consecutiveFailures: 0, startedAt: 0, blocked: false })
  readonly property var rotationRestartPolicy: ({ initialDelayMs: 1000, maxDelayMs: 30000, maxConsecutiveFailures: 5, stableAfterMs: 30000 })
  property var pendingCommands: ({})
  property var inputQueue: []
  property string inputBackendPath: ""
  property string inputBackendReason: "not-probed"
  property string inputBackendProbeOutput: ""
  property var inputBackendCapabilities: ({ backend: "unavailable", virtualKeyboard: "unavailable", textInput: "unavailable", inputMethod: "unavailable" })
  property var inputBackendStatus: ({ backend: "unavailable", connected: false, textActive: false, secure: false, layout: "en", group: 0, modifiers: 0, queueDepth: 0 })
  property bool inputTextFocusActive: false
  property bool inputSecureContext: false
  property bool inputTextBackendAvailable: false
  property bool oskAutoShown: false
  property var oskPolicyState: ({ visible: false, pending: false, pendingSince: 0, reason: "not-evaluated" })
  property int inputNativePending: 0
  property int inputRequestCounter: 0
  property var inputPendingRequests: ({})
  property int inputBackendSessionCounter: 0
  property string inputBackendSession: ""
  property var inputRestartState: ({ consecutiveFailures: 0, startedAt: 0, blocked: false })
  readonly property var inputRestartPolicy: ({ initialDelayMs: 1000, maxDelayMs: 30000, maxConsecutiveFailures: 5, stableAfterMs: 30000 })

  property var config: Config.defaults()
  property bool configReady: false
  property bool _loadingConfig: false
  property string configLoadStatus: "not-loaded"
  property string configLoadError: ""
  property var configMigration: ({ applied: [], from: Config.CURRENT_SCHEMA_VERSION, to: Config.CURRENT_SCHEMA_VERSION })
  property bool configRecoveryRunning: false
  property string configRecoveryOutput: ""
  property bool safeMode: false
  property bool masterEnabled: true
  property bool suspended: false
  property string adaptiveProfile: "auto"
  // Runtime-only profile preview. It never replaces adaptive.profile and is
  // intentionally applied after the hardware-derived state is resolved.
  property var adaptivePreviewState: AdaptiveSettingsModel.emptyPreviewState()
  property var featureStates: []
  property var featureStateSummary: ({ total: 0, available: 0, active: 0, partial: false, states: [] })
  property bool shuttingDown: false
  property bool annotationVisible: false

  property var devices: []
  property var monitors: []
  property var clients: []
  property var stylusDevices: []
  property var stylusInputState: StylusInputModel.emptyState()
  property var stylusProviderState: StylusInputModel.providerState({}, stylusInputState)
  property var stylusPalmState: ({ mode: "automatic", active: false, until: 0, reason: "not-evaluated" })
  property var inputMappingState: ({ schemaVersion: 1, outputs: [], plan: [], explanation: [] })
  property var lifecycleState: LifecycleModel.emptyState()
  property var orientationState: RotationModel.emptyState()
  property bool sessionMonitorAvailable: false
  property string sessionMonitorReason: "not-started"
  property var keyboardDevices: []
  property var keyboardTransitionState: KeyboardTransitionsModel.emptyState()
  property bool hasTouchscreen: false
  property bool hasStylus: false
  property bool hasPhysicalKeyboard: false
  property bool hasDetachableKeyboard: false
  property bool hasBluetoothKeyboard: false
  property var inputDeviceState: InputDevicesModel.emptyState()
  // Device Graph is a sanitized topology view shared by diagnostics and
  // future hardware profiles. It never replaces the existing input state.
  property var deviceGraph: DeviceGraphModel.emptyState()
  property var deviceProfileStore: DeviceProfilesModel.emptyStore()
  property bool inputDeviceMonitorAvailable: false
  property string inputDeviceMonitorReason: "not-started"
  property bool tabletSwitchAvailable: false
  property bool tabletSwitchActive: false
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
  property var performanceSnapshot: ({})
  property string performanceSnapshotOutput: ""
  property bool performanceSnapshotRunning: false
  property bool wobblyBackendRequestInFlight: false
  property bool wobblyBackendSynced: true
  property bool wobblyBackendDesired: false
  property bool wobblyBackendFailed: false
  property var wobblyBackendResponse: null
  property bool wobblyConfigRequestInFlight: false
  property bool wobblyConfigSynced: false
  property bool wobblyConfigFailed: false
  property var wobblyConfigResponse: null
  property string doctorOutput: ""
  property bool doctorRunning: false
  property string updateOutput: ""
  property bool updateRunning: false
  property string rollbackOutput: ""
  property bool rollbackRunning: false
  property string recoveryOutput: ""
  property bool recoveryRunning: false
  property string backupOutput: ""
  property bool backupRunning: false
  property string supportBundleOutput: ""
  property bool supportBundleRunning: false
  property var forceQuitState: ({ active: false, phase: "idle", target: null, message: "" })
  // Multitasking state is a local model boundary. Preview and divider motion
  // never call hyprctl; only the explicit commit path queues compositor work.
  property var snapAssistState: SnapAssistModel.emptyState()
  property var splitViewState: null
  property var splitViewWindows: []
  property var multitaskingLastAction: ({ type: "none", ok: false, reason: "not-used" })
  property string multitaskingError: ""
  property int multitaskingRevision: 0
  property var multitaskingLaunch: null
  property var multitaskingLaunchTarget: null
  property var windowGroups: []
  property var windowGroupEvents: []
  property var windowGroupRestorePlan: null
  property var multitaskingPairLaunch: null
  property var floatingLastAction: ({ type: "floating-window", ok: false, reason: "not-used" })
  property int floatingRevision: 0
  property var gestureState: GestureCoordinatorModel.emptyState()
  property var gestureLastAction: ({ type: "gesture", ok: false, reason: "not-used" })
  property int gestureRevision: 0
  property var tabletSwitcherState: TabletSwitcherModel.emptyState()
  property int tabletSwitcherRevision: 0
  property var layoutPersistenceState: LayoutPersistenceModel.emptyState()
  property int layoutPersistenceRevision: 0
  property var workspaceSwitcherState: WorkspaceSwitcherModel.emptyState()
  property int workspaceSwitcherRevision: 0
  property var shortcutConflictState: MultitaskingShortcutsModel.emptyState()
  property int shortcutConflictRevision: 0
  property bool shortcutConflictRunning: false
  property int multitaskingLayoutShortcutIndex: 0
  property var monitorRecoveryState: ({ ok: true, reason: "not-used", topology: { removed: [], added: [], changed: [] }, moved: [], skipped: [], commands: [], rollback: [] })
  property int monitorRecoveryRevision: 0
  property string blurRuleSignature: ""
  property string lastInput: "keyboard"
  property string inputCandidate: ""
  property double inputCandidateSince: 0
  property var responsiveState: ResponsiveModel.context(1280, 720, 1, "keyboard", "desktop", {})
  property var tabletModeState: ({ mode: "desktop", reason: "not probed", signals: {} })
  property var postureState: ({ current: "", candidate: "", candidateSince: 0, lastChangedAt: 0, reason: "not-evaluated" })
  property var tabletProfile: ({ mode: "desktop", tabletLike: false, touchTarget: 44, dockPosition: "bottom", oskAutoShow: false, windowControls: false, gestures: false, quickSettingsDensity: "comfortable", launcherDensity: "compact", docked: false, dockedKeepTouch: false, rotationPolicy: "preserve" })
  property string detectedMode: "desktop"
  property string effectiveMode: "desktop"
  property var adaptiveState: AdaptiveModeModel.effective("auto", Config.defaults(), { baseMode: "desktop", currentMode: "desktop" })
  property var modeTransitionState: ModeTransitionModel.emptyState()
  property var modeTransitionComponents: []
  property string nextModeTransitionReason: ""
  property var dockedModeState: DockedModeModel.emptyState()
  property var componentPolicy: ({ mode: "desktop", density: "compact", touchTargetSize: 40, osk: "suppressed", oskAutoShow: false, dock: "desktop", dockReveal: true, gestures: "conservative", windowControls: "optional", snapAssist: true, splitView: true, rotation: "preserve", quickSettings: "compact", overview: "compact", launcher: "compact", notificationPopups: true, notificationDensity: "compact", effects: "normal", previews: true, backgroundWork: "normal", animations: "enabled", animationPreset: "smooth", reason: "desktop mode" })
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
  property bool rotationAbortRequested: false
  property string rotationAbortReason: ""
  property bool rotationRollbackConfirmed: false

  signal stateUpdated()
  signal configUpdated(string path)
  signal gestureActionRequested(string action)

  function tr(key, fallback) {
    var language = String(cfg("general.language", "system"))
    if (language === "system") language = String(Quickshell.env("LANG") || "en")
    return I18n.text(language, key, fallback)
  }

  function cfg(path, fallback) {
    return Config.get(root.config, path, fallback)
  }

  // Master OFF and Suspend are runtime policies, not uninstall operations.
  // Keep this predicate in the service so every enhancement backend shares the
  // same fail-closed boundary while the status/control surfaces remain alive.
  function enhancementsActive() {
    return !root.shuttingDown && root.masterEnabled && !root.suspended && !root.safeMode
  }

  function featureCapabilities() {
    var devices = root.inputDeviceState && Array.isArray(root.inputDeviceState.devices) ? root.inputDeviceState.devices : []
    var touchpad = false
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && (devices[i].role === "touchpad" || devices[i].role === "trackpad")) {
        touchpad = true
        break
      }
    }
    return {
      touchscreen: root.hasTouchscreen,
      touchpad: touchpad,
      stylus: root.hasStylus,
      tabletSwitch: root.tabletSwitchAvailable,
      rotation: root.systemState && root.systemState.rotationAvailable === true,
      osk: root.inputTextBackendAvailable || root.wtypeAvailable,
      textInput: root.inputTextBackendAvailable || root.wtypeAvailable,
      effects: root.effectBackend && (root.effectBackend.layerRulesAvailable === true || root.companionState.loaded === true)
    }
  }

  function adaptiveSignals() {
    var signals = InputDevicesModel.postureSignals(root.devices, root.inputDeviceState, root.lastInput)
    signals.stylus = root.hasStylus && root.cfg("stylus.enabled", true) === true
    signals.orientation = root.orientation
    signals.monitorInventory = DockedModeModel.inventory(root.monitors)
    signals.externalMonitor = signals.monitorInventory.externalMonitor === true
    signals.externalMonitorCount = signals.monitorInventory.externalCount
    signals.monitorCount = signals.monitorInventory.monitorCount
    var keyboard = root.keyboardModeSignals()
    signals.physicalKeyboard = keyboard.physicalKeyboard
    signals.detachableKeyboard = keyboard.detachableKeyboard
    signals.bluetoothKeyboard = keyboard.bluetoothKeyboard
    signals.externalKeyboard = keyboard.externalKeyboard
    signals.keyboardCount = keyboard.keyboardCount
    signals.keyboardStable = keyboard.keyboardStable
    signals.keyboardPending = keyboard.keyboardPending
    return signals
  }

  function observeDockedMode(reason) {
    var adaptive = root.cfg("adaptive", {})
    var observed = DockedModeModel.observe(root.dockedModeState, root.adaptiveSignals(), root.config, {
      selectedProfile: root.adaptiveProfile,
      adaptiveEnabled: adaptive.enabled !== false,
      automaticTransitions: adaptive.automaticTransitions !== false,
      autoMode: root.detectedMode,
      reason: String(reason || "adaptive-signal")
    }, Date.now())
    root.dockedModeState = observed.state
    if (observed.pending) {
      dockedModeTimer.interval = Math.max(80, Number(observed.delayMs || 440))
      dockedModeTimer.restart()
    } else {
      dockedModeTimer.stop()
    }
    return observed
  }

  function dockedModeSummary() {
    return DockedModeModel.summary(root.dockedModeState)
  }

  function refreshAdaptiveState() {
    var previousMode = root.effectiveMode
    var adaptive = root.cfg("adaptive", {})
    root.observeDockedMode("adaptive-refresh")
    var context = {
      baseMode: root.detectedMode,
      currentMode: root.effectiveMode,
      signals: root.adaptiveSignals(),
      dockedState: root.dockedModeState,
      activeProfile: root.adaptiveProfile,
      transitioning: (root.postureState && root.postureState.candidate !== "") || (root.modeTransitionState && root.modeTransitionState.active === true),
      adaptiveEnabled: adaptive.enabled !== false,
      automaticTransitions: adaptive.automaticTransitions !== false,
      reducedMotion: root.cfg("general.reduceMotion", false) === true || root.cfg("accessibility.reducedMotion", false) === true || root.cfg("animations.reducedMotion", false) === true
    }
    var previewState = AdaptiveSettingsModel.tickPreview(root.adaptivePreviewState, Date.now())
    var previewChanged = previewState.active !== root.adaptivePreviewState.active || previewState.profile !== root.adaptivePreviewState.profile || previewState.expiresAt !== root.adaptivePreviewState.expiresAt
    if (previewChanged) root.adaptivePreviewState = previewState
    var state = AdaptiveModeModel.effective(root.adaptiveProfile, root.config, context)
    if (previewState.active === true) {
      var preview = AdaptiveModeModel.preview(previewState.profile, root.config, context)
      state = Object.assign({}, state, { preview: true, previewProfile: preview.previewProfile, previewReason: preview.reason, componentPolicy: preview.componentPolicy })
    }
    root.adaptiveState = state
    root.effectiveMode = String(state.effectiveMode || root.detectedMode || "desktop")
    root.componentPolicy = state.componentPolicy || root.componentPolicy
    if (previousMode !== root.effectiveMode)
      root.startModeTransition(previousMode, root.effectiveMode, root.modeTransitionReason())
    else {
      root.refreshModeTransitionComponents()
      root.nextModeTransitionReason = ""
    }
    return state
  }

  function featureStateContext() {
    return {
      config: root.config,
      profile: root.adaptiveProfile,
      autoOverrides: root.adaptiveState && root.adaptiveState.autoOverrides ? root.adaptiveState.autoOverrides : {},
      componentPolicy: root.componentPolicy,
      masterEnabled: root.masterEnabled,
      suspended: root.suspended,
      safeMode: root.safeMode,
      capabilities: root.featureCapabilities(),
      compositorAvailable: root.hyprlandAvailable,
      rotationAvailable: root.systemState && root.systemState.rotationAvailable === true,
      effectsAvailable: root.effectBackend && (root.effectBackend.layerRulesAvailable === true || root.companionState.loaded === true),
      notificationsAvailable: true,
      clipboardAvailable: true,
      accessibility: {
        reducedMotion: root.cfg("accessibility.reducedMotion", false) === true || root.cfg("general.reduceMotion", false) === true,
        reduceTransparency: root.cfg("accessibility.reduceTransparency", false) === true
      }
    }
  }

  function refreshFeatureStates() {
    var summary = FeatureStateModel.summary(root.featureStateContext())
    root.featureStates = summary.states
    root.featureStateSummary = summary
    return summary
  }

  function featureState(id) {
    var name = String(id || "")
    for (var i = 0; i < root.featureStates.length; i++) {
      if (root.featureStates[i] && root.featureStates[i].id === name) return root.featureStates[i]
    }
    return FeatureStateModel.state(root.featureStateContext(), name)
  }

  function featureEnabled(id) {
    var row = root.featureState(id)
    return !!row && row.effectiveEnabled === true
  }

  function keyboardDeviceSummaries() {
    return KeyboardDevicesModel.summary(root.keyboardDevices)
  }

  function keyboardModeSignals() {
    var actual = {
      physicalKeyboard: root.hasPhysicalKeyboard,
      detachableKeyboard: root.hasDetachableKeyboard,
      bluetoothKeyboard: root.hasBluetoothKeyboard,
      externalKeyboard: root.keyboardDevices.some(function(device) { return device && device.connected === true && device.formFactorRelation !== "built-in" }),
      keyboardCount: root.keyboardDevices.filter(function(device) { return device && device.connected === true }).length,
      keyboardStable: true,
      keyboardPending: false
    }
    var state = root.keyboardTransitionState || {}
    if (state.initialized === true && state.stableSignals) {
      var stable = state.stableSignals
      actual.physicalKeyboard = stable.physicalKeyboard === true
      actual.detachableKeyboard = stable.detachableKeyboard === true
      actual.bluetoothKeyboard = stable.bluetoothKeyboard === true
      actual.externalKeyboard = stable.externalKeyboard === true
      actual.keyboardCount = Number(state.connectedCount || stable.activeCount || 0)
      actual.keyboardStable = state.modeReady !== false
      actual.keyboardPending = state.pending === true
    }
    return actual
  }

  function observeKeyboardTransition(reason) {
    var observed = KeyboardTransitionsModel.observe(root.keyboardTransitionState, root.keyboardDevices, root.config, {
      currentMode: root.effectiveMode,
      touchscreen: root.hasTouchscreen,
      posture: String(root.postureState.current || ""),
      lastInput: root.lastInput,
      reason: String(reason || "device-snapshot")
    }, Date.now())
    root.keyboardTransitionState = observed.state
    if (observed.changed && observed.event && observed.event.type && observed.event.type !== "none")
      root.nextModeTransitionReason = String(observed.event.type)
    if (observed.pending) {
      keyboardTransitionTimer.interval = Math.max(20, Number(observed.delayMs || 80))
      keyboardTransitionTimer.restart()
    } else {
      keyboardTransitionTimer.stop()
    }
    return observed
  }

  function keyboardTransitionSummary() {
    return KeyboardTransitionsModel.summary(root.keyboardTransitionState)
  }

  function modeTransitionReason() {
    if (root.nextModeTransitionReason !== "") return root.nextModeTransitionReason
    var event = root.keyboardTransitionState && root.keyboardTransitionState.event ? root.keyboardTransitionState.event : {}
    if (["keyboard-attached", "keyboard-detached", "keyboard-changed"].indexOf(String(event.type || "")) >= 0)
      return String(event.type)
    if (root.adaptiveProfile !== "auto") return "manual-profile"
    return "posture-change"
  }

  function refreshModeTransitionComponents() {
    root.modeTransitionComponents = ModeTransitionModel.allComponents(root.modeTransitionState, root.componentPolicy)
    return root.modeTransitionComponents
  }

  function startModeTransition(fromMode, toMode, reason) {
    var result = ModeTransitionModel.begin(root.modeTransitionState, fromMode, toMode, reason || root.modeTransitionReason(), Date.now(), root.config, {
      enabled: root.enhancementsActive(),
      reducedMotion: root.cfg("general.reduceMotion", false) === true || root.cfg("accessibility.reducedMotion", false) === true || root.cfg("animations.reducedMotion", false) === true,
      preset: root.cfg("adaptive.transition.animationPreset", root.cfg("animations.preset", "smooth")),
      durationMs: root.cfg("adaptive.transition.durationMs", 260)
    })
    root.modeTransitionState = result.state
    root.refreshModeTransitionComponents()
    root.nextModeTransitionReason = ""
    if (result.state.active) modeTransitionTimer.restart()
    else modeTransitionTimer.stop()
    return result
  }

  function tickModeTransition() {
    var result = ModeTransitionModel.tick(root.modeTransitionState, Date.now())
    root.modeTransitionState = result.state
    root.refreshModeTransitionComponents()
    if (!result.state.active) {
      modeTransitionTimer.stop()
      root.stateRevision++
      root.stateUpdated()
    }
    return result
  }

  function cancelModeTransition(reason) {
    var result = ModeTransitionModel.cancel(root.modeTransitionState, reason || "cancelled", Date.now())
    root.modeTransitionState = result.state
    root.refreshModeTransitionComponents()
    modeTransitionTimer.stop()
    root.stateRevision++
    root.stateUpdated()
    return result
  }

  function componentTransition(component) {
    return ModeTransitionModel.componentState(root.modeTransitionState, component, root.componentPolicy)
  }

  function modeTransitionSummary() {
    return ModeTransitionModel.summary(root.modeTransitionState)
  }

  function releaseOmanomeInput(reason) {
    // stopNativeInputBackend sends a protocol-level reset before closing the
    // single helper. EOF is also a release boundary in the helper, so both
    // the normal and the crash/teardown paths avoid stuck modifiers.
    root.cancelFallbackInput()
    root.stopNativeInputBackend(String(reason || "enhancements-disabled"))
    root.oskAutoShown = false
    root.inputTextFocusActive = false
    root.inputSecureContext = false
    if (root.panel && root.panel.opened && root.panel.activeView === "keyboard") root.panel.close()
  }

  function disableEnhancements(reason) {
    root.releaseOmanomeInput(reason)
    root.stopClipboardWatchers()
    if (deviceMonitorProcess.running) deviceMonitorProcess.running = false
    if (sessionMonitorProcess.running) sessionMonitorProcess.running = false
    if (root.gestureState && root.gestureState.phase !== "idle") root.cancelGesture(String(reason || "enhancements-disabled"))
    if (root.snapAssistState && root.snapAssistState.active === true) root.cancelSnapAssist(String(reason || "enhancements-disabled"))
    if (root.splitViewState && root.splitViewState.phase === "dragging") root.rollbackSplitView(String(reason || "enhancements-disabled"))
    root.annotationVisible = false
    root.requestWobblyBackend(false)
    root.applyTouchIntegration()
    root.applyBlurRules()
    root.refreshIntegrations()
  }

  function enableEnhancements() {
    if (!root.enhancementsActive()) return false
    root.startInputBackendProbe()
    root.startDeviceMonitor()
    root.startSessionMonitor()
    root.startClipboardWatchers()
    root.refreshIntegrations()
    root.refreshRotationBackend()
    root.refreshEffectBackend()
    root.reconcileWobblyBackend()
    root.applyTouchIntegration()
    root.reconcileOskPolicy()
    return true
  }

  function setMasterEnabled(enabled) {
    var value = enabled === true
    root.setConfig("controlCenter.masterEnabled", value)
    return root.masterEnabled === value
  }

  function setSuspended(value) {
    var next = value === true
    root.setConfig("controlCenter.suspended", next)
    return root.suspended === next
  }

  function setAdaptiveProfile(profile) {
    var value = FeatureStateModel.normalizedProfile(profile)
    if (root.adaptivePreviewState.active === true) root.cancelAdaptivePreview("profile-selected")
    root.nextModeTransitionReason = "manual-profile"
    root.setConfig("adaptive.profile", value)
    return root.adaptiveProfile === value
  }

  function adaptiveProfiles() {
    return AdaptiveSettingsModel.profiles(root.config, root.adaptiveProfile)
  }

  function adaptiveProfileDetails(profile) {
    return AdaptiveSettingsModel.profile(root.config, profile)
  }

  function adaptiveProfileComponents() {
    return AdaptiveSettingsModel.components()
  }

  function adaptiveProfileFeatures() {
    return AdaptiveSettingsModel.features()
  }

  function adaptiveProfileValue(profile, component, fallback) {
    return AdaptiveSettingsModel.behaviorValue(root.config, profile, component, fallback)
  }

  function adaptiveProfileFeature(profile, id, fallback) {
    return AdaptiveSettingsModel.featureValue(root.config, profile, id, fallback)
  }

  function adaptiveProfileFeatureConfigured(profile, id) {
    return AdaptiveSettingsModel.featureConfigured(root.config, profile, id)
  }

  function setAdaptiveComponent(profile, component, value) {
    var name = AdaptiveSettingsModel.normalizedProfile(profile)
    var key = String(component || "")
    if (!key || key.indexOf(".") >= 0 || key.indexOf("/") >= 0) return false
    return root.setConfig("adaptive.profiles." + name + ".componentBehavior." + key, value)
  }

  function setAdaptiveFeatureOverride(profile, id, value) {
    var name = AdaptiveSettingsModel.normalizedProfile(profile)
    var key = String(id || "")
    if (!key || key.indexOf(".") >= 0 || key.indexOf("/") >= 0) return false
    return root.setConfig("adaptive.profiles." + name + ".featureOverrides." + key, value === true)
  }

  function resetAdaptiveProfile(profile) {
    var name = AdaptiveSettingsModel.normalizedProfile(profile)
    if (root.adaptivePreviewState.active === true) root.cancelAdaptivePreview("profile-reset")
    return root.setConfig("adaptive.profiles." + name, AdaptiveSettingsModel.profileDefaults(name))
  }

  function adaptivePreviewSummary() {
    return AdaptiveSettingsModel.previewSummary(root.adaptivePreviewState, Date.now())
  }

  function beginAdaptivePreview(profile, durationMs) {
    if (!root.configReady || root.safeMode || root.shuttingDown) return false
    root.adaptivePreviewState = AdaptiveSettingsModel.beginPreview(root.adaptivePreviewState, profile, Date.now(), durationMs)
    adaptivePreviewTimer.interval = Math.max(500, Number(root.adaptivePreviewState.expiresAt || Date.now() + 6000) - Date.now())
    adaptivePreviewTimer.restart()
    root.updateResponsiveContext()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function cancelAdaptivePreview(reason) {
    if (root.adaptivePreviewState.active !== true) return false
    root.adaptivePreviewState = AdaptiveSettingsModel.cancelPreview(root.adaptivePreviewState, reason || "preview-cancelled")
    adaptivePreviewTimer.stop()
    root.updateResponsiveContext()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function toggleFeature(id) {
    var row = root.featureState(id)
    if (!FeatureStateModel.canToggle(row)) return false
    return root.setConfig(row.configPath, row.userEnabled !== true)
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
    deviceMonitorProcess.command = ["bash", root.sourcePath("input/device-monitor.sh")]
    sessionMonitorProcess.command = ["bash", root.sourcePath("input/session-monitor.sh")]
  }

  function inputBackendCandidates() {
    var candidates = []
    var configured = String(Quickshell.env("OMANOME_INPUT_BIN") || "")
    if (configured) candidates.push(configured)
    candidates.push(root.sourcePath("input/omanome-input/omanome-input"))
    candidates.push(root.sourcePath("input/omanome-input/target/release/omanome-input"))
    candidates.push(root.sourcePath("input/omanome-input/target/debug/omanome-input"))
    return candidates
  }

  function firstLine(value) {
    var lines = String(value || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var line = String(lines[i] || "").trim()
      if (line) return line
    }
    return ""
  }

  function startInputBackendProbe() {
    var nativePolicy = String(root.cfg("input.nativeBackend", "auto"))
    if (!root.masterEnabled || root.suspended || root.safeMode || nativePolicy === "disabled" || nativePolicy === "fallback" || root.cfg("input.safeModeDisableNative", false) === true) {
      root.inputBackendReason = "native-backend-disabled-by-policy"
      return false
    }
    if (inputBackendProbe.running) return false
    var candidates = root.inputBackendCandidates()
    if (candidates.length === 0) return false
    inputBackendProbeOutput = ""
    inputBackendProbe.command = ["bash", "-c", "for candidate in \"$@\"; do if [ -x \"$candidate\" ]; then printf '%s\\n' \"$candidate\"; exit 0; fi; done; exit 1", "omanome-input"].concat(candidates)
    inputBackendProbe.running = true
    return true
  }

  function nativeInputReady() {
    var nativePolicy = String(root.cfg("input.nativeBackend", "auto"))
    var lifecycle = root.lifecycleState || {}
    return !root.shuttingDown && root.masterEnabled && !root.suspended && !root.safeMode && lifecycle.phase !== "suspended" && lifecycle.locked !== true && nativePolicy !== "disabled" && nativePolicy !== "fallback" && inputBackendAvailable && inputBackendProcess.running && inputBackendPath !== "" && inputBackendSession !== ""
  }

  function inputDispatchAllowed() {
    var lifecycle = root.lifecycleState || {}
    return !root.shuttingDown && root.masterEnabled && !root.suspended && !root.safeMode && lifecycle.phase !== "suspended" && lifecycle.locked !== true
  }

  function cancelFallbackInput() {
    root.inputQueue = []
    if (inputProcess.running) inputProcess.running = false
  }

  function nativeInputReset() {
    if (!inputBackendProcess.running || !root.inputBackendSession || root.inputNativePending >= 256) return false
    root.inputRequestCounter++
    var requestId = root.inputRequestCounter
    var pending = {}
    for (var pendingId in root.inputPendingRequests) pending[pendingId] = root.inputPendingRequests[pendingId]
    pending[String(requestId)] = true
    root.inputPendingRequests = pending
    inputBackendProcess.write(JSON.stringify({ type: "keyboard.reset", requestId: requestId }) + "\n")
    root.inputNativePending++
    return true
  }

  function nextInputBackendSession() {
    root.inputBackendSessionCounter++
    root.inputBackendSession = String(root.inputBackendSessionCounter) + "-" + String(Date.now())
    return root.inputBackendSession
  }

  function nativeInputSend(commands) {
    if (!root.nativeInputReady()) return false
    // A native request supersedes anything queued for the one-shot fallback.
    // This boundary prevents a late fallback process from duplicating a key.
    root.cancelFallbackInput()
    var list = Array.isArray(commands) ? commands : [commands]
    if (list.length === 0 || root.inputNativePending + list.length > 256) {
      root.lastError = "Native input queue is full"
      return false
    }
    for (var i = 0; i < list.length; i++) {
      var command = list[i]
      if (!command || typeof command !== "object") return false
      var request = {}
      for (var field in command) request[field] = command[field]
      root.inputRequestCounter++
      request.requestId = root.inputRequestCounter
      var pending = {}
      for (var pendingId in root.inputPendingRequests) pending[pendingId] = root.inputPendingRequests[pendingId]
      pending[String(request.requestId)] = true
      root.inputPendingRequests = pending
      inputBackendProcess.write(JSON.stringify(request) + "\n")
    }
    root.inputNativePending += list.length
    return true
  }

  function nativeInputLanguage() {
    var configured = String(root.cfg("keyboard.layout", "auto"))
    if (configured === "ru" || configured === "en") return configured
    return String(Quickshell.env("LANG") || "en").indexOf("ru") === 0 ? "ru" : "en"
  }

  function syncNativeInputLanguage() {
    if (!root.nativeInputReady()) return false
    return root.nativeInputSend({ type: "set.language", language: root.nativeInputLanguage() })
  }

  function oskPolicySource() {
    var policy = root.componentPolicy || {}
    var keyboard = root.keyboardModeSignals()
    return {
      autoShow: root.masterEnabled && !root.suspended && !root.safeMode && root.inputTextBackendAvailable && root.featureEnabled("osk") && policy.oskAutoShow === true && root.cfg("keyboard.autoShow", true) === true,
      textFocus: root.inputTextFocusActive,
      secure: root.inputSecureContext,
      securePolicy: "allow",
      physicalKeyboard: keyboard.physicalKeyboard,
      detachableKeyboard: keyboard.detachableKeyboard,
      bluetoothKeyboard: keyboard.bluetoothKeyboard,
      lastInput: root.lastInput,
      mode: root.effectiveMode,
      posture: String(root.postureState.current || ""),
      touchscreen: root.hasTouchscreen,
      laptopSuppressAutoShow: root.cfg("tabletMode.posture.laptopSuppressAutoShow", true) === true,
      suppressOnPhysicalKeyboard: root.cfg("input.suppressOskOnPhysicalKeyboard", true) === true,
      suppressOnDetachableKeyboard: root.cfg("input.suppressOskOnDetachableKeyboard", true) === true,
      suppressOnBluetoothKeyboard: root.cfg("input.suppressOskOnBluetoothKeyboard", true) === true
    }
  }

  function shouldAutoShowOsk() {
    return OskPolicy.desired(root.oskPolicySource()).visible === true
  }

  function applyOskPolicyVisibility(visible) {
    if (visible) {
      if (root.panel && root.panel.opened) {
        root.panel.activeView = "keyboard"
        root.oskAutoShown = true
      } else if (root.open("keyboard")) {
        root.oskAutoShown = true
      }
      return
    }
    if (root.oskAutoShown && root.panel && root.panel.opened && root.panel.activeView === "keyboard") root.panel.close()
    root.oskAutoShown = false
  }

  function reconcileOskPolicy() {
    if (!root.masterEnabled || root.suspended || root.safeMode) {
      root.applyOskPolicyVisibility(false)
      root.oskPolicyState = { visible: false, pending: false, pendingSince: 0, reason: !root.masterEnabled ? "master-disabled" : (root.suspended ? "suspended" : "safe-mode") }
      return root.oskPolicyState
    }
    var decision = OskPolicy.transition(root.oskPolicySource(), root.oskPolicyState, Date.now())
    root.oskPolicyState = decision.state
    if (decision.pending) {
      oskPolicyTimer.interval = Math.max(1, decision.delayMs)
      oskPolicyTimer.restart()
    } else if (decision.changed) {
      root.applyOskPolicyVisibility(decision.state.visible)
    }
    return decision
  }

  function requestAutoOsk(show) {
    if (!show) root.inputTextFocusActive = false
    return root.reconcileOskPolicy()
  }

  function refreshStylusInputPolicy() {
    root.stylusProviderState = StylusInputModel.providerState(root.cfg("stylus", {}), root.stylusInputState)
    root.stylusPalmState = StylusInputModel.palmTransition(
      root.stylusPalmState,
      { stylusProximity: root.stylusInputState.proximity === true, stylusContact: root.stylusInputState.contact === true, touchCount: root.lastInput === "touch" ? 1 : 0 },
      Date.now(),
      { mode: root.cfg("stylus.palmRejection", "automatic") }
    )
  }

  function updateTabletEvent(parsed) {
    root.stylusInputState = StylusInputModel.applyEvent(root.stylusInputState, parsed, Date.now())
    if (["proximity-in", "tip-down", "motion"].indexOf(String(parsed.event || "")) >= 0)
      root.recordInput("stylus")
    root.refreshStylusInputPolicy()
    root.stateRevision++
    root.stateUpdated()
  }

  function updateNativeInputLine(line) {
    var parsed = root.parseJson(line, null)
    if (!parsed || typeof parsed !== "object" || String(parsed.protocol || "") !== "omanome-input") return
    var session = String(parsed.session || "")
    if (!session || !root.inputBackendSession || session !== root.inputBackendSession) return
    var kind = String(parsed.type || "")
    if (kind === "input.ack") {
      var requestId = String(parsed.requestId || "")
      if (!requestId || root.inputPendingRequests[requestId] !== true) {
        root.lastError = "Native input acknowledgement was stale"
        return
      }
      var pendingRequests = {}
      for (var pendingId in root.inputPendingRequests) {
        if (pendingId !== requestId) pendingRequests[pendingId] = root.inputPendingRequests[pendingId]
      }
      root.inputPendingRequests = pendingRequests
      root.inputNativePending = Math.max(0, root.inputNativePending - 1)
      var ackStatus = {}
      for (var ackKey in root.inputBackendStatus) ackStatus[ackKey] = root.inputBackendStatus[ackKey]
      ackStatus.queueDepth = Number(parsed.queueDepth || 0)
      root.inputBackendStatus = ackStatus
      return
    }
    if (kind === "input.capabilities") {
      var capabilities = {}
      for (var key in parsed) capabilities[key] = parsed[key]
      root.inputBackendCapabilities = capabilities
      root.inputBackendAvailable = String(parsed.backend || "") === "native-wayland" && String(parsed.virtualKeyboard || "") === "native"
      root.inputTextBackendAvailable = String(parsed.inputMethod || "") === "v2"
      if (String(parsed.tablet || "") === "v2") {
        var tabletState = {}
        for (var tabletKey in root.stylusInputState) tabletState[tabletKey] = root.stylusInputState[tabletKey]
        tabletState.backend = "native-wayland-tablet-v2"
        tabletState.available = true
        tabletState.tabletCount = Number(parsed.tabletCount || tabletState.tabletCount || 0)
        tabletState.toolCount = Number(parsed.toolCount || tabletState.toolCount || 0)
        tabletState.proximity = parsed.stylusProximity === true
        tabletState.contact = parsed.stylusContact === true
        root.stylusInputState = tabletState
        root.refreshStylusInputPolicy()
      }
      root.inputBackendReason = root.inputBackendAvailable ? "native-wayland" : String(parsed.reason || "native-capability-unavailable")
      if (root.inputBackendAvailable) root.syncNativeInputLanguage()
      root.stateRevision++
      root.stateUpdated()
      return
    }
    if (kind === "input.status") {
      var status = {}
      for (var statusKey in parsed) status[statusKey] = parsed[statusKey]
      root.inputBackendStatus = status
      root.inputBackendAvailable = String(parsed.backend || "") === "native-wayland" && String(root.inputBackendCapabilities.virtualKeyboard || "") === "native"
      root.inputTextBackendAvailable = String(root.inputBackendCapabilities.inputMethod || "") === "v2"
      root.inputTextFocusActive = parsed.textActive === true ? root.inputTextFocusActive : root.inputTextFocusActive
      root.inputSecureContext = parsed.secure === true
      root.stateRevision++
      root.stateUpdated()
      return
    }
    if (kind === "text.enter") {
      root.inputTextFocusActive = true
      root.inputSecureContext = parsed.secure === true
      root.requestAutoOsk(true)
      return
    }
    if (kind === "text.leave") {
      root.inputTextFocusActive = false
      root.inputSecureContext = false
      root.requestAutoOsk(false)
      return
    }
    if (kind === "osk.request") {
      root.requestAutoOsk(String(parsed.request || "") === "show")
      return
    }
    if (kind === "tablet.event") {
      root.updateTabletEvent(parsed)
      return
    }
    if (kind === "input.error") {
      root.inputBackendReason = String(parsed.code || "input-error")
      root.lastError = "Native input: " + root.inputBackendReason
    }
  }

  function inputBackendExited(exitCode) {
    root.processStopped("omanome-input", inputBackendProcess, exitCode)
    if (root.shuttingDown) return
    root.inputBackendAvailable = false
    root.inputTextBackendAvailable = false
    root.inputNativePending = 0
    root.inputPendingRequests = ({})
    root.inputTextFocusActive = false
    root.inputSecureContext = false
    root.inputBackendSession = ""
    root.cancelFallbackInput()
    var lifecycle = root.lifecycleState || {}
    var nativePolicy = String(root.cfg("input.nativeBackend", "auto"))
    if (!root.inputBackendPath || nativePolicy === "disabled" || nativePolicy === "fallback" || lifecycle.phase === "suspended" || lifecycle.locked === true) return
    var decision = ProcessPolicy.nextRestart(root.inputRestartState, Date.now(), root.inputRestartPolicy)
    root.inputRestartState = { consecutiveFailures: decision.consecutiveFailures, startedAt: 0, blocked: decision.blocked === true }
    if (!decision.restart) {
      root.inputBackendReason = "crash-loop-limit"
      root.lastError = "Native input backend disabled after repeated failures"
      return
    }
    root.inputBackendReason = "bounded-backoff"
    inputBackendRestart.interval = Math.max(1, decision.delayMs)
    inputBackendRestart.restart()
  }

  function startNativeInputBackend() {
    var nativePolicy = String(root.cfg("input.nativeBackend", "auto"))
    var lifecycle = root.lifecycleState || {}
    if (root.shuttingDown || !root.masterEnabled || root.suspended || root.safeMode || lifecycle.phase === "suspended" || lifecycle.locked === true || nativePolicy === "disabled" || nativePolicy === "fallback" || !root.inputBackendPath || inputBackendProcess.running || root.inputRestartState.blocked) return false
    root.nextInputBackendSession()
    inputBackendProcess.command = [root.inputBackendPath]
    inputBackendProcess.running = true
    return true
  }

  function stopNativeInputBackend(reason) {
    // Give the helper a best-effort explicit release before terminating it.
    // The helper also releases every tracked key on stdin EOF, so this remains
    // safe when suspend/compositor teardown races the write.
    root.nativeInputReset()
    if (inputBackendProcess.running) inputBackendProcess.running = false
    root.inputBackendAvailable = false
    root.inputTextBackendAvailable = false
    root.inputNativePending = 0
    root.inputPendingRequests = ({})
    root.inputTextFocusActive = false
    root.inputSecureContext = false
    root.inputBackendSession = ""
    if (reason) root.inputBackendReason = String(reason)
  }

  function ownedEnvironment(component) {
    return {
      OMANOME_OWNER: root.processOwner,
      OMANOME_COMPONENT: String(component || "unknown"),
      OMANOME_SHELL_PID: String(Quickshell.processId || "")
    }
  }

  function inputBackendEnvironment() {
    var environment = root.ownedEnvironment("omanome-input")
    environment.OMANOME_INPUT_SESSION = root.inputBackendSession
    return environment
  }

  function observerEnvironment(component) {
    var environment = root.ownedEnvironment(component)
    environment.OMANOME_ROLE = "observer"
    return environment
  }

  function requestPerformanceSnapshot() {
    if (root.shuttingDown || performanceSnapshotProcess.running) return false
    root.performanceSnapshotOutput = ""
    root.performanceSnapshot = ({})
    performanceSnapshotProcess.running = true
    return true
  }

  function updatePerformanceSnapshot(raw) {
    var parsed = root.parseJson(raw, {})
    if (!parsed || typeof parsed !== "object") return
    root.performanceSnapshot = parsed
    root.performanceSnapshotOutput = JSON.stringify(parsed, null, 2)
  }

  function finishPerformanceSnapshot(exitCode) {
    performanceSnapshotTimeout.stop()
    root.performanceSnapshotRunning = false
    if (Number(exitCode || 0) !== 0) root.lastError = "Performance snapshot failed"
  }

  function updateProcessCounter(name, delta) {
    var next = {}
    for (var key in root.processCounters) next[key] = root.processCounters[key]
    next[String(name)] = Number(next[String(name)] || 0) + Number(delta || 0)
    root.processCounters = next
  }

  function recordProcessSpawn() {
    var now = Date.now()
    var next = {}
    for (var key in root.processCounters) next[key] = root.processCounters[key]
    var windowStartedAt = Number(next.spawnWindowStartedAt || 0)
    var windowCount = Number(next.spawnWindowCount || 0)
    if (windowStartedAt <= 0 || now - windowStartedAt >= 60000) {
      windowStartedAt = now
      windowCount = 0
    }
    windowCount++
    next.spawnWindowStartedAt = windowStartedAt
    next.spawnWindowCount = windowCount
    next.subprocessRatePerMinute = Math.round(windowCount * 60000 / Math.max(1000, now - windowStartedAt) * 100) / 100
    root.processCounters = next
  }

  function processRegistryEntry(component, pid) {
    var list = Array.isArray(root.ownedProcesses) ? root.ownedProcesses : []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].component || "") === String(component || "") && Number(list[i].pid || 0) === Number(pid || 0)) return list[i]
    }
    return null
  }

  function scheduleProcessRegistryWrite() {
    if (!root.shuttingDown && root.processRegistryReady && root.directoriesReady) processRegistryWriteDebounce.restart()
  }

  function loadProcessRegistry(raw) {
    var parsed = root.parseJson(raw, {})
    var next = []
    if (parsed && typeof parsed === "object" && (!parsed.owner || String(parsed.owner) === root.processOwner)) {
      // A registry belongs to one shell process. Never resurrect stale PIDs
      // from a previous session after a normal restart or compositor reload.
      var registryShellPid = String(parsed.shellPid || "")
      var currentShellPid = String(Quickshell.processId || "")
      var sameShell = registryShellPid !== "" && currentShellPid !== "" && registryShellPid === currentShellPid
      if (sameShell) {
        var entries = Array.isArray(parsed.processes) ? parsed.processes : []
        for (var i = 0; i < entries.length; i++) {
          var item = entries[i]
          if (!item || Number(item.pid || 0) <= 0 || !item.component) continue
          next.push(item)
        }
      }
      var counters = parsed.counters && typeof parsed.counters === "object" ? parsed.counters : {}
      var mergedCounters = {}
      for (var key in root.processCounters) mergedCounters[key] = Number(counters[key] || root.processCounters[key] || 0)
      root.processCounters = mergedCounters
    }
    root.ownedProcesses = next
    root.processRegistryReady = true
    root.scheduleProcessRegistryWrite()
  }

  function persistProcessRegistry() {
    if (!root.processRegistryReady || !root.directoriesReady) return
    processRegistryFile.setText(JSON.stringify({
      schemaVersion: 1,
      owner: root.processOwner,
      shellPid: String(Quickshell.processId || ""),
      updatedAt: new Date().toISOString(),
      processes: root.ownedProcesses,
      counters: root.processCounters
    }, null, 2) + "\n")
  }

  function processStarted(component, process, purpose, persistent, restartPolicy) {
    if (root.shuttingDown) return
    var pid = Number(process && process.processId || 0)
    if (pid <= 0) return
    var name = String(component || "unknown")
    var history = {}
    for (var key in root.processRestartHistory) history[key] = root.processRestartHistory[key]
    var entry = {
      pid: pid,
      component: name,
      purpose: String(purpose || "unspecified"),
      command: ProcessPolicy.redactedCommand(process.command),
      startedAt: new Date().toISOString(),
      shellPid: String(Quickshell.processId || ""),
      restartCount: Number(history[name] || 0),
      restartPolicy: String(restartPolicy || "none"),
      persistent: persistent === true,
      owner: root.processOwner
    }
    var next = []
    var replaced = false
    for (var i = 0; i < root.ownedProcesses.length; i++) {
      var existing = root.ownedProcesses[i]
      if (String(existing.component || "") === name && Number(existing.pid || 0) === pid) {
        next.push(entry)
        replaced = true
      } else next.push(existing)
    }
    if (!replaced) next.push(entry)
    root.ownedProcesses = next
    root.updateProcessCounter("spawnedTotal", 1)
    root.recordProcessSpawn()
    root.scheduleProcessRegistryWrite()
  }

  function processStopped(component, process, exitCode) {
    if (root.shuttingDown) return
    var name = String(component || "unknown")
    var pid = Number(process && process.processId || 0)
    var next = []
    for (var i = 0; i < root.ownedProcesses.length; i++) {
      var entry = root.ownedProcesses[i]
      var sameComponent = String(entry.component || "") === name
      var samePid = pid > 0 ? Number(entry.pid || 0) === pid : sameComponent
      if (!sameComponent || !samePid) next.push(entry)
    }
    root.ownedProcesses = next
    root.updateProcessCounter("eventsReceived", 1)
    if (Number(exitCode || 0) !== 0) {
      root.updateProcessCounter("failedExits", 1)
      var history = {}
      for (var key in root.processRestartHistory) history[key] = root.processRestartHistory[key]
      history[name] = Number(history[name] || 0) + 1
      root.processRestartHistory = history
    }
    root.scheduleProcessRegistryWrite()
  }

  function clipboardWatcherExited(component, exitCode) {
    root.processStopped(component, component === "clipboard-text" ? textWatch : imageWatch, exitCode)
    if (root.shuttingDown || !root.clipboardWatching) return
    var now = Date.now()
    var decision = ProcessPolicy.nextRestart(root.clipboardRestartState, now, root.clipboardRestartPolicy)
    root.clipboardRestartState = {
      consecutiveFailures: decision.consecutiveFailures,
      startedAt: 0,
      blocked: decision.blocked === true
    }
    if (!decision.restart) {
      root.lastError = "Clipboard watcher disabled after repeated failures"
      root.updateProcessCounter("helperRestarts", 1)
      return
    }
    root.updateProcessCounter("helperRestarts", 1)
    clipboardRestart.interval = Math.max(1, decision.delayMs)
    clipboardRestart.restart()
  }

  function rotationBackendWanted() {
    if (!root.configReady || !root.enhancementsActive() || !root.cfg("rotation.enabled", true)) return false
    return root.cfg("rotation.orientation", "auto") === "auto" && root.systemState.rotationSensorAvailable === true && !root.cfg("rotation.lock", false)
  }

  function rotationMonitorExited(exitCode) {
    root.processStopped("rotation-monitor", rotationProcess, exitCode)
    if (root.shuttingDown || !root.rotationBackendWanted()) return
    var now = Date.now()
    var decision = ProcessPolicy.nextRestart(root.rotationRestartState, now, root.rotationRestartPolicy)
    root.rotationRestartState = { consecutiveFailures: decision.consecutiveFailures, startedAt: 0, blocked: decision.blocked === true }
    if (!decision.restart) {
      root.lastError = "Rotation sensor monitor disabled after repeated failures"
      return
    }
    rotationRestart.interval = Math.max(1, decision.delayMs)
    rotationRestart.restart()
  }

  function queuedCommand(command) {
    if (root.shuttingDown) return false
    var key = ProcessPolicy.coalesceKey(command)
    if (!key) return false
    var pending = {}
    for (var existing in root.pendingCommands) pending[existing] = root.pendingCommands[existing]
    pending[key] = command.slice()
    root.pendingCommands = pending
    root.updateProcessCounter("coalescedRequests", 1)
    root.scheduleProcessRegistryWrite()
    return true
  }

  function startNextCommand() {
    if (root.shuttingDown || commandProcess.running) return false
    var pending = {}
    for (var existing in root.pendingCommands) pending[existing] = root.pendingCommands[existing]
    for (var key in root.pendingCommands) {
      var next = root.pendingCommands[key]
      delete pending[key]
      root.pendingCommands = pending
      commandProcess.command = next
      commandProcess.running = true
      return true
    }
    return false
  }

  function enqueueInput(command) {
    var values = Array.isArray(command) ? command.map(function(item) { return String(item) }) : []
    if (values.length === 0) return false
    var queue = root.inputQueue.slice()
    var textInput = values[0] === "wtype" && values.length === 3 && values[1] === "--"
    if (textInput && queue.length > 0) {
      var last = queue[queue.length - 1]
      if (Array.isArray(last) && last.length === 3 && last[0] === "wtype" && last[1] === "--" && String(last[2]).length + values[2].length <= 256) {
        last = last.slice()
        last[2] = String(last[2]) + values[2]
        queue[queue.length - 1] = last
      } else queue.push(values)
    } else queue.push(values)
    if (queue.length > 64) {
      root.lastError = "Input queue is full; request was not started"
      return false
    }
    root.inputQueue = queue
    inputFlush.restart()
    return true
  }

  function flushInputQueue() {
    if (root.shuttingDown || inputProcess.running || root.inputQueue.length === 0) return false
    var queue = root.inputQueue.slice()
    var next = queue.shift()
    root.inputQueue = queue
    inputProcess.command = next
    inputProcess.running = true
    return true
  }

  function refreshIntegrations() {
    if (!root.enhancementsActive()) {
      root.notificationService = null
      integrationRefresh.stop()
      return
    }
    if (root.shell && typeof root.shell.firstPartyServiceFor === "function")
      root.notificationService = root.cfg("notifications.enabled", true) ? root.shell.firstPartyServiceFor("omarchy.notifications") : null
    if (root.notificationService === null) integrationRefresh.restart()
    else integrationRefresh.stop()
  }

  function refreshEffectBackend() {
    if (!root.shuttingDown && !effectsInfoProcess.running) effectsInfoProcess.running = true
  }

  function previewRequested() {
    if (!root.enhancementsActive() || root.cfg("effects.enabled", true) === false || root.cfg("altTab.livePreview", "auto") === "never") return false
    if (root.systemState.batteryState === "discharging" && root.cfg("performance.disableOnBattery", true) === true) return false
    return true
  }

  function previewBudgetAllows(surface, ordinal) {
    if (!root.previewRequested()) return false
    var context = root.performanceContext()
    if (context.fullscreen && context.disableOnFullscreen) return false
    var limit = Math.max(1, Math.min(5, Math.floor(Number(root.cfg("altTab.previewStreams", 3)))))
    if (root.performanceState && Number(root.performanceState.previewStreams) > 0)
      limit = Math.min(limit, Number(root.performanceState.previewStreams))
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
    var context = {
      batterySaver: batterySaver,
      fullscreen: root.fullscreenActive(),
      powerProfile: String(root.systemState.powerProfile || "unknown"),
      thermalPressure: String(root.systemState.thermalPressure || "unknown"),
      onAc: batteryState !== "discharging" && batteryState !== "unknown",
      disableOnFullscreen: performance.disableOnFullscreen !== false,
      highGpuThreshold: Number(performance.highGpuThreshold || 0.85),
      reducedMotion: root.cfg("general.reduceMotion", false) === true || root.cfg("animations.reducedMotion", false) === true,
      reduceBlurWithMotion: root.cfg("blur.reduceBlurWithMotion", true) !== false,
      safeMode: root.safeMode === true,
      backendAvailable: root.effectBackend.layerRulesAvailable === true && root.safeMode !== true && root.cfg("effects.enabled", true) !== false
    }
    context.performanceMode = PerformanceModel.mode(performance, context)
    return context
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
    if (!root.enhancementsActive()) result.enabled = false
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
    var state = CubeModel.state(root.cfg("cube", {}), root.effectCapabilities)
    if (root.cfg("effects.enabled", true) === false) {
      state.available = false
      state.enabled = false
      state.reason = "advanced compositor effects are disabled"
    }
    return state
  }

  function wobblyState() {
    var state = WobblyModel.state(root.cfg("wobbly", {}), root.effectCapabilities, root.activeClient())
    if (state.configured && !root.wobblyPolicyAllows()) {
      state.enabled = false
      state.reason = root.cfg("effects.enabled", true) === false ? "advanced compositor effects are disabled" : (root.systemState.batteryState === "discharging" ? "disabled by battery policy" : "disabled for fullscreen")
    }
    return state
  }

  function wobblyPolicyAllows() {
    if (!root.enhancementsActive() || root.cfg("effects.enabled", true) === false) return false
    var effects = root.cfg("effects", {})
    if (root.systemState.batteryState === "discharging" && effects.disableOnBattery !== false) return false
    if (root.fullscreenActive() && effects.disableOnFullscreen !== false) return false
    return true
  }

  function wobblyDesired() {
    return root.cfg("wobbly.enabled", false) === true && root.wobblyPolicyAllows()
  }

  function requestWobblyBackend(enabled) {
    var wanted = Boolean(enabled)
    root.wobblyBackendDesired = wanted
    root.wobblyBackendSynced = false
    root.wobblyBackendFailed = false
    if (!root.hyprlandAvailable || (wanted && (root.companionState.loaded !== true || root.effectCapabilities.wobblyWindows !== true))) {
      if (wanted) root.lastError = "Wobbly needs a compatible loaded omanome-hypr renderer"
      return false
    }
    if (wobblyControlProcess.running) wobblyControlProcess.running = false
    root.wobblyBackendResponse = null
    root.wobblyBackendRequestInFlight = true
    wobblyControlProcess.command = ["hyprctl", "-j", "omanome-effects", "wobbly", wanted ? "enable" : "disable"]
    wobblyControlProcess.running = true
    return true
  }

  function reconcileWobblyBackend() {
    var wanted = root.wobblyDesired()
    if (!root.hyprlandAvailable) return false
    if (wanted && (root.companionState.loaded !== true || root.effectCapabilities.wobblyWindows !== true)) return false
    if (root.wobblyBackendSynced && root.wobblyBackendDesired === wanted) return true
    if (root.wobblyBackendFailed && root.wobblyBackendDesired === wanted) return false
    return root.requestWobblyBackend(wanted)
  }

  function updateWobblyBackendResponse(raw) {
    root.wobblyBackendResponse = root.parseJson(raw, null)
  }

  function finishWobblyBackend(exitCode) {
    if (root.shuttingDown) return
    var response = root.wobblyBackendResponse
    if (exitCode !== 0 || !response || response.error) {
      root.lastError = response && response.error ? String(response.error) : "Wobbly compositor command failed"
      root.wobblyBackendSynced = false
      root.wobblyBackendFailed = true
    } else {
      root.wobblyBackendSynced = true
      root.wobblyBackendFailed = false
    }
    root.wobblyBackendRequestInFlight = false
    root.refreshEffectBackend()
    root.stateRevision++
    root.stateUpdated()
  }

  function wobblyConfigArguments() {
    function bounded(value, minimum, maximum, fallback) {
      var number = Number(value)
      if (!isFinite(number)) number = fallback
      return Math.max(minimum, Math.min(maximum, number))
    }
    var grid = Math.round(bounded(root.cfg("wobbly.gridResolution", 8), 2, 32, 8))
    var maxVertices = Math.round(bounded(root.cfg("wobbly.maxVertices", 1024), 4, 4096, 1024))
    return [
      "grid=" + grid,
      "maxVertices=" + maxVertices,
      "stiffness=" + bounded(root.cfg("wobbly.stiffness", 0.72), 0.01, 32, 0.72).toFixed(4),
      "friction=" + bounded(root.cfg("wobbly.friction", 0.78), 0, 32, 0.78).toFixed(4),
      "damping=" + bounded(root.cfg("wobbly.damping", 0.62), 0, 32, 0.62).toFixed(4),
      "mass=" + bounded(root.cfg("wobbly.mass", 1.0), 0.05, 32, 1.0).toFixed(4),
      "maxDeformation=" + bounded(root.cfg("wobbly.maxDeformation", 0.035), 0, 0.25, 0.035).toFixed(4),
      "velocityInfluence=" + bounded(root.cfg("wobbly.velocityInfluence", 0.45), 0, 4, 0.45).toFixed(4)
    ]
  }

  function requestWobblyConfig() {
    if (!root.hyprlandAvailable || root.companionState.loaded !== true || root.effectCapabilities.wobblyWindows !== true) return false
    if (wobblyConfigProcess.running) wobblyConfigProcess.running = false
    root.wobblyConfigResponse = null
    root.wobblyConfigRequestInFlight = true
    root.wobblyConfigFailed = false
    wobblyConfigProcess.command = ["hyprctl", "-j", "omanome-effects", "wobbly", "config"].concat(root.wobblyConfigArguments())
    wobblyConfigProcess.running = true
    return true
  }

  function updateWobblyConfigResponse(raw) {
    root.wobblyConfigResponse = root.parseJson(raw, null)
  }

  function finishWobblyConfig(exitCode) {
    if (root.shuttingDown) return
    var response = root.wobblyConfigResponse
    if (exitCode !== 0 || !response || response.error) {
      root.lastError = response && response.error ? String(response.error) : "Wobbly compositor configuration failed"
      root.wobblyConfigSynced = false
      root.wobblyConfigFailed = true
    } else {
      root.wobblyConfigSynced = true
      root.wobblyConfigFailed = false
    }
    root.wobblyConfigRequestInFlight = false
    root.refreshEffectBackend()
    root.stateRevision++
    root.stateUpdated()
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
    var rules = root.enhancementsActive() ? EffectsModel.layerRules(root.cfg("blur", {}), root.effectBackend, context) : []
    var commands = []
    var namespaces = {}
    for (var surfaceIndex = 0; surfaceIndex < EffectsModel.SURFACES.length; surfaceIndex++) {
      var names = EffectsModel.NAMESPACE_BY_SURFACE[EffectsModel.SURFACES[surfaceIndex]] || []
      for (var nameIndex = 0; nameIndex < names.length; nameIndex++) namespaces[names[nameIndex]] = true
    }
    for (var namespace in namespaces) commands.push("keyword layerrule unset,namespace:" + namespace)
    for (var i = 0; i < rules.length; i++) if (rules[i].enabled) commands.push("keyword layerrule " + rules[i].rule)
    var signature = JSON.stringify({ rules: commands, mode: root.safeMode, enabled: root.enhancementsActive() })
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
    root.reconcileWobblyBackend()
    if (root.effectCapabilities.wobblyWindows === true && !root.wobblyConfigSynced && !root.wobblyConfigFailed && !root.wobblyConfigRequestInFlight)
      wobblyConfigDebounce.restart()
    root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
    root.applyBlurRules()
    root.stateRevision++
    root.stateUpdated()
  }

  function ensureDirectories() {
    if (root.shuttingDown) return
    directoryProcess.command = ["mkdir", "-p", root.configDir, root.stateDir, root.stateDir + "/clipboard-images"]
    directoryProcess.running = true
  }

  function startConfigRecovery() {
    if (root.shuttingDown || configRecoveryProcess.running || root.configLoadStatus === "future-schema") return false
    root.configRecoveryOutput = ""
    root.configRecoveryRunning = true
    configRecoveryProcess.command = ["python3", root.sourcePath("scripts/config_tool.py"), "recover", root.configPath, "--json"]
    configRecoveryProcess.running = true
    return true
  }

  function loadWindowGroups() {
    var result = WindowGroupsModel.restore(root.cfg("multitasking.groups", []))
    if (result.ok !== true) {
      root.windowGroups = []
      root.windowGroupEvents = [{ type: "load", reason: result.reason || "invalid-groups" }]
      root.windowGroupRestorePlan = null
      return false
    }
    root.windowGroups = WindowGroupsModel.normalizeList(result.groups)
    root.windowGroupEvents = []
    root.windowGroupRestorePlan = null
    return true
  }

  function loadLayoutPersistence() {
    var result = LayoutPersistenceModel.restore(root.cfg("multitasking.layoutPersistence", {}))
    root.layoutPersistenceState = result.ok === true ? result.state : LayoutPersistenceModel.emptyState()
    root.layoutPersistenceRevision++
    return result.ok === true
  }

  function persistLayoutPersistence() {
    if (!root.configReady || root._loadingConfig || ["ok", "fresh", "migrated"].indexOf(root.configLoadStatus) < 0) return false
    root.config = Config.set(root.config, "multitasking.layoutPersistence", LayoutPersistenceModel.persistable(root.layoutPersistenceState))
    root.saveConfig()
    root.configUpdated("multitasking.layoutPersistence")
    return true
  }

  function rememberManagedLayout(group, kind) {
    if (!group || root.safeMode) return false
    var previous = JSON.stringify(LayoutPersistenceModel.persistable(root.layoutPersistenceState))
    var next = String(kind || "recent") === "saved"
      ? LayoutPersistenceModel.save(root.layoutPersistenceState, group, { now: Date.now() })
      : LayoutPersistenceModel.rememberRecent(root.layoutPersistenceState, group, { now: Date.now() })
    root.layoutPersistenceState = next
    root.layoutPersistenceRevision++
    var changed = previous !== JSON.stringify(LayoutPersistenceModel.persistable(next))
    if (changed) root.persistLayoutPersistence()
    return changed
  }

  function removePersistedLayout(id) {
    root.layoutPersistenceState = LayoutPersistenceModel.remove(root.layoutPersistenceState, id)
    root.layoutPersistenceRevision++
    root.persistLayoutPersistence()
    return true
  }

  function persistWindowGroups() {
    if (!root.configReady || root._loadingConfig || ["ok", "fresh", "migrated"].indexOf(root.configLoadStatus) < 0) return false
    var saved = (Array.isArray(root.windowGroups) ? root.windowGroups : []).filter(function(group) { return group && group.persistent !== false })
    root.config = Config.set(root.config, "multitasking.groups", WindowGroupsModel.metadataList(saved))
    root.saveConfig()
    root.configUpdated("multitasking.groups")
    return true
  }

  function prepareWindowGroupRestore() {
    var result = WindowGroupsModel.restorePlan(
      root.windowGroups,
      root.clients,
      root.cfg("multitasking.sessionRestore", "ask"),
      Date.now(),
      { safeMode: root.safeMode, duplicatePolicy: root.cfg("multitasking.duplicatePolicy", "ask") }
    )
    root.windowGroupRestorePlan = result
    return result
  }

  function loadConfig(raw) {
    root._loadingConfig = true
    var loaded = Config.loadDetailed(raw)
    if (loaded.ok !== true) {
      // Never turn an unreadable or future config into a silently persisted
      // default. Keep the shell usable in memory, but require an explicit
      // repair/export/import action before writing the file again.
      root.config = Config.defaults()
      root.configLoadStatus = String(loaded.reason || "invalid-config")
      root.configLoadError = String(loaded.error || loaded.reason || "configuration requires recovery")
      root.configMigration = { applied: [], from: loaded.schemaVersion || null, to: Config.CURRENT_SCHEMA_VERSION }
      root.safeMode = true
      root.lastError = "Configuration requires recovery: " + root.configLoadError
      root.startConfigRecovery()
    } else {
      root.config = loaded.config
      root.configLoadStatus = loaded.fresh === true ? "fresh" : (loaded.migrated === true ? "migrated" : "ok")
      root.configLoadError = ""
      root.configMigration = { applied: loaded.applied || [], from: loaded.from, to: loaded.to }
      root.safeMode = false
    }
    root.syncDeviceProfiles()
    root.masterEnabled = root.cfg("controlCenter.masterEnabled", true) === true
    root.suspended = root.cfg("controlCenter.suspended", false) === true
    root.adaptiveProfile = FeatureStateModel.normalizedProfile(root.cfg("adaptive.profile", "auto"))
    root.refreshFeatureStates()
    root.loadWindowGroups()
    root.loadLayoutPersistence()
    root._loadingConfig = false
    root.configReady = true
    root.prepareWindowGroupRestore()
    root.startDeviceMonitor()
    root.startSessionMonitor()
    if (root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false))
      root.stopClipboardWatchers()
    else
      root.startClipboardWatchers()
    root.detectedMode = root.computeMode()
    root.updateResponsiveContext()
    if (root.hyprlandAvailable) root.applyTouchIntegration()
    root.refreshRotationBackend()
    root.refreshEffectBackend()
    root.stateRevision++
    root.stateUpdated()
  }

  function saveConfig() {
    if (!root.configReady || root._loadingConfig || ["ok", "fresh", "migrated"].indexOf(root.configLoadStatus) < 0) return
    root.config.schemaVersion = Config.CURRENT_SCHEMA_VERSION
    configWriteDebounce.restart()
  }

  function setConfig(path, value) {
    var configPath = String(path)
    root.config = Config.set(root.config, configPath, value)
    if (configPath === "deviceProfiles" || configPath.indexOf("deviceProfiles.") === 0) {
      root.deviceProfileStore = DeviceProfilesModel.normalizeStore(root.cfg("deviceProfiles", {}))
      root.config = Config.set(root.config, "deviceProfiles", root.deviceProfileStore)
    }
    root.saveConfig()
    root.configUpdated(configPath)
    if (configPath === "controlCenter.masterEnabled") {
      root.masterEnabled = value === true
      if (!root.masterEnabled) root.disableEnhancements("master-disabled")
      else root.enableEnhancements()
    } else if (configPath === "controlCenter.suspended") {
      root.suspended = value === true
      if (root.suspended) root.disableEnhancements("suspended")
      else root.enableEnhancements()
    }
    if (configPath === "adaptive.profile") root.adaptiveProfile = FeatureStateModel.normalizedProfile(value)
    if (configPath === "multitasking.groups") root.loadWindowGroups()
    if (configPath === "multitasking.layoutPersistence") root.loadLayoutPersistence()
    if (configPath.indexOf("multitasking.sessionRestore") === 0 || configPath === "multitasking.groups") root.prepareWindowGroupRestore()
    if (configPath === "keyboard.layout") root.setInputLanguage(String(value || "auto"))
    if (configPath.indexOf("clipboard.") === 0 || configPath.indexOf("privacy.clipboard") === 0) {
      if (root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false)) root.stopClipboardWatchers()
      else root.startClipboardWatchers()
      root.pruneClipboard()
    }
    if (configPath.indexOf("general.mode") === 0 || configPath.indexOf("tabletMode.") === 0 || configPath.indexOf("accessibility.") === 0 || configPath.indexOf("general.largeUi") === 0 || configPath.indexOf("adaptive.") === 0) {
      root.detectedMode = root.computeMode()
      root.updateResponsiveContext()
    }
    if (configPath.indexOf("keyboard.") === 0 || configPath.indexOf("stylus.showOskOnTextField") === 0 || configPath.indexOf("tabletMode.") === 0 || configPath === "controlCenter.masterEnabled" || configPath === "controlCenter.suspended")
      root.reconcileOskPolicy()
    if (configPath.indexOf("touch.") === 0) root.applyTouchIntegration()
    if (configPath.indexOf("rotation.") === 0) root.refreshRotationBackend()
    if (configPath.indexOf("input.") === 0) {
      if (configPath === "input.deviceHotplug" && root.cfg("input.deviceHotplug", true) !== true && deviceMonitorProcess.running)
        deviceMonitorProcess.running = false
      else if (root.cfg("input.deviceHotplug", true) === true) root.startDeviceMonitor()
      if (configPath === "input.nativeBackend" || configPath === "input.safeModeDisableNative") {
        var nativePolicy = String(root.cfg("input.nativeBackend", "auto"))
        if (nativePolicy === "fallback" || nativePolicy === "disabled" || root.cfg("input.safeModeDisableNative", false) === true) {
          root.stopNativeInputBackend("native-backend-disabled-by-policy")
        } else root.startInputBackendProbe()
      }
      if (configPath.indexOf("input.deviceMappings") === 0 || configPath === "input.defaultOutput") root.updateInputMapping()
    }
    if (configPath === "multitasking.snapAssist.enabled" && value === false && root.snapAssistState.active === true)
      root.cancelSnapAssist("snap-assist-disabled")
    if (configPath === "multitasking.splitView.enabled" && value === false && root.splitViewState && root.splitViewState.phase === "dragging")
      root.rollbackSplitView("split-view-disabled")
    if (configPath.indexOf("stylus.") === 0) root.refreshStylusInputPolicy()
    if (configPath.indexOf("notifications.enabled") === 0) root.refreshIntegrations()
    if (configPath === "wobbly.enabled") {
      root.wobblyBackendFailed = false
      root.requestWobblyBackend(root.wobblyDesired())
    } else if (configPath.indexOf("wobbly.") === 0) {
      root.wobblyConfigSynced = false
      root.wobblyConfigFailed = false
      wobblyConfigDebounce.restart()
    }
    if (configPath.indexOf("effects.") === 0 || configPath.indexOf("performance.") === 0 || configPath.indexOf("general.reduceMotion") === 0)
      root.reconcileWobblyBackend()
    if (configPath.indexOf("blur.") === 0 || configPath.indexOf("performance.") === 0 || configPath.indexOf("effects.") === 0 || configPath.indexOf("applicationRules.") === 0 || configPath.indexOf("animations.") === 0) {
      root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
      root.applyBlurRules()
    }
    root.refreshFeatureStates()
    root.stateRevision++
    root.stateUpdated()
    return true
  }

  function resetConfig() {
    root.adaptivePreviewState = AdaptiveSettingsModel.emptyPreviewState()
    adaptivePreviewTimer.stop()
    root.config = Config.defaults()
    root.deviceProfileStore = DeviceProfilesModel.emptyStore()
    root.masterEnabled = true
    root.suspended = false
    root.adaptiveProfile = "auto"
    root.loadWindowGroups()
    root.saveConfig()
    root.startClipboardWatchers()
    root.syncNativeInputLanguage()
    root.detectedMode = root.computeMode()
    root.updateResponsiveContext()
    root.refreshRotationBackend()
    root.blurRuleSignature = ""
    root.wobblyBackendFailed = false
    root.requestWobblyBackend(false)
    root.wobblyConfigSynced = false
    root.wobblyConfigFailed = false
    root.applyBlurRules()
    root.prepareWindowGroupRestore()
    root.refreshFeatureStates()
    root.stateRevision++
    root.stateUpdated()
  }

  function applyProfile(profile) {
    var raw = String(profile || "auto")
    var name = raw.toLowerCase().replace(/[\s_]+/g, "-")
    if (name === "stylus" || name === "gnome-like") name = "hybrid"
    if (name === "performance" || name === "battery-saver") name = "desktop"
    if (["auto", "desktop", "tablet", "hybrid", "presentation", "gaming", "custom"].indexOf(name) < 0) return false
    // Keep this legacy entry point for older settings deep links, but route it
    // through the adaptive profile state. Profiles are overlays and must not
    // rewrite general, input, effect or accessibility preferences.
    return root.setAdaptiveProfile(name)
  }

  function computeMode() {
    var signals = root.adaptiveSignals()
    // TabletModeModel.decide remains the deterministic baseline; transition()
    // adds debounce/dwell without hiding the underlying reason.
    var transition = TabletModeModel.transition(signals, { mode: root.cfg("general.mode", "automatic"), tabletMode: root.cfg("tabletMode", {}) }, root.postureState, Date.now())
    root.postureState = transition.state
    root.tabletModeState = transition.decision
    if (transition.pending) {
      postureTransition.interval = Math.max(20, Number(transition.delayMs || 80))
      postureTransition.restart()
    } else {
      postureTransition.stop()
    }
    return transition.state.current || transition.decision.mode
  }

  function focusedMonitor() {
    var list = Array.isArray(root.monitors) ? root.monitors : []
    for (var i = 0; i < list.length; i++) if (list[i] && (list[i].focused === true || list[i].active === true)) return list[i]
    return list.length > 0 ? list[0] : {}
  }

  function updateResponsiveContext() {
    root.refreshAdaptiveState()
    var monitor = root.focusedMonitor()
    var width = Number(monitor.width || (monitor.resolution && monitor.resolution.width) || 1280)
    var height = Number(monitor.height || (monitor.resolution && monitor.resolution.height) || 720)
    var scale = Number(monitor.scale || monitor.factor || 1)
    root.responsiveState = ResponsiveModel.context(width, height, scale, root.lastInput, root.effectiveMode, {
      largeUi: root.cfg("general.largeUi", false) === true,
      touchTargetSize: root.cfg("accessibility.touchTargetSize", "default"),
      textScale: root.cfg("accessibility.textScale", 1),
      reducedMotion: root.cfg("general.reduceMotion", false) === true || root.cfg("accessibility.reducedMotion", false) === true,
      reduceTransparency: root.cfg("accessibility.reduceTransparency", false) === true,
      highContrast: root.cfg("accessibility.highContrast", false) === true
    })
    var profile = TabletModeModel.profile(root.effectiveMode, root.config, root.responsiveState)
    var policy = root.componentPolicy || {}
    root.tabletProfile = Object.assign({}, profile, {
      mode: root.effectiveMode,
      touchTarget: Number(policy.touchTargetSize || profile.touchTarget),
      oskAutoShow: policy.oskAutoShow === true,
      windowControls: policy.windowControls !== "hidden" && policy.windowControls !== "optional" && root.effectiveMode !== "desktop",
      gestures: policy.gestures !== "disabled" && profile.gestures,
      quickSettingsDensity: String(policy.quickSettings || profile.quickSettingsDensity),
      launcherDensity: String(policy.launcher || profile.launcherDensity),
      docked: policy.docked === true,
      dockedKeepTouch: policy.dockedKeepTouch === true,
      rotationPolicy: String(policy.rotation || profile.rotation || "preserve")
    })
    root.refreshFeatureStates()
  }

  function recordInput(kind) {
    var value = String(kind || "keyboard")
    value = InputModel.normalize(value)
    var now = Date.now()
    var observed = InputModel.observe({ current: root.lastInput, pending: root.inputCandidate, pendingSince: root.inputCandidateSince }, value, now, root.cfg("general.inputDebounceMs", 320))
    root.inputCandidate = observed.pending
    root.inputCandidateSince = observed.pendingSince
    if (observed.current !== root.lastInput) {
      root.lastInput = observed.current
      root.detectedMode = root.computeMode()
      root.updateResponsiveContext()
      root.reconcileOskPolicy()
      root.stateRevision++
      root.stateUpdated()
      return
    }
    if (root.inputCandidate) {
      inputModeCommit.interval = InputModel.delay(root.inputCandidate, root.cfg("general.inputDebounceMs", 320))
      inputModeCommit.restart()
    }
  }

  function commitInputMode() {
    var now = Date.now()
    var observed = InputModel.commit({ current: root.lastInput, pending: root.inputCandidate, pendingSince: root.inputCandidateSince }, now, root.cfg("general.inputDebounceMs", 320))
    root.inputCandidate = observed.pending
    root.inputCandidateSince = observed.pendingSince
    if (observed.current === root.lastInput) return
    root.lastInput = observed.current
    root.detectedMode = root.computeMode()
    root.updateResponsiveContext()
    root.reconcileOskPolicy()
    root.refreshFeatureStates()
    root.stateRevision++
    root.stateUpdated()
  }

  function parseJson(text, fallback) {
    try { return JSON.parse(String(text || "")) } catch (error) { return fallback }
  }

  function refreshSystemState() {
    if (!root.shuttingDown && !systemStateProcess.running) systemStateProcess.running = true
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
    root.reconcileWobblyBackend()
    root.applyBlurRules()
    root.refreshFeatureStates()
    root.stateRevision++
    root.stateUpdated()
  }

  function scanWifi() {
    if (!root.shuttingDown && !wifiScanProcess.running) wifiScanProcess.running = true
  }

  function updateWifiScan(raw) {
    var parsed = root.parseJson(raw, [])
    root.wifiNetworks = Array.isArray(parsed) ? parsed : []
    root.stateRevision++
    root.stateUpdated()
  }

  function scanBluetooth() {
    if (!root.shuttingDown && !bluetoothScanProcess.running) bluetoothScanProcess.running = true
  }

  function updateBluetoothScan(raw) {
    var parsed = root.parseJson(raw, [])
    root.bluetoothDevices = Array.isArray(parsed) ? parsed : []
    root.stateRevision++
    root.stateUpdated()
  }

  function scanAudio() {
    if (!root.shuttingDown && !audioScanProcess.running) audioScanProcess.running = true
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
    if (screenshotProcess.running) return false
    screenshotProcess.command = copyToClipboard
      ? ["bash", "-c", "grim - | wl-copy --type image/png"]
      : ["bash", "-c", "mkdir -p \"$HOME/Pictures/Screenshots\" && grim \"$HOME/Pictures/Screenshots/omanome-$(date +%Y%m%d-%H%M%S).png\""]
    screenshotProcess.running = true
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

  function rotationMonitorName(value) {
    var name = String(value || "").trim()
    // Hyprland connector names are token-like. Reject unsafe names instead
    // of stripping characters and accidentally targeting a different output.
    return /^[A-Za-z0-9_.:-]+$/.test(name) ? name : ""
  }

  function rotationMonitorState(monitors) {
    var result = []
    var list = Array.isArray(monitors) ? monitors : []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var name = root.rotationMonitorName(item.name)
      if (!name) continue
      var transform = Number(item.transform)
      if (!isFinite(transform) || transform < 0 || transform > 3) transform = root.rotationTransform
      result.push({ name: name.replace(/[;,]/g, ""), transform: Math.floor(transform) })
    }
    return result
  }

  function rotationBatch(value, monitorStates) {
    var commands = []
    var transform = Math.max(0, Math.min(3, Math.floor(Number(value))))
    if (root.cfg("rotation.transformTouch", true))
      commands.push("keyword input:touchdevice:transform " + String(transform))
    if (root.cfg("rotation.transformStylus", true))
      commands.push("keyword input:tablet:transform " + String(transform))
    var list = Array.isArray(monitorStates) ? monitorStates : []
    for (var i = 0; i < list.length; i++) {
      var name = root.rotationMonitorName(list[i] && list[i].name)
      if (name) commands.push("keyword monitor " + name + ",transform," + String(transform))
    }
    return commands.join(";")
  }

  function rotationRollbackBatch() {
    var previous = root.rotationRollback || {}
    var commands = []
    var touch = Number(previous.touch)
    var tablet = Number(previous.tablet)
    if (!isFinite(touch) || touch < 0 || touch > 3) touch = 0
    if (!isFinite(tablet) || tablet < 0 || tablet > 3) tablet = 0
    if (root.cfg("rotation.transformTouch", true))
      commands.push("keyword input:touchdevice:transform " + String(Math.floor(touch)))
    if (root.cfg("rotation.transformStylus", true))
      commands.push("keyword input:tablet:transform " + String(Math.floor(tablet)))
    var monitors = Array.isArray(previous.monitors) ? previous.monitors : []
    for (var i = 0; i < monitors.length; i++) {
      var item = monitors[i] || {}
      var name = root.rotationMonitorName(item.name)
      var transform = Number(item.transform)
      if (!isFinite(transform) || transform < 0 || transform > 3) transform = 0
      if (name) commands.push("keyword monitor " + name + ",transform," + String(Math.floor(transform)))
    }
    return commands.join(";")
  }

  function rotationLifecycleAllowed() {
    var lifecycle = root.lifecycleState || {}
    return !root.shuttingDown && lifecycle.phase !== "suspended" && lifecycle.locked !== true
  }

  function finishRotation(success, rollbackConfirmed, reason) {
    if (success) {
      root.rotationTransform = root.pendingRotationTransform
      root.lastError = ""
    } else {
      var previous = Number(root.rotationRollback.previous)
      if (isFinite(previous) && previous >= 0 && previous <= 3) root.rotationTransform = Math.floor(previous)
      root.rotationRollbackConfirmed = rollbackConfirmed === true
      root.lastError = root.rotationRollbackConfirmed
        ? (reason ? String(reason) + "; previous monitor and input transforms were restored" : "Rotation failed; previous monitor and input transforms were restored")
        : (reason || "Rotation failed; previous monitor and input transforms could not be confirmed")
    }
    root.pendingRotationTransform = -1
    root.rotationTargets = []
    root.rotationAbortRequested = false
    root.rotationAbortReason = ""
    root.stateRevision++
    root.stateUpdated()
    if (success && root.queuedRotationTransform >= 0 && root.rotationLifecycleAllowed()) {
      var queued = root.queuedRotationTransform
      root.queuedRotationTransform = -1
      Qt.callLater(function() { root.applyRotation(queued) })
    } else root.queuedRotationTransform = -1
  }

  function abortRotation(reason) {
    var message = String(reason || "Rotation transaction cancelled")
    root.queuedRotationTransform = -1
    if (rotationApplyProcess.running || rotationRollbackProcess.running) {
      root.rotationAbortRequested = true
      root.rotationAbortReason = message
      if (rotationApplyProcess.running) rotationApplyProcess.running = false
      if (rotationRollbackProcess.running) rotationRollbackProcess.running = false
      return true
    }
    if (root.pendingRotationTransform >= 0) {
      root.finishRotation(false, false, message)
      return true
    }
    return false
  }

  function applyRotation(transform) {
    if (!root.rotationLifecycleAllowed() || !root.hyprlandAvailable || !root.systemState.rotationAvailable) return false
    var requested = Number(transform)
    if (!isFinite(requested)) requested = root.rotationTransform
    var value = Math.max(0, Math.min(3, Math.floor(requested)))
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
    root.rotationRollbackConfirmed = false
    root.rotationAbortRequested = false
    root.rotationAbortReason = ""
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
    var observed = RotationModel.observe(root.orientationState, next, Date.now(), {
      stableMs: Number(root.cfg("rotation.orientationDebounceMs", 550)),
      minimumDwellMs: Number(root.cfg("rotation.minimumDwellMs", 1000))
    })
    root.orientationState = observed.state
    if (observed.pending) {
      orientationTransition.interval = Math.max(120, Number(observed.delayMs || 550))
      orientationTransition.restart()
      return
    }
    if (observed.changed) root.orientation = observed.value
    if (observed.changed && root.cfg("rotation.orientation", "auto") === "auto" && !root.cfg("rotation.lock", false))
      root.applyRotation(root.rotationTransformFor(observed.value))
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
    if (root.shuttingDown) return false
    if (root.rotationBackendWanted()) {
      if (!root.rotationRestartState.blocked && !rotationProcess.running) rotationProcess.running = true
      return
    }
    rotationRestart.stop()
    root.rotationRestartState = { consecutiveFailures: 0, startedAt: 0, blocked: false }
    if (rotationProcess.running) rotationProcess.running = false
  }

  function refreshDevices() {
    if (root.shuttingDown) return false
    if (!devicesProcess.running) devicesProcess.running = true
    if (!monitorsProcess.running) monitorsProcess.running = true
    if (!clientsProcess.running) clientsProcess.running = true
  }

  function updateInputMapping() {
    var mappingPlan = MappingModel.plan(
      root.inputDeviceState.devices,
      root.monitors,
      root.cfg("input.deviceMappings", {}),
      root.cfg("input.defaultOutput", "")
    )
    root.inputMappingState = {
      schemaVersion: 1,
      outputs: MappingModel.availableOutputs(root.monitors),
      plan: mappingPlan,
      explanation: MappingModel.explain(mappingPlan)
    }
  }

  function updateDeviceGraph() {
    var source = root.devices && typeof root.devices === "object" && !Array.isArray(root.devices) ? root.devices : {}
    var snapshot = Object.assign({}, source, { monitors: Array.isArray(root.monitors) ? root.monitors : [] })
    root.deviceGraph = DeviceGraphModel.fromSnapshot(snapshot, root.deviceGraph)
  }

  function deviceProfileRows() {
    return DeviceProfilesModel.list(root.deviceGraph, root.deviceProfileStore)
  }

  function syncDeviceProfiles() {
    root.deviceProfileStore = DeviceProfilesModel.normalizeStore(root.cfg("deviceProfiles", {}))
  }

  function updateDevices(raw) {
    var parsed = parseJson(raw, {})
    root.devices = parsed
    root.inputDeviceState = InputDevicesModel.stateFromSnapshot(parsed, root.inputDeviceState)
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
    root.hasTouchscreen = touches.length > 0 || root.inputDeviceState.devices.some(function(item) { return item.role === "touchscreen" })
    root.stylusDevices = styluses
    root.hasStylus = styluses.length > 0
    root.keyboardDevices = KeyboardDevicesModel.classify(parsed)
    root.hasPhysicalKeyboard = root.keyboardDevices.some(function(device) { return device && device.connected === true })
    root.hasDetachableKeyboard = root.keyboardDevices.some(function(device) { return device && device.connected === true && device.formFactorRelation === "detachable" })
    root.hasBluetoothKeyboard = root.keyboardDevices.some(function(device) { return device && device.connected === true && device.transport === "bluetooth" })
    root.observeKeyboardTransition("device-snapshot")
    root.updateInputMapping()
    root.refreshStylusInputPolicy()
    root.reconcileOskPolicy()
    var tabletSwitch = parsed.tabletSwitch
    if (tabletSwitch === undefined) tabletSwitch = parsed.tablet_switch
    if (tabletSwitch === undefined && parsed.switches && typeof parsed.switches === "object") {
      tabletSwitch = parsed.switches.tabletMode
      if (tabletSwitch === undefined) tabletSwitch = parsed.switches.tablet
    }
    if (tabletSwitch !== undefined) {
      if (typeof tabletSwitch === "object") {
        root.tabletSwitchAvailable = tabletSwitch.available !== false
        root.tabletSwitchActive = tabletSwitch.active === true || tabletSwitch.state === "tablet"
      } else {
        root.tabletSwitchAvailable = true
        root.tabletSwitchActive = tabletSwitch === true
      }
    } else {
      root.tabletSwitchAvailable = false
      root.tabletSwitchActive = false
    }
    root.detectedMode = root.computeMode()
    root.updateResponsiveContext()
    root.reconcileOskPolicy()
    root.refreshFeatureStates()
    root.updateDeviceGraph()
    root.stateRevision++
    root.stateUpdated()
  }

  function updateDeviceEvent(raw) {
    var parsed = parseJson(raw, null)
    if (!parsed || String(parsed.type || "") !== "device.event") return
    root.inputDeviceState = InputDevicesModel.applyEvent(root.inputDeviceState, parsed)
    root.deviceGraph = DeviceGraphModel.applyEvent(root.deviceGraph, parsed)
    root.keyboardTransitionState = KeyboardTransitionsModel.noteEvent(root.keyboardTransitionState, parsed, Date.now())
    root.updateInputMapping()
    root.refreshStylusInputPolicy()
    root.inputDeviceMonitorAvailable = true
    root.inputDeviceMonitorReason = "udev-event-stream"
    deviceRefreshDebounce.restart()
    root.refreshFeatureStates()
    root.stateRevision++
    root.stateUpdated()
  }

  function startDeviceMonitor() {
    if (root.shuttingDown || !root.configReady || root.safeMode || !root.masterEnabled || root.suspended || root.cfg("input.deviceHotplug", true) !== true || deviceMonitorProcess.running) return false
    if (!root.sourcePath("input/device-monitor.sh")) return false
    deviceMonitorProcess.command = ["bash", root.sourcePath("input/device-monitor.sh")]
    deviceMonitorProcess.running = true
    return true
  }

  function startSessionMonitor() {
    if (root.shuttingDown || !root.configReady || root.safeMode || !root.masterEnabled || root.suspended || sessionMonitorProcess.running) return false
    if (!root.sourcePath("input/session-monitor.sh")) return false
    sessionMonitorProcess.command = ["bash", root.sourcePath("input/session-monitor.sh")]
    sessionMonitorProcess.running = true
    return true
  }

  function updateSessionEvent(raw) {
    var parsed = parseJson(raw, null)
    if (!parsed || String(parsed.type || "") !== "session.event") return
    var transition = LifecycleModel.transition(root.lifecycleState, parsed, Date.now())
    if (!transition.changed && transition.action === "ignore") return
    root.lifecycleState = transition.state
    if (transition.state.phase === "suspended") {
      root.inputTextFocusActive = false
      root.requestAutoOsk(false)
      root.stopNativeInputBackend("suspended")
      root.cancelFallbackInput()
      if (rotationProcess.running) rotationProcess.running = false
      root.abortRotation("Rotation was cancelled for suspend")
      root.sessionMonitorReason = "suspended"
    } else if (transition.state.phase === "active") {
      root.sessionMonitorReason = transition.state.locked ? "active-locked" : "active"
      root.inputRestartState = { consecutiveFailures: 0, startedAt: 0, blocked: false }
      root.startInputBackendProbe()
      root.startDeviceMonitor()
      root.refreshDevices()
      root.refreshRotationBackend()
    }
    if (transition.state.locked) {
      root.requestAutoOsk(false)
      root.cancelFallbackInput()
      root.nativeInputReset()
    }
    root.stateRevision++
    root.stateUpdated()
  }

  function updateMonitors(raw) {
    var parsed = parseJson(raw, [])
    var nextMonitors = Array.isArray(parsed) ? parsed : []
    var previousMonitors = Array.isArray(root.monitors) ? root.monitors.slice() : []
    var activeName = ""
    for (var monitorIndex = 0; monitorIndex < nextMonitors.length; monitorIndex++) {
      if (nextMonitors[monitorIndex] && (nextMonitors[monitorIndex].focused === true || nextMonitors[monitorIndex].active === true)) {
        activeName = String(nextMonitors[monitorIndex].name || nextMonitors[monitorIndex].monitor || nextMonitors[monitorIndex].output || "")
        break
      }
    }
    var recovery = MonitorRecoveryModel.plan(
      previousMonitors,
      nextMonitors,
      root.clients,
      root.windowGroups,
      { activeMonitor: activeName, minimumWindowSize: root.cfg("multitasking.minimumWindowSize", {}), recoverOffscreen: true }
    )
    root.monitorRecoveryState = recovery
    root.monitorRecoveryRevision++
    var availableNames = nextMonitors.map(function(item) { return root.rotationMonitorName(item && item.name) }).filter(function(name) { return name !== "" })
    var missingTarget = root.rotationTargets.some(function(name) { return availableNames.indexOf(root.rotationMonitorName(name)) < 0 })
    if (missingTarget) root.abortRotation("Rotation was cancelled because a target monitor disappeared")
    root.monitors = nextMonitors
    if (root.cfg("multitasking.multiMonitor.enabled", true) !== false && root.cfg("multitasking.multiMonitor.hotplugRecovery", true) !== false && recovery.commands.length > 0)
      root.applyMonitorRecoveryPlan(recovery)
    root.updateInputMapping()
    root.updateDeviceGraph()
    root.updateResponsiveContext()
    root.stateRevision++
    root.stateUpdated()
  }

  function applyMonitorRecoveryPlan(plan) {
    var source = plan || {}
    if (source.ok !== true) return root.multitaskingRecord({ type: "monitor-recovery", ok: false, reason: String(source.reason || "invalid-plan") })
    if (!root.hyprlandAvailable) {
      root.monitorRecoveryState = Object.assign({}, source, { applied: 0, failed: true, rolledBack: false, reason: "hyprland-unavailable" })
      root.monitorRecoveryRevision++
      return root.multitaskingRecord({ type: "monitor-recovery", ok: false, reason: "hyprland-unavailable", moved: 0 })
    }
    var commands = Array.isArray(source.commands) ? source.commands.slice(0, MonitorRecoveryModel.MAX_COMMANDS) : []
    var applied = 0
    var failed = false
    for (var i = 0; i < commands.length; i++) {
      if (!root.dispatch(commands[i])) { failed = true; break }
      applied++
    }
    var rolledBack = false
    if (failed) {
      var rollback = Array.isArray(source.rollback) ? source.rollback.slice(0, MonitorRecoveryModel.MAX_COMMANDS) : []
      for (var j = 0; j < rollback.length; j++) if (root.dispatch(rollback[j])) rolledBack = true
    }
    root.monitorRecoveryState = Object.assign({}, source, { applied: applied, failed: failed, rolledBack: rolledBack })
    root.monitorRecoveryRevision++
    if (!failed && source.affectedGroups && root.splitViewState && root.splitViewWindows.length > 0) {
      var splitGroup = root.windowGroupForWindow(root.splitViewWindows[0])
      if (splitGroup && source.affectedGroups.indexOf(String(splitGroup.id || "")) >= 0) {
        root.splitViewState = null
        root.splitViewWindows = []
      }
    }
    root.reconcileWindowGroups()
    root.stateUpdated()
    return root.multitaskingRecord({ type: "monitor-recovery", ok: !failed, reason: failed ? "dispatch-rejected" : "queued", moved: applied / 2, rolledBack: rolledBack })
  }

  function updateClients(raw) {
    root.clients = parseJson(raw, [])
    root.reconcileWindowGroups()
    root.resolveMultitaskingLaunch()
    if (root.hyprlandAvailable) root.applyTouchIntegration()
    root.performanceState = PerformanceModel.snapshot(root.cfg("performance", {}), root.performanceContext())
    root.reconcileWobblyBackend()
    root.applyBlurRules()
    root.stateRevision++
    root.stateUpdated()
  }

  function statusObject() {
    return {
      version: root.manifest ? String(root.manifest.version || "1.2.0") : "1.2.0",
      quickshell: String(Quickshell.env("QUICKSHELL_VERSION") || "host-provided"),
      service: "ready",
      safeMode: root.safeMode,
      enabled: root.masterEnabled,
      suspended: root.suspended,
      profile: root.adaptiveProfile,
      mode: root.detectedMode,
      effectiveMode: root.effectiveMode,
      transitioning: (root.adaptiveState && root.adaptiveState.transitioning === true) || (root.modeTransitionState && root.modeTransitionState.active === true),
      modeTransition: root.modeTransitionSummary(),
      dockedMode: root.dockedModeSummary(),
      adaptivePreview: root.adaptivePreviewSummary(),
      keyboardState: String(root.keyboardTransitionState.phase || (root.hasPhysicalKeyboard ? "Connected" : "Disconnected")).toLowerCase(),
      keyboardStable: root.keyboardTransitionState.modeReady !== false,
      keyboardTransition: root.keyboardTransitionSummary(),
      features: root.featureStateSummary,
      requestedMode: root.cfg("general.mode", "automatic"),
      lastInput: root.lastInput,
      inputCandidate: root.inputCandidate,
      responsive: root.responsiveState,
      hasTouchscreen: root.hasTouchscreen,
      hasStylus: root.hasStylus,
      stylusCount: root.stylusDevices.length,
      physicalKeyboard: root.hasPhysicalKeyboard,
      detachableKeyboard: root.hasDetachableKeyboard,
      bluetoothKeyboard: root.hasBluetoothKeyboard,
      tabletMode: { mode: root.effectiveMode, switchAvailable: root.tabletSwitchAvailable, switchActive: root.tabletSwitchActive, reason: root.tabletModeState.reason, profile: root.tabletProfile },
      physicalKeyboardCount: root.keyboardDevices.length,
      keyboards: root.keyboardDeviceSummaries(),
      inputDevices: {
        backend: root.inputDeviceState.backend,
        revision: Number(root.inputDeviceState.revision || 0),
        count: root.inputDeviceState.devices.length,
        hotplug: root.inputDeviceMonitorAvailable,
        hotplugReason: root.inputDeviceMonitorReason,
        lastEvent: root.inputDeviceState.hotplug,
        mapping: root.inputDeviceState.devices.map(function(item) { return { id: item.id, role: item.role, output: item.output || "automatic" } })
      },
      deviceGraph: DeviceGraphModel.summary(root.deviceGraph),
      deviceProfiles: DeviceProfilesModel.summary(root.deviceProfileStore),
      stylusInput: {
        backend: root.stylusInputState.backend,
        available: root.stylusInputState.available === true,
        proximity: root.stylusInputState.proximity === true,
        contact: root.stylusInputState.contact === true,
        capabilities: root.stylusInputState.capabilities,
        points: Number(root.stylusInputState.totalPoints || 0),
        provider: root.stylusProviderState,
        palm: root.stylusPalmState
      },
      inputMapping: root.inputMappingState,
      lifecycle: { state: root.lifecycleState, sessionMonitor: root.sessionMonitorAvailable, reason: root.sessionMonitorReason },
      orientationDebounce: root.orientationState,
      posture: InputDevicesModel.explain(root.tabletModeState.signals || {}, root.detectedMode),
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
      inputText: root.inputTextBackendAvailable,
      inputBackendReason: root.inputBackendReason,
      inputCapabilities: root.inputBackendCapabilities,
      inputStatus: root.inputBackendStatus,
      textFocus: root.inputTextFocusActive,
      secureTextFocus: root.inputSecureContext,
      oskPolicy: root.oskPolicyState,
      rotation: {
        available: root.systemState.rotationAvailable === true,
        sensor: root.systemState.rotationSensorAvailable === true,
        sensorBackend: String(root.systemState.rotationSensorBackend || "manual"),
        dbus: root.systemState.rotationDbusAvailable === true,
        accelerometer: root.systemState.rotationAccelerometerAvailable === true,
        targets: root.rotationTargets.slice(),
        transactionPending: root.pendingRotationTransform >= 0,
        rollbackConfirmed: root.rotationRollbackConfirmed,
        orientation: root.orientation,
        locked: root.cfg("rotation.lock", false) === true
      },
      configPath: root.configPath,
      config: { schemaVersion: Number(root.config.schemaVersion || Config.CURRENT_SCHEMA_VERSION), loadStatus: root.configLoadStatus, loadError: root.configLoadError, migration: root.configMigration },
      clipboardEntries: root.clipboardHistory.length,
      processes: {
        owner: root.processOwner,
        registryPath: root.processRegistryPath,
        registryReady: root.processRegistryReady,
        ownedCount: root.ownedProcesses.length,
        counters: root.processCounters,
        clipboardRestart: root.clipboardRestartState
      },
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
      multitasking: {
        enabled: root.cfg("multitasking.enabled", true) !== false,
        monitorCount: root.multitaskingMonitors().length,
        revision: root.multitaskingRevision,
        lastAction: root.multitaskingLastAction,
        error: root.multitaskingError,
        snapAssist: {
          active: root.snapAssistState.active === true,
          phase: String(root.snapAssistState.phase || "idle"),
          reason: String(root.snapAssistState.reason || "idle"),
          inputKind: String(root.snapAssistState.inputKind || "mouse"),
          monitor: String(root.snapAssistState.monitorName || ""),
          candidate: String(root.snapAssistState.candidateId || ""),
          preview: root.snapAssistState.preview || null
        },
        splitView: root.splitViewState ? {
          phase: String(root.splitViewState.phase || "idle"),
          axis: String(root.splitViewState.pair && root.splitViewState.pair.axis || ""),
          ratio: Number(root.splitViewState.ratio || 0),
          ratioName: String(root.splitViewState.ratioName || ""),
          divider: root.splitViewState.divider || null,
          transaction: root.splitViewState.transaction || null
        } : null,
        launch: root.multitaskingLaunch ? {
          appId: String(root.multitaskingLaunch.appId || ""),
          status: String(root.multitaskingLaunch.status || "pending"),
          reason: String(root.multitaskingLaunch.reason || ""),
          deadline: Number(root.multitaskingLaunch.deadline || 0),
          attempts: Number(root.multitaskingLaunch.attempts || 0)
        } : null,
        pairLaunch: root.multitaskingPairLaunch ? {
          groupId: String(root.multitaskingPairLaunch.groupId || ""),
          phase: String(root.multitaskingPairLaunch.phase || "queued"),
          appIds: Array.isArray(root.multitaskingPairLaunch.appIds) ? root.multitaskingPairLaunch.appIds.slice(0, 2) : [],
          nextIndex: Number(root.multitaskingPairLaunch.nextIndex || 0),
          deadline: Number(root.multitaskingPairLaunch.deadline || 0)
        } : null,
        gestures: {
          enabled: root.cfg("multitasking.gestures.enabled", true) === true,
          touchLock: root.cfg("multitasking.gestures.touchLock", false) === true,
          state: root.gestureSummary(),
          revision: root.gestureRevision,
          lastAction: { ok: root.gestureLastAction.ok === true, action: String(root.gestureLastAction.action || ""), reason: String(root.gestureLastAction.reason || "") }
        },
        tabletSwitcher: root.tabletSwitcherSummary(),
        workspaceSwitcher: root.workspaceSwitcherSummary(),
        shortcutConflicts: MultitaskingShortcutsModel.summary(root.shortcutConflictState),
        monitorRecovery: MonitorRecoveryModel.summary(root.monitorRecoveryState),
        groups: root.windowGroupSummaries(),
        layoutPersistence: LayoutPersistenceModel.summary(root.layoutPersistenceState),
        sessionRestore: root.windowGroupRestoreSummary(),
        floating: {
          enabled: root.cfg("multitasking.floating.enabled", true) === true,
          mini: root.cfg("multitasking.floating.miniEnabled", true) === true,
          pictureInPicture: root.cfg("multitasking.floating.pictureInPicture", true) === true,
          revision: root.floatingRevision,
          lastAction: { ok: root.floatingLastAction.ok === true, reason: String(root.floatingLastAction.reason || ""), mode: String(root.floatingLastAction.mode || "") }
        }
      },
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

  // Diagnostics deliberately contain capability and version metadata only.
  // Clipboard entries, window titles, typed text, file contents and secrets
  // never enter this object.
  function diagnosticsObject() {
    var companion = root.companionState || {}
    return {
      version: root.manifest ? String(root.manifest.version || "unknown") : "unknown",
      hyprland: root.effectBackend && root.effectBackend.runtime ? String(root.effectBackend.runtime.version || "unknown") : (root.hyprlandAvailable ? "available" : "unavailable"),
      hyprlandAbi: root.effectBackend && root.effectBackend.runtime ? String(root.effectBackend.runtime.abi || "unknown") : "unknown",
      quickshell: String(Quickshell.env("QUICKSHELL_VERSION") || "host-provided"),
      wayland: String(Quickshell.env("WAYLAND_DISPLAY") || "unavailable"),
      mode: root.detectedMode,
      enabled: root.masterEnabled,
      suspended: root.suspended,
      profile: root.adaptiveProfile,
      effectiveMode: root.effectiveMode,
      transitioning: (root.adaptiveState && root.adaptiveState.transitioning === true) || (root.modeTransitionState && root.modeTransitionState.active === true),
      modeTransition: root.modeTransitionSummary(),
      dockedMode: root.dockedModeSummary(),
      adaptivePreview: root.adaptivePreviewSummary(),
      keyboardState: String(root.keyboardTransitionState.phase || (root.hasPhysicalKeyboard ? "Connected" : "Disconnected")).toLowerCase(),
      keyboardStable: root.keyboardTransitionState.modeReady !== false,
      keyboardTransition: root.keyboardTransitionSummary(),
      features: root.featureStateSummary,
      input: { last: root.lastInput, pending: root.inputCandidate, touchscreen: root.hasTouchscreen, stylus: root.hasStylus, physicalKeyboard: root.hasPhysicalKeyboard, detachableKeyboard: root.hasDetachableKeyboard, bluetoothKeyboard: root.hasBluetoothKeyboard, deviceBackend: root.inputDeviceState.backend, hotplug: root.inputDeviceMonitorAvailable, stylusInput: root.stylusInputState, stylusProvider: root.stylusProviderState, palm: root.stylusPalmState, mapping: root.inputMappingState },
      tabletMode: { mode: root.effectiveMode, reason: root.tabletModeState.reason, switchAvailable: root.tabletSwitchAvailable, switchActive: root.tabletSwitchActive, profile: root.tabletProfile },
      onboarding: { completed: root.cfg("onboarding.completed", false) === true, skipped: root.cfg("onboarding.skipped", false) === true, version: Number(root.cfg("onboarding.version", 1)) },
      devices: { monitors: root.monitors.length, stylus: root.stylusDevices.length, keyboards: root.keyboardDeviceSummaries() },
      rotation: { available: root.systemState.rotationAvailable === true, sensor: root.systemState.rotationSensorAvailable === true, backend: String(root.systemState.rotationSensorBackend || "manual") },
      multitasking: {
        enabled: root.cfg("multitasking.enabled", true) !== false,
        monitors: root.multitaskingMonitors().length,
        snapPhase: String(root.snapAssistState.phase || "idle"),
        splitAxis: root.splitViewState && root.splitViewState.pair ? String(root.splitViewState.pair.axis || "") : "unavailable",
        splitRatio: root.splitViewState ? Number(root.splitViewState.ratio || 0) : 0,
        lastAction: String(root.multitaskingLastAction.type || "none"),
        launchPending: !!root.multitaskingLaunch,
        launchAppId: root.multitaskingLaunch ? String(root.multitaskingLaunch.appId || "") : "",
        pairLaunchPending: !!root.multitaskingPairLaunch,
        gestures: {
          enabled: root.cfg("multitasking.gestures.enabled", true) === true,
          touchLock: root.cfg("multitasking.gestures.touchLock", false) === true,
          phase: String(root.gestureState.phase || "idle"),
          owner: String(root.gestureState.owner || ""),
          inputKind: String(root.gestureState.inputKind || ""),
          lastAction: String(root.gestureLastAction.action || ""),
          lastReason: String(root.gestureLastAction.reason || "")
        },
        tabletSwitcher: root.tabletSwitcherSummary(),
        workspaceSwitcher: root.workspaceSwitcherSummary(),
        shortcutConflicts: MultitaskingShortcutsModel.summary(root.shortcutConflictState),
        monitorRecovery: MonitorRecoveryModel.summary(root.monitorRecoveryState),
        groups: root.windowGroupSummaries(),
        layoutPersistence: LayoutPersistenceModel.summary(root.layoutPersistenceState),
        sessionRestore: root.windowGroupRestoreSummary(),
        floating: {
          enabled: root.cfg("multitasking.floating.enabled", true) === true,
          mini: root.cfg("multitasking.floating.miniEnabled", true) === true,
          pictureInPicture: root.cfg("multitasking.floating.pictureInPicture", true) === true,
          revision: root.floatingRevision,
          lastAction: { ok: root.floatingLastAction.ok === true, reason: String(root.floatingLastAction.reason || ""), mode: String(root.floatingLastAction.mode || ""), appId: String(root.floatingLastAction.appId || "") }
        }
      },
      companion: { installed: companion.installed === true, built: companion.built === true, loaded: companion.loaded === true, compatible: companion.compatible === true, crashMarker: companion.crashMarker === true, abiMatch: companion.abiMatch === true },
      effects: { blur: root.effectBackend.layerRulesAvailable === true, livePreview: root.livePreviewState.available === true, wobbly: root.effectCapabilities.wobblyWindows === true, cube: root.effectCapabilities.desktopCube === true },
      osk: { enabled: root.cfg("keyboard.enabled", true) === true, wtype: root.wtypeAvailable, inputBackend: root.inputBackendAvailable, inputText: root.inputTextBackendAvailable, textFocus: root.inputTextFocusActive, secure: root.inputSecureContext, policy: root.oskPolicyState },
      processes: { owner: root.processOwner, registryReady: root.processRegistryReady, ownedCount: root.ownedProcesses.length, counters: root.processCounters },
      config: { schemaVersion: Number(root.config.schemaVersion || Config.CURRENT_SCHEMA_VERSION), path: root.configPath, loadStatus: root.configLoadStatus, loadError: root.configLoadError, migration: root.configMigration },
      responsive: root.responsiveState,
      error: String(root.lastError || "")
    }
  }

  function diagnosticsText() { return JSON.stringify(root.diagnosticsObject(), null, 2) }

  function copyPlainText(value) {
    var text = String(value || "")
    if (!text) return false
    diagnosticsCopyProcess.payload = text
    diagnosticsCopyProcess.running = true
    return true
  }

  function copyDiagnostics() { return root.copyPlainText(root.diagnosticsText()) }

  function runDoctor() {
    if (doctorProcess.running) return false
    root.doctorOutput = ""
    root.doctorRunning = true
    doctorProcess.running = true
    return true
  }

  function runUpdateCheck() {
    if (updateProcess.running) return false
    root.updateOutput = ""
    updateProcess.command = ["bash", root.sourcePath("cli/omanome"), "update", "--check", "--json"]
    root.updateRunning = true
    updateProcess.running = true
    return true
  }

  function runUpdatePreview() {
    if (updateProcess.running) return false
    root.updateOutput = ""
    updateProcess.command = ["bash", root.sourcePath("cli/omanome"), "update", "--dry-run", "--json"]
    root.updateRunning = true
    updateProcess.running = true
    return true
  }

  function runRollbackList() {
    if (rollbackProcess.running) return false
    root.rollbackOutput = ""
    rollbackProcess.command = ["bash", root.sourcePath("cli/omanome"), "rollback", "--list", "--json"]
    root.rollbackRunning = true
    rollbackProcess.running = true
    return true
  }

  function runRecovery() {
    if (recoveryProcess.running) return false
    root.recoveryOutput = ""
    recoveryProcess.command = ["bash", root.sourcePath("cli/omanome"), "recover", "--json"]
    root.recoveryRunning = true
    recoveryProcess.running = true
    return true
  }

  function runBackup() {
    if (backupProcess.running) return false
    root.backupOutput = ""
    backupProcess.command = ["bash", root.sourcePath("cli/omanome"), "config", "export"]
    root.backupRunning = true
    backupProcess.running = true
    return true
  }

  function runSupportBundle() {
    if (supportBundleProcess.running) return false
    root.supportBundleOutput = ""
    supportBundleProcess.command = ["bash", root.sourcePath("cli/omanome"), "diagnostics", "bundle"]
    root.supportBundleRunning = true
    supportBundleProcess.running = true
    return true
  }

  function needsOnboarding() {
    return root.configReady && root.cfg("onboarding.completed", false) !== true && root.cfg("onboarding.skipped", false) !== true
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
    if (root.shuttingDown) return false
    var command = Array.isArray(argv) ? argv : []
    if (command.length === 0) return false
    if (String(command[0] || "").split("/").pop() === "wtype") return root.enqueueInput(command)
    if (commandProcess.running) return root.queuedCommand(command)
    commandProcess.command = command.map(function(item) { return String(item) })
    commandProcess.running = true
    return true
  }

  function dispatch(action) {
    return root.execute(["hyprctl", "dispatch"].concat(String(action || "").split(" ")))
  }

  function launchApp(desktopId) {
    var id = String(desktopId || "").replace(/\.desktop$/, "")
    if (!id) return false
    root.rememberRecentApp(id)
    return root.execute(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }

  function clientAppId(client) {
    var item = client || {}
    return String(item.appId || item.app_id || item.class || item.className || item.initialClass || "").replace(/\.desktop$/, "")
  }

  function windowsForApp(appId) {
    var key = String(appId || "").replace(/\.desktop$/, "")
    if (!key) return []
    var result = []
    var list = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < list.length; i++) {
      if (root.clientAppId(list[i]) !== key) continue
      if (list[i].address || list[i].pid) result.push(list[i])
    }
    return result
  }

  function hasWindowsForApp(appId) { return root.windowsForApp(appId).length > 0 }

  function closeWindowsForApp(appId) {
    var rows = root.windowsForApp(appId)
    var closed = false
    for (var i = 0; i < rows.length; i++) {
      var address = String(rows[i].address || "")
      if (!address) continue
      closed = root.dispatch("closewindow address:" + address) || closed
    }
    return closed
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

  function closeSwitcherWindow(window) {
    var item = root.multitaskingForeign(window)
    if (item && typeof item.close === "function") {
      item.close()
      return true
    }
    var address = root.multitaskingAddress(window)
    return address ? root.dispatch("closewindow address:" + address) : false
  }

  function tabletSwitcherOptions() {
    var configured = root.cfg("multitasking.tabletSwitcher", {})
    var altTab = root.cfg("altTab", {})
    return {
      enabled: configured.enabled !== false,
      mode: String(configured.mode || "automatic"),
      scope: String(configured.scope || altTab.scope || "current-workspace"),
      maxCards: Number(configured.maxCards || 32),
      closeOnSwipe: configured.closeOnSwipe === true,
      touchSwipe: configured.touchSwipe !== false && altTab.touchSwipe !== false,
      swipeThresholdPx: Number(configured.swipeThresholdPx || 96),
      swipeVelocity: Number(configured.swipeVelocity || 0.5),
      closeThresholdPx: Number(configured.closeThresholdPx || 120),
      selectedScale: Number(configured.selectedScale || 1.0),
      sideScale: Number(configured.sideScale || 0.92),
      sideOpacity: Number(configured.sideOpacity || 0.76)
    }
  }

  function tabletSwitcherMode() {
    var options = root.tabletSwitcherOptions()
    if (options.enabled === false || root.cfg("multitasking.enabled", true) === false) return false
    if (options.mode === "always") return true
    if (options.mode === "never") return false
    return root.effectiveMode === "tablet" || root.effectiveMode === "hybrid" || root.lastInput === "touch" || root.lastInput === "stylus"
  }

  function tabletSwitcherCards(windows, context) {
    if (!root.tabletSwitcherMode()) return []
    var cards = TabletSwitcherModel.selectable(windows, root.tabletSwitcherOptions(), context || {})
    root.tabletSwitcherState = Object.assign({}, root.tabletSwitcherState, { phase: "ready", cardCount: cards.length, reason: "cards-refreshed" })
    root.tabletSwitcherRevision++
    return cards
  }

  function beginTabletSwitcherSwipe(index, point) {
    root.tabletSwitcherState = TabletSwitcherModel.begin(root.tabletSwitcherState, index, point, root.tabletSwitcherOptions(), Date.now())
    root.tabletSwitcherRevision++
    return root.tabletSwitcherState
  }

  function updateTabletSwitcherSwipe(point) {
    root.tabletSwitcherState = TabletSwitcherModel.update(root.tabletSwitcherState, point, root.tabletSwitcherOptions(), Date.now())
    root.tabletSwitcherRevision++
    return root.tabletSwitcherState
  }

  function endTabletSwitcherSwipe(point, velocity, index, window) {
    var result = TabletSwitcherModel.end(root.tabletSwitcherState, point, velocity, root.tabletSwitcherOptions(), Date.now())
    root.tabletSwitcherState = result.state
    root.tabletSwitcherRevision++
    if (result.decision.action === "close" && root.tabletSwitcherOptions().closeOnSwipe === true) {
      var target = window || root.clients[Math.max(0, Math.min(root.clients.length - 1, Number(index === undefined ? result.state.index : index)))]
      result.closed = root.closeSwitcherWindow(target)
    }
    return result
  }

  function tabletSwitcherSummary() {
    var state = TabletSwitcherModel.summary(root.tabletSwitcherState)
    state.mode = root.tabletSwitcherMode() ? "large-cards" : "coverflow"
    state.enabled = root.tabletSwitcherOptions().enabled === true
    return state
  }

  function currentWorkspaceId() {
    var active = root.activeClient() || {}
    var workspace = active.workspace
    if (workspace && typeof workspace === "object") workspace = workspace.id !== undefined ? workspace.id : workspace.name
    if (workspace === undefined || workspace === null || workspace === "") workspace = active.workspaceId
    if (workspace !== undefined && workspace !== null && workspace !== "") return String(workspace)
    var clients = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < clients.length; i++) {
      var item = clients[i] || {}
      var value = item.workspace
      if (value && typeof value === "object") value = value.id !== undefined ? value.id : value.name
      if (value !== undefined && value !== null && value !== "") return String(value)
    }
    return "1"
  }

  function workspaceSwitcherIds() {
    var result = []
    var seen = {}
    var clients = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < clients.length; i++) {
      var item = clients[i] || {}
      var value = item.workspace
      if (value && typeof value === "object") value = value.id !== undefined ? value.id : value.name
      if (value === undefined || value === null || value === "") value = item.workspaceId
      var id = String(value === undefined || value === null ? "" : value)
      if (!id || seen[id]) continue
      seen[id] = true
      result.push(id)
    }
    var active = root.currentWorkspaceId()
    if (!seen[active]) { seen[active] = true; result.push(active) }
    var numeric = result.every(function(value) { return /^\d+$/.test(String(value)) })
    if (numeric) {
      result.sort(function(left, right) { return Number(left) - Number(right) })
      if (root.cfg("multitasking.workspaceNavigation.activateEmpty", true) !== false) {
        var next = String(Math.max(1, Number(active)) + 1)
        if (!seen[next] && result.length < WorkspaceSwitcherModel.MAX_WORKSPACES) result.push(next)
      }
    }
    return result.slice(0, WorkspaceSwitcherModel.MAX_WORKSPACES)
  }

  function workspaceSwitcherOptions() {
    var navigation = root.cfg("multitasking.workspaceNavigation", {})
    var gestures = root.cfg("multitasking.gestures", {})
    return {
      enabled: root.enhancementsActive() && root.cfg("multitasking.enabled", true) !== false && gestures.enabled !== false,
      showOverlay: navigation.showOverlay !== false,
      maxWorkspaces: WorkspaceSwitcherModel.MAX_WORKSPACES,
      thresholdPx: Math.max(1, Number(root.cfg("touch.threshold", 96))),
      velocityThreshold: Math.max(0, Number(root.cfg("touch.velocity", 0.35))),
      reducedMotion: root.cfg("general.reduceMotion", false) === true || root.cfg("accessibility.reducedMotion", false) === true || root.cfg("animations.reducedMotion", false) === true
    }
  }

  function workspaceSwitcherCards(workspaces, context) {
    var options = root.workspaceSwitcherOptions()
    var state = Object.assign({}, context || {}, { activeId: (context && context.activeId) || root.currentWorkspaceId(), livePreview: root.livePreviewState.available === true })
    return WorkspaceSwitcherModel.cards(workspaces, options, state)
  }

  function showWorkspaceSwitcher(direction) {
    var options = root.workspaceSwitcherOptions()
    if (options.enabled !== true || options.showOverlay !== true) return false
    var active = root.currentWorkspaceId()
    root.workspaceSwitcherState = WorkspaceSwitcherModel.begin(root.workspaceSwitcherState, active, direction, root.workspaceSwitcherIds(), Date.now(), options)
    root.workspaceSwitcherRevision++
    if (root.panel && typeof root.panel.showWorkspaceOverlay === "function") root.panel.showWorkspaceOverlay()
    else root.open("workspace-overlay")
    return true
  }

  function beginWorkspaceSwitcherSwipe(direction) {
    var options = root.workspaceSwitcherOptions()
    root.workspaceSwitcherState = WorkspaceSwitcherModel.begin(root.workspaceSwitcherState, root.currentWorkspaceId(), direction, root.workspaceSwitcherIds(), Date.now(), options)
    root.workspaceSwitcherRevision++
    return root.workspaceSwitcherState
  }

  function updateWorkspaceSwitcherSwipe(distance, width) {
    root.workspaceSwitcherState = WorkspaceSwitcherModel.update(root.workspaceSwitcherState, distance, width, Date.now(), root.workspaceSwitcherOptions())
    root.workspaceSwitcherRevision++
    return root.workspaceSwitcherState
  }

  function endWorkspaceSwitcherSwipe(distance, velocity) {
    var result = WorkspaceSwitcherModel.end(root.workspaceSwitcherState, distance, velocity, root.workspaceSwitcherOptions(), Date.now())
    root.workspaceSwitcherState = result.state
    root.workspaceSwitcherRevision++
    if (result.decision && result.decision.action === "workspace-focus") root.workspaceSwitcherFocus(result.decision.workspaceId)
    return result
  }

  function workspaceSwitcherFocus(workspaceId) {
    var id = String(workspaceId || "")
    if (!id) return false
    var accepted = root.dispatch("workspace " + id)
    root.workspaceSwitcherState = Object.assign({}, root.workspaceSwitcherState, { phase: accepted ? "committed" : "failed", targetId: id, progress: accepted ? 1 : 0, committed: accepted, reason: accepted ? "workspace-dispatched" : "workspace-dispatch-rejected" })
    root.workspaceSwitcherRevision++
    return accepted
  }

  function workspaceSwitcherSummary() {
    var summary = WorkspaceSwitcherModel.summary(root.workspaceSwitcherState)
    summary.enabled = root.workspaceSwitcherOptions().enabled === true
    summary.overlay = root.workspaceSwitcherOptions().showOverlay === true
    return summary
  }

  function multitaskingShortcutEntries() {
    return MultitaskingShortcutsModel.ACTIONS.map(function(action) {
      return { key: action, labelKey: action, binding: root.cfg("multitasking.shortcuts." + action, MultitaskingShortcutsModel.DEFAULTS[action]) }
    })
  }

  function shortcutConflictText() {
    var state = root.shortcutConflictState || {}
    if (String(state.status || "not-checked") === "not-checked") return root.tr("shortcutConflictNotChecked", "External Hyprland bindings have not been checked")
    if (String(state.status || "") === "unavailable") return root.tr("shortcutConflictUnavailable", "Hyprland bindings are unavailable in this session")
    var count = Array.isArray(state.conflicts) ? state.conflicts.length : 0
    return count > 0 ? root.tr("shortcutConflictFound", "Shortcut conflicts found") + ": " + count : root.tr("shortcutConflictFree", "No shortcut conflicts found")
  }

  function updateShortcutConflicts(raw) {
    var parsed = root.parseJson(raw, null)
    if (!Array.isArray(parsed)) {
      root.shortcutConflictState = Object.assign({}, MultitaskingShortcutsModel.emptyState(), { status: "unavailable", reason: "invalid-hyprland-bindings" })
    } else {
      root.shortcutConflictState = MultitaskingShortcutsModel.report(root.cfg("multitasking.shortcuts", {}), root.cfg("shortcuts", {}), parsed)
    }
    root.shortcutConflictRunning = false
    root.shortcutConflictRevision++
    root.stateUpdated()
  }

  function checkShortcutConflicts() {
    if (root.shortcutConflictRunning) return false
    if (!root.hyprlandAvailable) {
      root.shortcutConflictState = Object.assign({}, MultitaskingShortcutsModel.emptyState(), { status: "unavailable", reason: "hyprland-unavailable" })
      root.shortcutConflictRevision++
      root.stateUpdated()
      return false
    }
    root.shortcutConflictRunning = true
    shortcutBindsProcess.command = ["hyprctl", "-j", "binds"]
    shortcutBindsProcess.running = true
    return true
  }

  function executeMultitaskingShortcut(action) {
    var name = String(action || "")
    if (root.safeMode) return root.multitaskingRecord({ type: "shortcut", ok: false, action: name, reason: "safe-mode" })
    var active = root.multitaskingForeign(root.activeClient())
    if (name === "snap-left" || name === "snap-right")
      return root.snapWindowToZone(active, root.multitaskingHalfZone(active, name === "snap-left" ? "start" : "end"), "mouse", {})
    if (name === "next-layout") {
      var zones = root.availableSnapZones("mouse", {}).filter(function(zone) { return ["half-left", "half-right", "half-top", "half-bottom", "quarter-top-left", "quarter-top-right", "quarter-bottom-left", "quarter-bottom-right", "maximized"].indexOf(String(zone.id)) >= 0 })
      if (zones.length === 0) return root.multitaskingRecord({ type: "shortcut", ok: false, action: name, reason: "no-layout-zones" })
      root.multitaskingLayoutShortcutIndex = (root.multitaskingLayoutShortcutIndex + 1) % zones.length
      return root.snapWindowToZone(active, zones[root.multitaskingLayoutShortcutIndex].id, "mouse", {})
    }
    if (name === "toggle-float") return root.toggleWindowFloating(active)
    if (name === "break-pair") {
      var group = root.windowGroupForWindow(active)
      return group ? root.breakWindowGroup(group.id) : root.multitaskingRecord({ type: "shortcut", ok: false, action: name, reason: "group-not-found" })
    }
    if (name === "create-pair") {
      var pair = root.splitViewWindows.length === 2 ? root.splitViewWindows : []
      return pair.length === 2 ? root.createWindowGroup("app-pair", pair, { ratio: root.splitViewState && root.splitViewState.ratioName || "50/50" }) : root.multitaskingRecord({ type: "shortcut", ok: false, action: name, reason: "split-pair-required" })
    }
    if (name === "move-pair-workspace") {
      var activeGroup = root.windowGroupForWindow(active)
      if (!activeGroup || !activeGroup.runtime || !Array.isArray(activeGroup.runtime.memberIds)) return root.multitaskingRecord({ type: "shortcut", ok: false, action: name, reason: "group-not-found" })
      var moved = 0
      for (var i = 0; i < activeGroup.runtime.memberIds.length; i++) {
        var member = root.windowForMultitaskingId(activeGroup.runtime.memberIds[i])
        var address = root.multitaskingAddress(member)
        if (address && root.dispatch("movetoworkspace e+1,address:" + address)) moved++
      }
      return root.multitaskingRecord({ type: "shortcut", ok: moved === activeGroup.runtime.memberIds.length, action: name, moved: moved, members: activeGroup.runtime.memberIds.length })
    }
    return root.multitaskingRecord({ type: "shortcut", ok: false, action: name, reason: "unknown-action" })
  }

  function layoutPersistenceSummary() {
    return LayoutPersistenceModel.summary(root.layoutPersistenceState)
  }

  function multitaskingOptions() {
    var snap = root.cfg("multitasking.snapAssist", {})
    var split = root.cfg("multitasking.splitView", {})
    var customLayouts = root.cfg("multitasking.customLayouts", [])
    var active = root.enhancementsActive() && root.cfg("multitasking.enabled", true) !== false
    return {
      enabled: active && snap.enabled !== false,
      snapAssistEnabled: active && snap.enabled !== false,
      splitViewEnabled: active && split.enabled !== false,
      gap: Number(root.cfg("multitasking.gap", 12)),
      layouts: root.cfg("multitasking.layouts", []),
      customLayouts: Array.isArray(customLayouts) ? customLayouts : [],
      touchDwellMs: Number(snap.dwellMs !== undefined ? snap.dwellMs : root.cfg("multitasking.snapAssist.dwellMs", 220)),
      touchMovementThreshold: Number(snap.movementThreshold !== undefined ? snap.movementThreshold : root.cfg("multitasking.snapAssist.movementThreshold", 18)),
      stylusDwellMs: Number(snap.stylusDwellMs !== undefined ? snap.stylusDwellMs : root.cfg("multitasking.snapAssist.stylusDwellMs", 120)),
      portraitLayouts: snap.portraitLayouts !== false && root.cfg("multitasking.snapAssist.portraitLayouts", true) !== false,
      autoSecondWindowPicker: snap.autoSecondWindowPicker !== false && root.cfg("multitasking.snapAssist.autoSecondWindowPicker", true) !== false,
      dividerEnabled: split.divider !== false && root.cfg("multitasking.splitView.divider", true) !== false,
      dividerAutoHide: split.autoHide !== false && root.cfg("multitasking.splitView.autoHide", true) !== false,
      dividerAutoHideMs: Number(split.autoHideMs !== undefined ? split.autoHideMs : root.cfg("multitasking.splitView.autoHideMs", 1800)),
      dividerHandleSize: Number(split.handleSize !== undefined ? split.handleSize : root.cfg("multitasking.splitView.handleSize", 48)),
      defaultRatio: String(split.defaultRatio || root.cfg("multitasking.splitView.defaultRatio", "50/50")),
      minSize: root.cfg("multitasking.minimumWindowSize", {}),
      groupClosePolicy: String(root.cfg("multitasking.closePolicy", "keep")),
      groupMonitorPolicy: String(root.cfg("multitasking.monitorPolicy", "active")),
      duplicatePolicy: String(root.cfg("multitasking.duplicatePolicy", "ask")),
      launchTimeoutMs: Math.max(500, Math.min(15000, Number(root.cfg("multitasking.launchTimeoutMs", 12000)))),
      floating: root.cfg("multitasking.floating", {}),
      gestures: root.cfg("multitasking.gestures", {}),
      workspaceNavigation: root.cfg("multitasking.workspaceNavigation", {}),
      multiMonitor: root.cfg("multitasking.multiMonitor", {}),
      sessionRestore: WindowGroupsModel.restorePolicy(root.cfg("multitasking.sessionRestore", "ask"))
    }
  }

  function multitaskingFallbackMonitor() {
    var responsive = root.responsiveState || {}
    return {
      name: "active",
      x: 0,
      y: 0,
      width: Math.max(1, Number(responsive.logicalWidth || responsive.width || 1280)),
      height: Math.max(1, Number(responsive.logicalHeight || responsive.height || 720)),
      scale: Number(responsive.scale || 1)
    }
  }

  function multitaskingMonitors() {
    return Array.isArray(root.monitors) && root.monitors.length > 0 ? root.monitors : [root.multitaskingFallbackMonitor()]
  }

  function multitaskingForeign(window) {
    return window && window.wayland ? window.wayland : window
  }

  function multitaskingWindowIdentity(window) {
    return SnapAssistModel.windowIdentity(window)
  }

  function multitaskingMonitorForWindow(window, point) {
    var monitors = root.multitaskingMonitors()
    var item = root.multitaskingForeign(window) || {}
    var requested = String(item.monitorName || item.monitor || item.output || "")
    if (requested) {
      for (var i = 0; i < monitors.length; i++) {
        if (String(monitors[i].name || monitors[i].monitor || monitors[i].output || "") === requested) return monitors[i]
      }
    }
    if (point) {
      var byPoint = SnapAssistModel.findMonitor(monitors, point)
      if (byPoint) return byPoint
    }
    return monitors.length > 0 ? monitors[0] : root.multitaskingFallbackMonitor()
  }

  function multitaskingTouchInput(kind) {
    return SnapAssistModel.inputKind(kind)
  }

  // Gesture ownership is resolved once at contact time and released at end or
  // cancel. The coordinator receives only transient capability/context flags;
  // no window title, document name or runtime identity is retained in the
  // gesture state.
  function gestureContext(overrides) {
    var active = root.activeClient() || {}
    var rules = root.appRuleDecision()
    var base = {
      activeWindow: active,
      fullscreen: root.fullscreenActive(),
      drawing: active.drawing === true || active.drawingApp === true,
      game: active.game === true || active.gameMode === true || active.isGame === true,
      osk: root.inputTextFocusActive === true || root.oskPolicyState.visible === true,
      overviewOpen: root.panel && root.panel.opened === true && String(root.panel.activeView || "") === "overview",
      floatingDrag: root.snapAssistState.active === true || (root.splitViewState && String(root.splitViewState.phase || "") === "dragging"),
      stylus: root.lastInput === "stylus" || root.stylusInputState.contact === true || root.stylusInputState.proximity === true,
      appRuleDisabled: rules.disableGestures === true,
      backShortcut: root.cfg("multitasking.gestures.backShortcut", ""),
      systemEdge: false
    }
    return Object.assign(base, overrides || {})
  }

  function gestureRecord(action) {
    root.gestureLastAction = action || { type: "gesture", ok: false, reason: "unknown" }
    root.gestureRevision++
    root.stateUpdated()
    return action
  }

  function gestureShortcut(shortcut) {
    var parts = String(shortcut || "").split("+").map(function(value) { return String(value || "").trim() }).filter(function(value) { return value !== "" })
    if (parts.length === 0) return false
    var key = parts.pop()
    var modifiers = []
    for (var i = 0; i < parts.length; i++) {
      var modifier = parts[i].toLowerCase()
      if (modifier === "super" || modifier === "meta") modifier = "super"
      else if (modifier === "control" || modifier === "ctrl") modifier = "ctrl"
      else if (modifier === "alt") modifier = "alt"
      else if (modifier === "shift") modifier = "shift"
      else continue
      modifiers.push(modifier)
    }
    if (key.toLowerCase() === "space") key = "space"
    else if (key.toLowerCase() === "esc") key = "Escape"
    else if (key.toLowerCase() === "left") key = "Left"
    else if (key.toLowerCase() === "right") key = "Right"
    else if (key.toLowerCase() === "up") key = "Up"
    else if (key.toLowerCase() === "down") key = "Down"
    return root.sendModifiedKey(key, modifiers)
  }

  function performGestureAction(action) {
    var source = action || {}
    var name = String(source.action || "")
    if (name === "overview" || name === "quick-settings" || name === "notifications") {
      var view = name === "quick-settings" ? "quicksettings" : name
      if (root.panel) {
        root.panel.activeView = view
        root.panel.opened = true
        return { ok: true, type: "gesture", action: name, owner: source.owner || "" }
      }
      var opened = root.open(view)
      return { ok: opened, type: "gesture", action: name, owner: source.owner || "", reason: opened ? "opened" : "open-rejected" }
    }
    if (name === "dock") {
      root.gestureActionRequested("dock")
      return { ok: true, type: "gesture", action: name, owner: source.owner || "" }
    }
    if (name === "workspace-next" || name === "workspace-previous") {
      var direction = name === "workspace-next" ? "next" : "previous"
      root.showWorkspaceSwitcher(direction)
      var target = String(root.workspaceSwitcherState.targetId || "")
      var workspaceCommand = target ? "workspace " + target : (direction === "next" ? "workspace e+1" : "workspace e-1")
      var dispatched = root.dispatch(workspaceCommand)
      root.workspaceSwitcherState = Object.assign({}, root.workspaceSwitcherState, { phase: dispatched ? "committed" : "failed", progress: dispatched ? 1 : 0, committed: dispatched, reason: dispatched ? "workspace-dispatched" : "workspace-dispatch-rejected" })
      root.workspaceSwitcherRevision++
      return { ok: dispatched, type: "gesture", action: name, owner: source.owner || "", reason: root.hyprlandAvailable ? (dispatched ? "workspace-dispatched" : "workspace-dispatch-rejected") : "hyprland-unavailable" }
    }
    if (name === "back") {
      if (String(source.backend || "") === "shortcut" && source.shortcut)
        return { ok: root.gestureShortcut(source.shortcut), type: "gesture", action: name, owner: source.owner || "", reason: "shortcut" }
      if (String(source.backend || "") === "backend") {
        root.gestureActionRequested("back")
        return { ok: true, type: "gesture", action: name, owner: source.owner || "", reason: "backend-requested" }
      }
      return { ok: false, type: "gesture", action: name, owner: source.owner || "", reason: "back-backend-unavailable" }
    }
    return { ok: false, type: "gesture", action: name, owner: source.owner || "", reason: "action-disabled" }
  }

  function beginGesture(inputKind, edge, point, options) {
    var settings = root.cfg("multitasking.gestures", {})
    var source = Object.assign({}, options || {})
    source.inputKind = inputKind || source.inputKind || root.lastInput
    source.edge = edge || source.edge || ""
    source.point = point || source.point || { x: 0, y: 0 }
    var monitor = root.focusedMonitor()
    if (source.width === undefined) source.width = Number(monitor.width || 0)
    if (source.height === undefined) source.height = Number(monitor.height || 0)
    if (source.edgeWidth === undefined) source.edgeWidth = Number(root.cfg("touch.edgeWidth", 36))
    if (!root.enhancementsActive() || settings.enabled === false) {
      root.gestureState = GestureCoordinatorModel.cancel(root.gestureState, !root.enhancementsActive() ? "enhancements-disabled" : "gestures-disabled")
      return root.gestureState
    }
    root.recordInput(source.inputKind)
    var result = GestureCoordinatorModel.begin(source, settings, root.gestureContext(source.context || {}), Date.now(), root.gestureState)
    root.gestureState = result
    if (result.phase === "suppressed") root.gestureLastAction = { type: "gesture", ok: false, reason: String(result.reason || "gesture-rejected"), owner: String(result.owner || "") }
    root.gestureRevision++
    root.stateUpdated()
    return result
  }

  function updateGesture(point, options) {
    if (!GestureCoordinatorModel.active(root.gestureState)) return root.gestureState
    var source = Object.assign({}, options || {})
    source.point = point || source.point || root.gestureState.point
    root.gestureState = GestureCoordinatorModel.update(root.gestureState, source, Date.now())
    root.gestureRevision++
    root.stateUpdated()
    return root.gestureState
  }

  function endGesture(point, options) {
    if (!GestureCoordinatorModel.active(root.gestureState)) return root.gestureRecord({ type: "gesture", ok: false, reason: "gesture-not-active" })
    var source = Object.assign({}, options || {})
    source.point = point || source.point || root.gestureState.point
    var result = GestureCoordinatorModel.end(root.gestureState, source, root.gestureContext(source.context || {}), Date.now())
    root.gestureState = result.state
    var actionResult = result.ok && result.action ? root.performGestureAction(result.action) : { ok: false, type: "gesture", reason: String(result.reason || "gesture-cancelled") }
    var record = {
      type: "gesture",
      ok: result.ok === true && actionResult.ok === true,
      owner: String(result.state.owner || ""),
      action: result.action ? String(result.action.action || "") : "",
      reason: result.ok ? String(actionResult.reason || (actionResult.ok ? "committed" : "action-rejected")) : String(result.reason || "gesture-cancelled")
    }
    root.gestureRevision++
    root.gestureLastAction = record
    root.stateUpdated()
    return { ok: record.ok, state: result.state, action: result.action, result: actionResult, reason: record.reason }
  }

  function cancelGesture(reason) {
    root.gestureState = GestureCoordinatorModel.cancel(root.gestureState, reason || "cancelled")
    return root.gestureRecord({ type: "gesture", ok: false, reason: String(root.gestureState.reason || "cancelled"), owner: String(root.gestureState.owner || "") })
  }

  function gestureAvailableOwners(inputKind, options) {
    return GestureCoordinatorModel.availableOwners(root.cfg("multitasking.gestures", {}), root.gestureContext(options || {}), inputKind || root.lastInput)
  }

  function gestureSummary() {
    return GestureCoordinatorModel.summary(root.gestureState)
  }

  function multitaskingRecord(action) {
    root.multitaskingLastAction = action || { type: "none", ok: false, reason: "unknown" }
    root.multitaskingError = action && action.ok === false ? String(action.reason || "unavailable") : ""
    root.multitaskingRevision++
    root.stateUpdated()
    return action
  }

  function floatingWindowState(window) {
    return FloatingWindowsModel.normalizeWindow(window)
  }

  function applyFloatingPlan(plan) {
    var source = plan || {}
    if (source.ok !== true) {
      root.floatingLastAction = { type: "floating-window", ok: false, reason: String(source.reason || "invalid-plan") }
      root.floatingRevision++
      return root.multitaskingRecord(root.floatingLastAction)
    }
    var commands = Array.isArray(source.commands) ? source.commands.slice(0, FloatingWindowsModel.MAX_COMMANDS) : []
    var applied = []
    var failed = false
    for (var i = 0; i < commands.length; i++) {
      if (!root.dispatch(commands[i])) { failed = true; break }
      applied.push(commands[i])
    }
    var rolledBack = false
    if (failed) {
      var rollback = Array.isArray(source.rollback) ? source.rollback.slice(0, FloatingWindowsModel.MAX_COMMANDS) : []
      for (var j = 0; j < rollback.length; j++) if (root.dispatch(rollback[j])) rolledBack = true
    }
    root.floatingLastAction = {
      type: "floating-window",
      ok: !failed && applied.length === commands.length,
      reason: failed ? "dispatch-rejected" : "queued",
      mode: String(source.mode || "toggle"),
      identity: String(source.identity || ""),
      appId: String(source.appId || ""),
      monitor: String(source.monitor || ""),
      target: source.target || null,
      commands: applied,
      rolledBack: rolledBack
    }
    root.floatingRevision++
    return root.multitaskingRecord(root.floatingLastAction)
  }

  function toggleWindowFloating(window) {
    if (root.cfg("multitasking.enabled", true) === false || root.cfg("multitasking.floating.enabled", true) === false)
      return root.multitaskingRecord({ type: "floating-window", ok: false, reason: "disabled" })
    return root.applyFloatingPlan(FloatingWindowsModel.toggleFloating(window))
  }

  function setWindowMini(window, options) {
    if (root.cfg("multitasking.enabled", true) === false || root.cfg("multitasking.floating.miniEnabled", true) === false)
      return root.multitaskingRecord({ type: "floating-window", ok: false, reason: "mini-disabled" })
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    var monitor = settings.monitor || root.multitaskingMonitorForWindow(window)
    return root.applyFloatingPlan(FloatingWindowsModel.mini(window, monitor, settings))
  }

  function setWindowPictureInPicture(window, options) {
    if (root.cfg("multitasking.enabled", true) === false || root.cfg("multitasking.floating.pictureInPicture", true) === false)
      return root.multitaskingRecord({ type: "floating-window", ok: false, reason: "pip-disabled" })
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    var monitor = settings.monitor || root.multitaskingMonitorForWindow(window)
    return root.applyFloatingPlan(FloatingWindowsModel.pip(window, monitor, settings))
  }

  function windowGroupById(groupId) {
    var wanted = String(groupId || "")
    var list = Array.isArray(root.windowGroups) ? root.windowGroups : []
    for (var i = 0; i < list.length; i++) if (list[i] && String(list[i].id || "") === wanted) return list[i]
    return null
  }

  function windowGroupForWindow(window) {
    var identity = root.multitaskingWindowIdentity(window)
    if (!identity) return null
    var list = Array.isArray(root.windowGroups) ? root.windowGroups : []
    for (var i = 0; i < list.length; i++) {
      var members = list[i] && list[i].runtime ? list[i].runtime.memberIds : []
      if (Array.isArray(members) && members.indexOf(identity) >= 0) return list[i]
    }
    return null
  }

  function windowGroupSummaries() {
    var list = Array.isArray(root.windowGroups) ? root.windowGroups : []
    return list.slice(0, WindowGroupsModel.MAX_GROUPS).map(function(group) {
      var item = group || {}
      var layout = item.layout || {}
      var runtime = item.runtime || {}
      return {
        id: String(item.id || ""),
        type: String(item.type || "split-pair"),
        name: String(item.name || "Window group"),
        apps: Array.isArray(item.apps) ? item.apps.slice(0, WindowGroupsModel.MAX_MEMBERS) : [],
        persistent: item.persistent !== false,
        status: String(runtime.status || "idle"),
        memberCount: Array.isArray(runtime.memberIds) ? runtime.memberIds.length : 0,
        layout: { id: String(layout.id || "split"), orientation: String(layout.orientation || "auto"), ratio: String(layout.ratio || "50/50") },
        targetWorkspace: String(item.preferences && item.preferences.targetWorkspace || ""),
        monitorPolicy: String(item.preferences && item.preferences.monitorPolicy || "active")
      }
    })
  }

  function windowGroupRestoreSummary() {
    var plan = root.windowGroupRestorePlan || {}
    return {
      policy: String(plan.decision && plan.decision.policy || root.cfg("multitasking.sessionRestore", "ask")),
      reason: String(plan.decision && plan.decision.reason || "not-prepared"),
      requiresConfirmation: plan.decision && plan.decision.requiresConfirmation === true,
      plans: Array.isArray(plan.plans) ? plan.plans.slice(0, WindowGroupsModel.MAX_GROUPS) : []
    }
  }

  function createWindowGroup(type, windows, options) {
    var settings = Object.assign({}, options || {})
    var kind = String(type || settings.type || "split-pair")
    if (root.cfg("multitasking.enabled", true) === false)
      return root.multitaskingRecord({ type: "group-create", ok: false, reason: "disabled" })
    if (root.safeMode && kind === "app-pair")
      return root.multitaskingRecord({ type: "group-create", ok: false, reason: "safe-mode" })
    var result = WindowGroupsModel.createGroup(kind, windows, settings, Date.now())
    if (result.ok !== true)
      return root.multitaskingRecord({ type: "group-create", ok: false, reason: result.reason || "invalid-group" })
    var next = Array.isArray(root.windowGroups) ? root.windowGroups.filter(function(group) { return String(group.id || "") !== String(result.group.id) }) : []
    next.push(result.group)
    root.windowGroups = WindowGroupsModel.normalizeList(next)
    if (result.group.persistent !== false) root.persistWindowGroups()
    if (result.group.type === "app-pair") root.rememberManagedLayout(result.group, "saved")
    root.multitaskingRecord({ type: "group-create", ok: true, groupId: result.group.id, groupType: result.group.type, appCount: result.group.apps.length, memberCount: result.group.runtime.memberIds.length })
    return result.group
  }

  function saveAppPair(appIds, options) {
    var settings = Object.assign({}, options || {}, { apps: Array.isArray(appIds) ? appIds : [], persistent: true })
    return root.createWindowGroup("app-pair", [], settings)
  }

  function removeWindowGroup(groupId) {
    var group = root.windowGroupById(groupId)
    if (!group) return root.multitaskingRecord({ type: "group-remove", ok: false, reason: "group-not-found" })
    root.windowGroups = WindowGroupsModel.removeGroup(root.windowGroups, group.id)
    root.persistWindowGroups()
    if (group.type === "app-pair") root.removePersistedLayout(group.id)
    return root.multitaskingRecord({ type: "group-remove", ok: true, groupId: group.id })
  }

  function breakWindowGroup(groupId) {
    return root.removeWindowGroup(groupId)
  }

  function updateWindowGroupRuntime(groupId, windows) {
    var group = root.windowGroupById(groupId)
    if (!group) return { ok: false, reason: "group-not-found" }
    var outcome = WindowGroupsModel.reconcileGroup(group, windows, Date.now(), { duplicatePolicy: "ask" })
    var next = Array.isArray(root.windowGroups) ? root.windowGroups.slice() : []
    for (var i = 0; i < next.length; i++) {
      if (String(next[i].id || "") === String(groupId)) { next[i] = outcome.group; break }
    }
    root.windowGroups = WindowGroupsModel.normalizeList(next)
    return outcome
  }

  function reconcileWindowGroups() {
    var result = WindowGroupsModel.reconcile(
      root.windowGroups,
      root.clients,
      Date.now(),
      { duplicatePolicy: root.cfg("multitasking.duplicatePolicy", "ask") }
    )
    root.windowGroups = result.groups
    root.windowGroupEvents = result.events || []
    for (var i = 0; i < root.windowGroupEvents.length; i++) {
      var event = root.windowGroupEvents[i]
      if (!event || event.type !== "break" || !root.splitViewState || root.splitViewWindows.length < 1) continue
      var splitGroup = root.windowGroupForWindow(root.splitViewWindows[0])
      if (splitGroup && splitGroup.id === event.groupId) {
        root.splitViewState = null
        root.splitViewWindows = []
      }
    }
    if (result.events && result.events.length > 0) root.multitaskingRevision++
    return result
  }

  function syncSplitWindowGroup(windows, options) {
    var list = Array.isArray(windows) ? windows.slice(0, 2) : []
    var settings = Object.assign({}, options || {})
    var created = WindowGroupsModel.createGroup("split-pair", list, {
      id: settings.id || ("split-runtime-" + String(root.multitaskingRevision + 1)),
      ratio: settings.ratio || settings.defaultRatio || root.cfg("multitasking.splitView.defaultRatio", "50/50"),
      persistent: settings.persistent === true
    }, Date.now())
    if (created.ok !== true) return false
    var wanted = created.group.runtime.memberIds.slice().sort().join("|")
    var next = Array.isArray(root.windowGroups) ? root.windowGroups.slice() : []
    var found = -1
    for (var i = 0; i < next.length; i++) {
      var current = next[i] || {}
      var currentIds = current.runtime && Array.isArray(current.runtime.memberIds) ? current.runtime.memberIds.slice().sort().join("|") : ""
      if (current.type === "split-pair" && currentIds && currentIds === wanted) { found = i; break }
    }
    if (found < 0) next.push(created.group)
    else {
      var existing = next[found]
      next[found] = WindowGroupsModel.normalizeGroup(Object.assign({}, existing, {
        layout: Object.assign({}, existing.layout || {}, { ratio: created.group.layout.ratio }),
        runtime: created.group.runtime,
        updatedAt: Date.now()
      }), found)
    }
    root.windowGroups = WindowGroupsModel.normalizeList(next)
    return root.windowGroups[found < 0 ? root.windowGroups.length - 1 : found]
  }

  function multitaskingWindowsForApp(appId) {
    var key = WindowMatcherModel.appId(appId)
    var result = []
    var list = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < list.length; i++) {
      if (WindowMatcherModel.appId(list[i]) !== key) continue
      if (root.multitaskingWindowIdentity(list[i])) result.push(list[i])
    }
    return result
  }

  function startNextMultitaskingPairLaunch() {
    var state = root.multitaskingPairLaunch
    if (!state) return { ok: false, reason: "pair-launch-unavailable" }
    var index = Math.max(0, Math.floor(Number(state.nextIndex || 0)))
    while (index < state.appIds.length && state.windowIds[index]) index++
    if (index >= state.appIds.length) return root.finishMultitaskingPairLaunch(true, "all-apps-ready")
    var now = Date.now()
    var remaining = Math.max(0, Number(state.deadline || 0) - now)
    if (remaining < 500) return root.finishMultitaskingPairLaunch(false, "launch-timeout")
    var request = WindowMatcherModel.begin(state.appIds[index], root.clients, now, {
      timeoutMs: Math.min(Number(state.timeoutMs || 12000), remaining),
      workspaceId: state.workspaceId,
      monitorName: state.monitorName
    })
    if (request.status !== "pending") return root.finishMultitaskingPairLaunch(false, request.reason || "launch-request-rejected")
    state.nextIndex = index
    state.phase = "launching"
    state.currentAppId = state.appIds[index]
    root.multitaskingPairLaunch = state
    root.multitaskingLaunch = request
    root.multitaskingLaunchTarget = { type: "pair", groupId: state.groupId, index: index, appId: state.appIds[index] }
    if (!root.launchApp(state.appIds[index])) {
      root.multitaskingLaunch = null
      root.multitaskingLaunchTarget = null
      return root.finishMultitaskingPairLaunch(false, "launch-rejected")
    }
    multitaskingLaunchTimeout.interval = request.timeoutMs
    multitaskingLaunchTimeout.restart()
    return { ok: true, pending: true, appId: state.appIds[index], deadline: request.deadline, index: index }
  }

  function finishMultitaskingPairLaunch(ok, reason) {
    var state = root.multitaskingPairLaunch
    if (!state) return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: "pair-launch-unavailable" })
    multitaskingLaunchTimeout.stop()
    root.multitaskingLaunch = null
    root.multitaskingLaunchTarget = null
    root.multitaskingPairLaunch = null
    var windows = []
    var missing = []
    for (var i = 0; i < state.appIds.length; i++) {
      var window = state.windowIds[i] ? root.windowForMultitaskingId(state.windowIds[i]) : null
      if (window) windows.push(window)
      else missing.push(state.appIds[i])
    }
    if (!ok || missing.length > 0) {
      if (windows.length > 0) root.updateWindowGroupRuntime(state.groupId, windows)
      return root.multitaskingRecord({ type: "app-pair-launch", ok: false, partial: windows.length > 0, reason: reason || "launch-incomplete", groupId: state.groupId, missingApps: missing })
    }
    var settings = Object.assign({}, state.options || {}, { ratio: state.ratio, defaultRatio: state.ratio })
    var applied = root.splitWindows(windows, settings)
    if (applied) root.updateWindowGroupRuntime(state.groupId, windows)
    return root.multitaskingRecord({ type: "app-pair-launch", ok: applied === true, reason: applied ? "committed" : "split-apply-failed", groupId: state.groupId, appCount: windows.length })
  }

  function launchAppPair(groupId, options) {
    var group = root.windowGroupById(groupId)
    if (!group || group.type !== "app-pair") return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: "app-pair-not-found" })
    if (!root.enhancementsActive() || root.cfg("multitasking.enabled", true) === false || root.cfg("multitasking.splitView.enabled", true) === false)
      return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: root.safeMode ? "safe-mode" : (!root.enhancementsActive() ? "enhancements-disabled" : "split-view-disabled") })
    if (root.multitaskingLaunch || root.multitaskingPairLaunch)
      return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: "launch-request-active" })
    var settings = Object.assign({}, options || {})
    var appIds = WindowGroupsModel.expectedApps(group).slice(0, 2)
    if (appIds.length < 2) return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: "two-application-identities-required" })
    var duplicatePolicy = String(group.preferences && group.preferences.duplicatePolicy || "ask")
    var windowIds = ["", ""]
    var duplicates = []
    for (var i = 0; i < appIds.length; i++) {
      var rows = root.multitaskingWindowsForApp(appIds[i])
      if (rows.length > 1 && duplicatePolicy !== "first") { duplicates.push(appIds[i]); continue }
      if (rows.length > 0) windowIds[i] = root.multitaskingWindowIdentity(rows[0])
    }
    if (duplicates.length > 0)
      return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: "duplicate-window-choice-required", groupId: group.id, duplicateApps: duplicates })
    var missing = windowIds.filter(function(value) { return !value }).length
    if (missing === 0) {
      var existingWindows = windowIds.map(function(value) { return root.windowForMultitaskingId(value) })
      var direct = root.splitWindows(existingWindows, Object.assign(settings, { ratio: group.layout.ratio, defaultRatio: group.layout.ratio }))
      if (direct) root.updateWindowGroupRuntime(group.id, existingWindows)
      return root.multitaskingRecord({ type: "app-pair-launch", ok: direct === true, reason: direct ? "committed" : "split-apply-failed", groupId: group.id, appCount: existingWindows.length })
    }
    var now = Date.now()
    var timeoutMs = Math.max(500, Math.min(15000, Math.floor(Number(settings.timeoutMs || root.cfg("multitasking.launchTimeoutMs", 12000)))))
    root.multitaskingPairLaunch = {
      groupId: group.id,
      appIds: appIds,
      windowIds: windowIds,
      nextIndex: 0,
      currentAppId: "",
      startedAt: now,
      timeoutMs: timeoutMs,
      deadline: now + timeoutMs,
      workspaceId: group.preferences && group.preferences.targetWorkspace || "",
      monitorName: group.preferences && group.preferences.originalMonitor || "",
      ratio: group.layout.ratio,
      options: settings,
      phase: "queued"
    }
    var next = root.startNextMultitaskingPairLaunch()
    if (!next || next.ok !== true) return next
    return root.multitaskingRecord({ type: "app-pair-launch", ok: true, pending: true, groupId: group.id, appId: next.appId, deadline: next.deadline })
  }

  function beginSnapAssist(window, kind, start, options) {
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    if (settings.enabled === false) {
      root.snapAssistState = Object.assign(SnapAssistModel.emptyState(), { phase: "blocked", reason: root.safeMode ? "safe-mode" : (!root.enhancementsActive() ? "enhancements-disabled" : "disabled") })
      root.multitaskingRecord({ type: "snap-begin", ok: false, reason: root.snapAssistState.reason })
      return false
    }
    root.snapAssistState = SnapAssistModel.beginDrag(window, kind, start, settings)
    root.multitaskingRecord({ type: "snap-begin", ok: root.snapAssistState.active === true, reason: root.snapAssistState.reason, windowId: root.snapAssistState.windowId })
    return root.snapAssistState.active === true
  }

  function updateSnapAssist(point, options) {
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    var settings = Object.assign(root.multitaskingOptions(), options || {}, { now: options && options.now !== undefined ? options.now : Date.now() })
    root.snapAssistState = SnapAssistModel.updateDrag(root.snapAssistState, point, root.multitaskingMonitors(), settings)
    root.multitaskingRevision++
    root.stateUpdated()
    return root.snapAssistState
  }

  function cancelSnapAssist(reason) {
    root.snapAssistState = SnapAssistModel.cancel(root.snapAssistState, reason || "cancelled")
    root.multitaskingRecord({ type: "snap-cancel", ok: true, reason: root.snapAssistState.reason })
    return true
  }

  function selectSnapZone(zoneId, options) {
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    var monitor = null
    var monitors = root.multitaskingMonitors()
    for (var i = 0; i < monitors.length; i++) {
      if (String(monitors[i].name || monitors[i].monitor || "active") === String(root.snapAssistState.monitorName || "")) { monitor = monitors[i]; break }
    }
    if (!monitor) monitor = root.multitaskingMonitorForWindow(null, root.snapAssistState.lastPoint)
    root.snapAssistState = SnapAssistModel.selectZone(root.snapAssistState, zoneId, monitor, settings)
    root.multitaskingRevision++
    root.stateUpdated()
    return root.snapAssistState
  }

  function multitaskingAddress(windowOrId) {
    var value = windowOrId
    if (typeof value === "object") value = root.multitaskingForeign(value)
    var address = String(value && value.address || value || "")
    if (address.indexOf("address:") === 0) address = address.substring(8)
    return /^[0-9a-fA-Fx]+$/.test(address) ? address : ""
  }

  function multitaskingInteger(value) {
    var result = Math.round(Number(value))
    return isFinite(result) ? result : NaN
  }

  function applyWindowRect(window, rect) {
    if (!rect || !root.hyprlandAvailable) return { ok: false, reason: root.hyprlandAvailable ? "invalid-geometry" : "hyprland-unavailable" }
    var address = root.multitaskingAddress(window)
    if (!address) return { ok: false, reason: "window-address-unavailable" }
    var x = root.multitaskingInteger(rect.x)
    var y = root.multitaskingInteger(rect.y)
    var width = root.multitaskingInteger(rect.width)
    var height = root.multitaskingInteger(rect.height)
    if (![x, y, width, height].every(function(value) { return isFinite(value) && value >= 0 })) return { ok: false, reason: "invalid-geometry" }
    if (!root.dispatch("movewindowpixel exact " + x + " " + y + ",address:" + address)) return { ok: false, reason: "move-dispatch-rejected" }
    if (!root.dispatch("resizewindowpixel exact " + width + " " + height + ",address:" + address)) return { ok: false, reason: "resize-dispatch-rejected" }
    return { ok: true, address: address, queued: 2 }
  }

  function windowForMultitaskingId(id) {
    var wanted = String(id || "")
    var list = Array.isArray(root.clients) ? root.clients : []
    for (var i = 0; i < list.length; i++) {
      if (root.multitaskingWindowIdentity(list[i]) === wanted) return list[i]
      if (WindowMatcherModel.identity(list[i]) === wanted) return list[i]
    }
    return null
  }

  function commitSnapAssist() {
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    var result = SnapAssistModel.commit(root.snapAssistState)
    if (!result.ok) return root.multitaskingRecord({ type: "snap-commit", ok: false, reason: result.reason })
    var window = root.windowForMultitaskingId(result.action.windowId)
    var applied = root.applyWindowRect(window, result.action.layout.slots[0].rect)
    if (!applied.ok) {
      root.snapAssistState = SnapAssistModel.cancel(result.state, applied.reason)
      return root.multitaskingRecord({ type: "snap-commit", ok: false, reason: applied.reason, rolledBack: true })
    }
    root.snapAssistState = result.state
    return root.multitaskingRecord({ type: "snap-commit", ok: true, reason: result.reason, action: result.action, applied: applied })
  }

  function availableSnapZones(kind, options) {
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    return SnapAssistModel.availableZones(root.multitaskingMonitors(), kind || root.lastInput, Object.assign(root.multitaskingOptions(), options || {}))
  }

  function snapZonesForWindow(window, kind, options) {
    var monitor = root.multitaskingMonitorForWindow(window)
    var wanted = String(monitor.name || monitor.monitor || "active")
    return root.availableSnapZones(kind || root.lastInput, options).filter(function(zone) { return String(zone.monitorName || "") === wanted })
  }

  function snapZonesForTarget(window, kind, options) {
    if (window) return root.snapZonesForWindow(window, kind, options)
    var zones = root.availableSnapZones(kind || root.lastInput, options)
    var firstMonitor = zones.length > 0 ? String(zones[0].monitorName || "") : ""
    return zones.filter(function(zone) { return String(zone.monitorName || "") === firstMonitor })
  }

  function multitaskingHalfZone(window, side) {
    var monitor = root.multitaskingMonitorForWindow(window)
    var portrait = Number(monitor.width || 0) < Number(monitor.height || 0)
    return portrait ? (String(side || "start") === "end" ? "half-bottom" : "half-top") : (String(side || "start") === "end" ? "half-right" : "half-left")
  }

  function snapWindowToZone(window, zoneId, kind, options) {
    var monitor = root.multitaskingMonitorForWindow(window)
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    var zones = root.availableSnapZones(kind || root.lastInput, settings)
    var wanted = String(LayoutEngineModel.canonicalZoneId(zoneId) || zoneId || "")
    var selected = null
    for (var i = 0; i < zones.length; i++) {
      if (String(zones[i].monitorName || "") === String(monitor.name || monitor.monitor || "active") && String(zones[i].id) === wanted) { selected = zones[i]; break }
    }
    if (!selected) return root.multitaskingRecord({ type: "snap-commit", ok: false, reason: "snap-zone-unavailable" })
    var rect = selected.rect || {}
    var start = { x: Number(rect.x || 0) + Number(rect.width || 1) / 2, y: Number(rect.y || 0) + Number(rect.height || 1) / 2 }
    if (!root.beginSnapAssist(window, kind || "mouse", start, settings)) return false
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    root.snapAssistState = SnapAssistModel.selectZone(root.snapAssistState, wanted, monitor, settings)
    return root.commitSnapAssist()
  }

  function createSplitView(windows, options) {
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    var list = Array.isArray(windows) ? windows : []
    var ids = list.slice(0, 2).map(function(window) { return root.multitaskingWindowIdentity(window) })
    if (ids.length < 2 || !ids[0] || !ids[1]) {
      root.splitViewState = null
      root.splitViewWindows = []
      root.multitaskingRecord({ type: "split-create", ok: false, reason: "two-window-identities-required" })
      return null
    }
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    if (settings.splitViewEnabled !== true) {
      root.multitaskingRecord({ type: "split-create", ok: false, reason: root.safeMode ? "safe-mode" : (!root.enhancementsActive() ? "enhancements-disabled" : "split-view-disabled") })
      return null
    }
    var monitor = settings.monitor || root.multitaskingMonitorForWindow(list[0])
    root.splitViewWindows = list.slice(0, 2)
    root.splitViewState = SplitViewModel.createState(monitor, ids, settings)
    root.syncSplitWindowGroup(root.splitViewWindows, { ratio: root.splitViewState.ratioName })
    root.multitaskingRecord({ type: "split-create", ok: true, ratio: root.splitViewState.ratioName, axis: root.splitViewState.pair.axis })
    return root.splitViewState
  }

  function splitWindows(windows, options) {
    if (!root.createSplitView(windows, options)) return false
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    root.splitViewState = SplitViewModel.beginApply(root.splitViewState, Object.assign(root.multitaskingOptions(), options || {}))
    return root.commitSplitView().ok === true
  }

  function splitAppWithActiveWindow(appId) {
    var active = root.activeClient()
    var rows = root.windowsForApp(appId)
    var activeId = root.multitaskingWindowIdentity(active)
    for (var i = 0; i < rows.length; i++) {
      if (root.multitaskingWindowIdentity(rows[i]) === activeId) continue
      return root.splitWindows([active, rows[i]], {})
    }
    return root.launchAppToSplit(appId, active, {})
  }

  function launchAppToZone(appId, zoneId, kind, options) {
    var key = WindowMatcherModel.appId(appId)
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    if (!key) return root.multitaskingRecord({ type: "launch-to-slot", ok: false, reason: "application-identity-required" })
    if (settings.enabled === false || root.safeMode)
      return root.multitaskingRecord({ type: "launch-to-slot", ok: false, reason: root.safeMode ? "safe-mode" : "disabled" })
    var existing = root.windowsForApp(key)
    if (existing.length > 0) {
      var current = root.multitaskingForeign(existing[0])
      return root.snapWindowToZone(current, zoneId, kind || "touch", settings)
    }
    if (root.multitaskingLaunch) return root.multitaskingRecord({ type: "launch-to-slot", ok: false, reason: "launch-request-active" })
    var request = WindowMatcherModel.begin(key, root.clients, Date.now(), {
      timeoutMs: settings.launchTimeoutMs,
      workspaceId: settings.workspaceId,
      monitorName: settings.monitorName || settings.monitor
    })
    if (request.status !== "pending") return root.multitaskingRecord({ type: "launch-to-slot", ok: false, reason: request.reason })
    root.multitaskingLaunch = request
    root.multitaskingLaunchTarget = { type: "snap", appId: key, zoneId: String(zoneId || ""), kind: kind || "touch", options: settings }
    if (!root.launchApp(key)) {
      root.multitaskingLaunch = null
      root.multitaskingLaunchTarget = null
      return root.multitaskingRecord({ type: "launch-to-slot", ok: false, reason: "launch-rejected" })
    }
    multitaskingLaunchTimeout.interval = request.timeoutMs
    multitaskingLaunchTimeout.restart()
    return root.multitaskingRecord({ type: "launch-to-slot", ok: true, pending: true, appId: key, deadline: request.deadline })
  }

  function launchAppToSplit(appId, firstWindow, options) {
    var key = WindowMatcherModel.appId(appId)
    var settings = Object.assign(root.multitaskingOptions(), options || {})
    var first = firstWindow || root.activeClient()
    var firstId = root.multitaskingWindowIdentity(first)
    if (!key || !firstId) return root.multitaskingRecord({ type: "launch-to-split", ok: false, reason: "window-identity-required" })
    if (settings.enabled === false || root.safeMode)
      return root.multitaskingRecord({ type: "launch-to-split", ok: false, reason: root.safeMode ? "safe-mode" : "disabled" })
    var existing = root.windowsForApp(key)
    if (existing.length > 0) return root.splitWindows([first, root.multitaskingForeign(existing[0])], settings)
    if (root.multitaskingLaunch) return root.multitaskingRecord({ type: "launch-to-split", ok: false, reason: "launch-request-active" })
    var request = WindowMatcherModel.begin(key, root.clients, Date.now(), { timeoutMs: settings.launchTimeoutMs })
    if (request.status !== "pending") return root.multitaskingRecord({ type: "launch-to-split", ok: false, reason: request.reason })
    root.multitaskingLaunch = request
    root.multitaskingLaunchTarget = { type: "split", appId: key, firstWindowId: firstId, options: settings }
    if (!root.launchApp(key)) {
      root.multitaskingLaunch = null
      root.multitaskingLaunchTarget = null
      return root.multitaskingRecord({ type: "launch-to-split", ok: false, reason: "launch-rejected" })
    }
    multitaskingLaunchTimeout.interval = request.timeoutMs
    multitaskingLaunchTimeout.restart()
    return root.multitaskingRecord({ type: "launch-to-split", ok: true, pending: true, appId: key, deadline: request.deadline })
  }

  function resolveMultitaskingLaunch() {
    if (!root.multitaskingLaunch) return null
    var resolved = WindowMatcherModel.resolve(root.multitaskingLaunch, root.clients, Date.now())
    root.multitaskingLaunch = resolved.request
    if (resolved.result.status === "pending") return resolved.result
    multitaskingLaunchTimeout.stop()
    var target = root.multitaskingLaunchTarget
    root.multitaskingLaunch = null
    root.multitaskingLaunchTarget = null
    if (target && target.type === "pair") {
      if (resolved.result.status === "timeout") return root.finishMultitaskingPairLaunch(false, "launch-timeout")
      var pairWindow = root.windowForMultitaskingId(resolved.result.windowId)
      if (!pairWindow) return root.finishMultitaskingPairLaunch(false, "matched-window-disappeared")
      var pairState = root.multitaskingPairLaunch
      if (!pairState) return root.multitaskingRecord({ type: "app-pair-launch", ok: false, reason: "pair-launch-state-missing" })
      pairState.windowIds[target.index] = resolved.result.windowId
      pairState.nextIndex = Number(target.index) + 1
      root.multitaskingPairLaunch = pairState
      var nextPair = root.startNextMultitaskingPairLaunch()
      if (nextPair && nextPair.pending === true)
        return root.multitaskingRecord({ type: "app-pair-launch", ok: true, pending: true, groupId: pairState.groupId, appId: nextPair.appId, deadline: nextPair.deadline })
      return nextPair
    }
    if (resolved.result.status === "timeout")
      return root.multitaskingRecord({ type: target && target.type === "split" ? "launch-to-split" : "launch-to-slot", ok: false, reason: "launch-timeout", appId: target && target.appId || "" })
    var window = root.windowForMultitaskingId(resolved.result.windowId)
    if (!window) return root.multitaskingRecord({ type: "launch-to-slot", ok: false, reason: "matched-window-disappeared" })
    var result = target && target.type === "split"
      ? root.splitWindows([root.windowForMultitaskingId(target.firstWindowId), window], target.options || {})
      : root.snapWindowToZone(root.multitaskingForeign(window), target && target.zoneId || "maximized", target && target.kind || "touch", target && target.options || {})
    return root.multitaskingRecord({ type: target && target.type === "split" ? "launch-to-split" : "launch-to-slot", ok: result && result.ok === true, reason: result && result.reason || "apply-failed", matchedWindowId: resolved.result.windowId })
  }

  function beginSplitDividerDrag(point, options) {
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    if (!root.splitViewState) return root.multitaskingRecord({ type: "split-begin", ok: false, reason: "split-view-unavailable" })
    if (root.multitaskingOptions().splitViewEnabled !== true) return root.multitaskingRecord({ type: "split-begin", ok: false, reason: "split-view-disabled" })
    root.splitViewState = SplitViewModel.beginDividerDrag(root.splitViewState, point, Object.assign(root.multitaskingOptions(), options || {}))
    root.multitaskingRecord({ type: "split-begin", ok: root.splitViewState.phase === "dragging", reason: root.splitViewState.error || "ready" })
    return root.splitViewState
  }

  function updateSplitDividerDrag(point, options) {
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    if (!root.splitViewState) return null
    root.splitViewState = SplitViewModel.updateDividerDrag(root.splitViewState, point, Object.assign(root.multitaskingOptions(), options || {}))
    root.multitaskingRevision++
    root.stateUpdated()
    return root.splitViewState
  }

  function applySplitPair(pair, windows) {
    var list = Array.isArray(windows) ? windows : root.splitViewWindows
    if (!pair || !Array.isArray(pair.slots) || list.length < 2) return { ok: false, reason: "split-pair-incomplete", applied: 0 }
    var applied = 0
    for (var i = 0; i < 2; i++) {
      var result = root.applyWindowRect(list[i], pair.slots[i].rect)
      if (!result.ok) return { ok: false, reason: result.reason, applied: applied }
      applied++
    }
    return { ok: true, applied: applied }
  }

  function commitSplitView() {
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    if (!root.splitViewState) return root.multitaskingRecord({ type: "split-commit", ok: false, reason: "split-view-unavailable" })
    var candidate = root.splitViewState.pair
    var applied = root.applySplitPair(candidate, root.splitViewWindows)
    var result = SplitViewModel.commit(root.splitViewState, applied)
    root.splitViewState = result.state
    if (!result.ok && result.rolledBack && applied.applied > 0) root.applySplitPair(result.pair, root.splitViewWindows)
    if (result.ok) {
      var splitGroup = root.syncSplitWindowGroup(root.splitViewWindows, { ratio: root.splitViewState.ratioName })
      if (splitGroup) root.rememberManagedLayout(splitGroup, "recent")
    }
    return root.multitaskingRecord({ type: "split-commit", ok: result.ok, reason: result.reason || "committed", rolledBack: result.rolledBack === true, applied: applied })
  }

  function rollbackSplitView(reason) {
    if (!root.splitViewState) return false
    var result = SplitViewModel.rollback(root.splitViewState, reason || "cancelled")
    root.splitViewState = result.state
    return root.multitaskingRecord({ type: "split-rollback", ok: false, reason: result.reason, rolledBack: true })
  }

  function rotateSplitView(monitor, options) {
    if (!root.splitViewState) return null
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    root.splitViewState = SplitViewModel.rotate(root.splitViewState, monitor || root.multitaskingMonitorForWindow(root.splitViewWindows[0]), Object.assign(root.multitaskingOptions(), options || {}))
    root.multitaskingRecord({ type: "split-rotate", ok: true, axis: root.splitViewState.pair.axis, ratio: root.splitViewState.ratioName })
    return root.splitViewState
  }

  function splitDividerGeometry() {
    if (!root.splitViewState) return null
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    return SplitViewModel.dividerGeometry(root.splitViewState.pair, root.multitaskingOptions())
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
    if (!root.inputDispatchAllowed() || root.cfg("keyboard.enabled", true) !== true) return false
    var value = String(key || "")
    var named = keyName(value)
    if (root.nativeInputReady()) {
      if (value.length === 1) return root.nativeInputSend({ type: "keyboard.text", text: shifted ? value.toUpperCase() : value })
      return root.nativeInputSend([
        { type: "keyboard.key", key: named, state: 1 },
        { type: "keyboard.key", key: named, state: 0 }
      ])
    }
    if (!root.wtypeAvailable || root.cfg("input.allowWtypeFallback", true) !== true) return false
    if (value.length === 1 && !shifted) return root.execute(["wtype", "--", value])
    if (value.length === 1 && shifted) return root.typeText(value.toUpperCase())
    return root.execute(["wtype", "-k", named])
  }

  function sendModifiedKey(key, modifiers) {
    if (!root.inputDispatchAllowed() || root.cfg("keyboard.enabled", true) !== true) return false
    var value = String(key || "")
    if (!value) return false
    if (root.nativeInputReady() && value.length === 1 && value.charCodeAt(0) < 128) {
      var nativeCommands = [{ type: "keyboard.modifiers", modifiers: Array.isArray(modifiers) ? modifiers : [] }]
      nativeCommands.push({ type: "keyboard.key", key: root.keyName(value), state: 1 })
      nativeCommands.push({ type: "keyboard.key", key: root.keyName(value), state: 0 })
      nativeCommands.push({ type: "keyboard.modifiers", modifiers: [] })
      return root.nativeInputSend(nativeCommands)
    }
    if (!root.wtypeAvailable || root.cfg("input.allowWtypeFallback", true) !== true) return false
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
    if (!root.inputDispatchAllowed() || root.cfg("keyboard.enabled", true) !== true) return false
    var value = String(text || "")
    if (!value) return false
    if (root.nativeInputReady()) return root.nativeInputSend({ type: "keyboard.text", text: value })
    if (!root.wtypeAvailable || root.cfg("input.allowWtypeFallback", true) !== true) return false
    return root.execute(["wtype", "--", value])
  }

  function setInputLanguage(language) {
    var value = String(language || "auto")
    if (["en", "ru", "auto"].indexOf(value) < 0) value = "auto"
    if (!root.nativeInputReady()) return false
    return root.nativeInputSend({ type: "set.language", language: value })
  }

  function saveClipboard() {
    if (!root.configReady || root.cfg("clipboard.persist", true) === false) return
    clipboardWriteDebounce.restart()
  }

  function persistClipboard() {
    if (!root.configReady || root.cfg("clipboard.persist", true) === false) return
    var settings = root.cfg("clipboard", {})
    clipboardFile.setText(JSON.stringify(ClipboardModel.persistable(root.clipboardHistory, settings), null, 2) + "\n")
    root.updateProcessCounter("clipboardWrites", 1)
    root.scheduleProcessRegistryWrite()
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
    if (!root.enhancementsActive() || !root.configReady || !root.cfg("clipboard.enabled", true) || root.cfg("clipboard.privateMode", false) || root.cfg("privacy.clipboardPrivate", false)) return
    if (!root.captureScript) root.reloadPaths()
    if (ProcessPolicy.stable(root.clipboardRestartState, Date.now(), root.clipboardRestartPolicy))
      root.clipboardRestartState = { consecutiveFailures: 0, startedAt: 0, blocked: false }
    if (root.clipboardRestartState.blocked === true) return
    root.clipboardWatching = true
    if (!textWatch.running) textWatch.running = true
    if (!imageWatch.running) imageWatch.running = true
  }

  function stopClipboardWatchers() {
    root.clipboardWatching = false
    if (textWatch.running) textWatch.running = false
    if (imageWatch.running) imageWatch.running = false
    clipboardRestart.stop()
    root.clipboardRestartState = { consecutiveFailures: 0, startedAt: 0, blocked: false }
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
      started = root.annotationScreenshot(false)
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
    var enabled = root.enhancementsActive() && TouchModel.workspaceSwipeEnabled(touchConfig, root.clients)
    root.applyHyprSetting("gestures:workspace_swipe_touch", enabled)
    if (!enabled) return
    root.applyHyprSetting("gestures:workspace_swipe_distance", Math.max(1, Number(root.cfg("touch.threshold", 96))))
    root.applyHyprSetting("gestures:workspace_swipe_min_speed_to_force", Math.max(1, Math.round(Number(root.cfg("touch.velocity", 0.35)) * 100)))
    root.applyHyprSetting("gestures:workspace_swipe_touch_invert", root.cfg("touch.invert", false))
  }

  Process {
    id: commandProcess
    environment: root.ownedEnvironment("command")
    onStarted: root.processStarted("command", commandProcess, "serialized user/system command", false, "serialized-coalesced")
    onExited: function(exitCode) {
      root.processStopped("command", commandProcess, exitCode)
      if (root.shuttingDown) return
      root.startNextCommand()
      systemRefresh.restart()
    }
  }

  Process {
    id: shortcutBindsProcess
    environment: root.ownedEnvironment("shortcut-conflicts")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateShortcutConflicts(text) }
    onStarted: root.processStarted("shortcut-conflicts", shortcutBindsProcess, "on-demand Hyprland shortcut conflict check", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("shortcut-conflicts", shortcutBindsProcess, exitCode)
      if (exitCode !== 0 && root.shortcutConflictRunning) {
        root.shortcutConflictState = Object.assign({}, MultitaskingShortcutsModel.emptyState(), { status: "unavailable", reason: "hyprland-bindings-command-failed" })
        root.shortcutConflictRunning = false
        root.shortcutConflictRevision++
        root.stateUpdated()
      }
    }
  }

  Process {
    id: inputProcess
    environment: root.ownedEnvironment("input")
    onStarted: root.processStarted("input", inputProcess, "bounded one-shot input fallback", false, "queue-bounded")
    onExited: function(exitCode) {
      root.processStopped("input", inputProcess, exitCode)
      if (root.shuttingDown) return
      if (root.inputQueue.length > 0) inputFlush.restart()
    }
  }

  Process {
    id: inputBackendProbe
    environment: root.ownedEnvironment("omanome-input-probe")
    stdout: SplitParser { onRead: function(line) { root.inputBackendProbeOutput = String(line || "").trim() } }
    onStarted: root.processStarted("omanome-input-probe", inputBackendProbe, "locate native input helper", false, "startup")
    onExited: function(exitCode) {
      root.processStopped("omanome-input-probe", inputBackendProbe, exitCode)
      root.inputBackendPath = exitCode === 0 ? root.firstLine(root.inputBackendProbeOutput) : ""
      if (root.inputBackendPath) root.startNativeInputBackend()
      else root.inputBackendReason = "native-helper-unavailable"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: inputBackendProcess
    stdinEnabled: true
    environment: root.inputBackendEnvironment()
    stdout: SplitParser { onRead: function(line) { root.updateNativeInputLine(line) } }
    // Native helper diagnostics are intentionally not copied into the shell
    // log: the helper's public stream is already redacted and bounded.
    stderr: SplitParser { onRead: function(line) { root.inputBackendReason = "native-helper-diagnostic" } }
    onStarted: {
      root.processStarted("omanome-input", inputBackendProcess, "persistent native Wayland input backend", true, "bounded-backoff")
      root.inputNativePending = 0
      root.inputPendingRequests = ({})
      root.inputBackendReason = "connecting"
    }
    onExited: function(exitCode) { root.inputBackendExited(exitCode) }
  }

  Process {
    id: screenshotProcess
    environment: root.ownedEnvironment("screenshot")
    onStarted: root.processStarted("screenshot", screenshotProcess, "user-requested screenshot", false, "user-action")
    onExited: function(exitCode) { root.processStopped("screenshot", screenshotProcess, exitCode) }
  }

  Process {
    id: performanceSnapshotProcess
    command: ["python3", root.sourcePath("scripts/process_snapshot.py"), "--json", "--sample-ms", "100"]
    environment: root.observerEnvironment("performance-snapshot")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updatePerformanceSnapshot(text) }
    onStarted: {
      root.performanceSnapshotRunning = true
      root.processStarted("performance-snapshot", performanceSnapshotProcess, "on-demand owner-only diagnostics", false, "user-action")
      performanceSnapshotTimeout.restart()
    }
    onExited: function(exitCode) {
      root.processStopped("performance-snapshot", performanceSnapshotProcess, exitCode)
      root.finishPerformanceSnapshot(exitCode)
    }
  }

  Timer {
    id: performanceSnapshotTimeout
    interval: 5000
    repeat: false
    onTriggered: if (performanceSnapshotProcess.running) performanceSnapshotProcess.running = false
  }

  Process {
    id: directoryProcess
    environment: root.ownedEnvironment("directory")
    onStarted: root.processStarted("directory", directoryProcess, "create user directories", false, "none")
    onExited: function(exitCode) {
      root.processStopped("directory", directoryProcess, exitCode)
      if (root.shuttingDown) return
      if (exitCode !== 0) root.lastError = "Could not create Omanome user directories"
      else {
        root.directoriesReady = true
        root.scheduleProcessRegistryWrite()
        initialConfigSave.restart()
      }
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
      root.configLoadStatus = "recovery-pending"
      root.configLoadError = "configuration file was missing or could not be read"
      root.safeMode = true
      root.startConfigRecovery()
    }
    onFileChanged: if (!root._loadingConfig) reload()
  }

  Process {
    id: configRecoveryProcess
    environment: root.ownedEnvironment("config-recovery")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.configRecoveryOutput = text }
    onStarted: root.processStarted("config-recovery", configRecoveryProcess, "preserve damaged config and restore last-known-good", false, "recovery")
    onExited: function(exitCode) {
      root.processStopped("config-recovery", configRecoveryProcess, exitCode)
      if (root.shuttingDown) return
      root.configRecoveryRunning = false
      var result = root.parseJson(root.configRecoveryOutput, {})
      if (exitCode !== 0 || result.ok !== true) {
        root.lastError = "Configuration recovery is unavailable; use 'omanome config recover'"
        root.stateRevision++
        root.stateUpdated()
        return
      }
      root.lastError = result.recovered === true ? "Configuration recovered; previous data was preserved" : ""
      // FileView observes the atomic replacement. Reload explicitly as well so
      // a recovery that created a previously missing file is never delayed by
      // a watcher implementation that only watches existing inodes.
      configFile.reload()
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Timer {
    id: configWriteDebounce
    interval: 180
    repeat: false
    onTriggered: {
      configFile.setText(JSON.stringify(root.config, null, 2) + "\n")
      root.updateProcessCounter("configWrites", 1)
      root.scheduleProcessRegistryWrite()
    }
  }

  FileView {
    id: processRegistryFile
    path: root.processRegistryPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadProcessRegistry(text())
    onLoadFailed: root.loadProcessRegistry("")
  }

  Timer {
    id: processRegistryWriteDebounce
    // performance: allow-fast-timer — one-shot coalescing for atomic registry writes.
    interval: 80
    repeat: false
    onTriggered: root.persistProcessRegistry()
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

  Timer {
    id: clipboardWriteDebounce
    interval: 250
    repeat: false
    onTriggered: root.persistClipboard()
  }

  Process {
    id: devicesProcess
    command: ["hyprctl", "devices", "-j"]
    environment: root.ownedEnvironment("devices")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateDevices(text) }
    onStarted: root.processStarted("devices", devicesProcess, "Hyprland device snapshot", false, "none")
    onExited: function(exitCode) {
      root.processStopped("devices", devicesProcess, exitCode)
      root.hyprlandAvailable = exitCode === 0 || root.hyprlandAvailable
      if (exitCode === 0) root.applyTouchIntegration()
    }
  }

  Process {
    id: deviceMonitorProcess
    environment: root.ownedEnvironment("device-hotplug")
    stdout: SplitParser { onRead: function(line) { root.updateDeviceEvent(line) } }
    stderr: SplitParser { onRead: function(line) { root.inputDeviceMonitorReason = "udev-monitor-diagnostic" } }
    onStarted: {
      root.processStarted("device-hotplug", deviceMonitorProcess, "event-driven input/display hotplug", true, "none")
      root.inputDeviceMonitorReason = "connecting"
    }
    onExited: function(exitCode) {
      root.processStopped("device-hotplug", deviceMonitorProcess, exitCode)
      root.inputDeviceMonitorAvailable = false
      root.inputDeviceMonitorReason = exitCode === 127 ? "udev-unavailable" : "udev-monitor-exited"
    }
  }

  Process {
    id: sessionMonitorProcess
    environment: root.ownedEnvironment("session-lifecycle")
    stdout: SplitParser { onRead: function(line) { root.updateSessionEvent(line) } }
    stderr: SplitParser { onRead: function(line) { root.sessionMonitorReason = "session-monitor-diagnostic" } }
    onStarted: {
      root.processStarted("session-lifecycle", sessionMonitorProcess, "event-driven suspend/resume lifecycle", true, "none")
      root.sessionMonitorAvailable = true
      root.sessionMonitorReason = "connected"
    }
    onExited: function(exitCode) {
      root.processStopped("session-lifecycle", sessionMonitorProcess, exitCode)
      root.sessionMonitorAvailable = false
      root.sessionMonitorReason = exitCode === 127 ? "dbus-monitor-unavailable" : "session-monitor-exited"
    }
  }

  Timer {
    id: deviceRefreshDebounce
    interval: 240
    repeat: false
    onTriggered: root.refreshDevices()
  }

  Timer {
    id: keyboardTransitionTimer
    interval: 680
    repeat: false
    onTriggered: {
      var observed = root.observeKeyboardTransition("keyboard-stability-window")
      if (observed.pending) return
      root.detectedMode = root.computeMode()
      root.updateResponsiveContext()
      root.reconcileOskPolicy()
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Timer {
    id: modeTransitionTimer
    // performance: allow-fast-timer — local Qt-style choreography only; no
    // subprocess, no compositor IPC, and no config write occurs per frame.
    interval: 16
    repeat: true
    onTriggered: root.tickModeTransition()
  }

  Timer {
    id: dockedModeTimer
    // Event-driven monitor/keyboard stability window; this is not a poll.
    interval: 440
    repeat: false
    onTriggered: {
      root.updateResponsiveContext()
      root.reconcileOskPolicy()
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Timer {
    id: adaptivePreviewTimer
    // One bounded one-shot restores the hardware-derived policy after a
    // settings preview; it is not a device or compositor polling loop.
    interval: 6000
    repeat: false
    onTriggered: {
      root.adaptivePreviewState = AdaptiveSettingsModel.tickPreview(root.adaptivePreviewState, Date.now())
      root.updateResponsiveContext()
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Timer {
    id: postureTransition
    interval: 320
    repeat: false
    onTriggered: {
      var before = root.detectedMode
      root.detectedMode = root.computeMode()
      root.updateResponsiveContext()
      root.reconcileOskPolicy()
      if (before !== root.detectedMode) {
        root.stateRevision++
        root.stateUpdated()
      }
    }
  }

  Timer {
    id: orientationTransition
    interval: 550
    repeat: false
    onTriggered: {
      var candidate = String(root.orientationState.candidate || "")
      if (!candidate) return
      var observed = RotationModel.observe(root.orientationState, candidate, Date.now(), {
        stableMs: Number(root.cfg("rotation.orientationDebounceMs", 550)),
        minimumDwellMs: Number(root.cfg("rotation.minimumDwellMs", 1000))
      })
      root.orientationState = observed.state
      if (observed.pending) {
        interval = Math.max(120, Number(observed.delayMs || 550))
        restart()
      } else if (observed.changed) {
        root.orientation = observed.value
        if (root.cfg("rotation.orientation", "auto") === "auto" && !root.cfg("rotation.lock", false))
          root.applyRotation(root.rotationTransformFor(observed.value))
      }
    }
  }

  Process {
    id: monitorsProcess
    command: ["hyprctl", "monitors", "-j"]
    environment: root.ownedEnvironment("monitors")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateMonitors(text) }
    onStarted: root.processStarted("monitors", monitorsProcess, "Hyprland monitor snapshot", false, "none")
    onExited: function(exitCode) { root.processStopped("monitors", monitorsProcess, exitCode) }
  }

  Process {
    id: clientsProcess
    command: ["hyprctl", "clients", "-j"]
    environment: root.ownedEnvironment("clients")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateClients(text) }
    onStarted: root.processStarted("clients", clientsProcess, "Hyprland client snapshot", false, "none")
    onExited: function(exitCode) { root.processStopped("clients", clientsProcess, exitCode) }
  }

  Process {
    id: systemStateProcess
    command: ["bash", root.sourcePath("input/system-state.sh")]
    environment: root.ownedEnvironment("system-state")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateSystemState(text) }
    onStarted: root.processStarted("system-state", systemStateProcess, "Quick Settings state snapshot", false, "none")
    onExited: function(exitCode) {
      root.processStopped("system-state", systemStateProcess, exitCode)
      if (exitCode !== 0) root.lastError = "Quick Settings state probe failed"
    }
  }

  Process {
    id: effectsInfoProcess
    command: ["bash", root.sourcePath("input/effects-info.sh")]
    environment: root.ownedEnvironment("effects-info")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateEffectBackend(text) }
    onStarted: root.processStarted("effects-info", effectsInfoProcess, "effect backend snapshot", false, "none")
    onExited: function(exitCode) {
      root.processStopped("effects-info", effectsInfoProcess, exitCode)
      if (exitCode !== 0) root.lastError = "Effect backend probe failed"
    }
  }

  Process {
    id: wobblyControlProcess
    environment: root.ownedEnvironment("wobbly-control")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateWobblyBackendResponse(text) }
    onStarted: root.processStarted("wobbly-control", wobblyControlProcess, "wobbly backend request", false, "coalesced")
    onExited: function(exitCode) {
      root.processStopped("wobbly-control", wobblyControlProcess, exitCode)
      root.finishWobblyBackend(exitCode)
    }
  }

  Timer {
    id: wobblyConfigDebounce
    interval: 180
    repeat: false
    onTriggered: root.requestWobblyConfig()
  }

  Process {
    id: wobblyConfigProcess
    environment: root.ownedEnvironment("wobbly-config")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateWobblyConfigResponse(text) }
    onStarted: root.processStarted("wobbly-config", wobblyConfigProcess, "wobbly configuration request", false, "debounced")
    onExited: function(exitCode) {
      root.processStopped("wobbly-config", wobblyConfigProcess, exitCode)
      root.finishWobblyConfig(exitCode)
    }
  }

  Process {
    id: forceQuitTermProcess
    environment: root.ownedEnvironment("force-quit-term")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateForceQuitTerm(text, 0) }
    onStarted: root.processStarted("force-quit-term", forceQuitTermProcess, "graceful close request", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("force-quit-term", forceQuitTermProcess, exitCode)
      if (exitCode !== 0) root.updateForceQuitTerm("", exitCode)
    }
  }

  Process {
    id: forceQuitKillProcess
    environment: root.ownedEnvironment("force-quit-kill")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateForceQuitKill(text, 0) }
    onStarted: root.processStarted("force-quit-kill", forceQuitKillProcess, "forced close request", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("force-quit-kill", forceQuitKillProcess, exitCode)
      if (exitCode !== 0) root.updateForceQuitKill("", exitCode)
    }
  }

  Process {
    id: wifiScanProcess
    command: ["bash", root.sourcePath("input/wifi-scan.sh")]
    environment: root.ownedEnvironment("wifi-scan")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateWifiScan(text) }
    onStarted: root.processStarted("wifi-scan", wifiScanProcess, "on-demand Wi-Fi scan", false, "user-action")
    onExited: function(exitCode) { root.processStopped("wifi-scan", wifiScanProcess, exitCode) }
  }

  Process {
    id: bluetoothScanProcess
    command: ["bash", root.sourcePath("input/bluetooth-scan.sh")]
    environment: root.ownedEnvironment("bluetooth-scan")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBluetoothScan(text) }
    onStarted: root.processStarted("bluetooth-scan", bluetoothScanProcess, "on-demand Bluetooth scan", false, "user-action")
    onExited: function(exitCode) { root.processStopped("bluetooth-scan", bluetoothScanProcess, exitCode) }
  }

  Process {
    id: audioScanProcess
    command: ["bash", root.sourcePath("input/audio-devices.sh")]
    environment: root.ownedEnvironment("audio-scan")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateAudioDevices(text) }
    onStarted: root.processStarted("audio-scan", audioScanProcess, "on-demand audio scan", false, "user-action")
    onExited: function(exitCode) { root.processStopped("audio-scan", audioScanProcess, exitCode) }
  }

  Process {
    id: rotationApplyProcess
    environment: root.ownedEnvironment("rotation-apply")
    onStarted: root.processStarted("rotation-apply", rotationApplyProcess, "atomic monitor rotation", false, "rollback")
    onExited: function(exitCode) {
      root.processStopped("rotation-apply", rotationApplyProcess, exitCode)
      if (root.shuttingDown) return
      var aborted = root.rotationAbortRequested
      var abortReason = root.rotationAbortReason
      root.rotationAbortRequested = false
      if (exitCode === 0 && !aborted) {
        root.finishRotation(true)
        return
      }
      var rollback = root.rotationRollbackBatch()
      if (rollback) {
        rotationRollbackProcess.command = ["hyprctl", "--batch", rollback]
        rotationRollbackProcess.running = true
      } else {
        root.finishRotation(false, false, abortReason)
      }
    }
  }

  Process {
    id: rotationRollbackProcess
    environment: root.ownedEnvironment("rotation-rollback")
    onStarted: root.processStarted("rotation-rollback", rotationRollbackProcess, "rotation rollback", false, "rollback")
    onExited: function(exitCode) {
      root.processStopped("rotation-rollback", rotationRollbackProcess, exitCode)
      var reason = root.rotationAbortReason
      root.finishRotation(false, exitCode === 0, reason)
    }
  }

  Process {
    id: rotationProcess
    command: ["bash", root.sourcePath("input/rotation-monitor.sh")]
    environment: root.ownedEnvironment("rotation-monitor")
    stdout: SplitParser { onRead: function(line) { root.updateOrientation(line) } }
    onStarted: {
      root.processStarted("rotation-monitor", rotationProcess, "event-driven orientation monitor", true, "bounded-backoff")
      if (ProcessPolicy.stable(root.rotationRestartState, Date.now(), root.rotationRestartPolicy))
        root.rotationRestartState = { consecutiveFailures: 0, startedAt: 0, blocked: false }
      var state = root.rotationRestartState
      if (!state.startedAt) state.startedAt = Date.now()
      root.rotationRestartState = state
    }
    onExited: root.rotationMonitorExited(exitCode)
  }

  Process {
    id: nightLightProcess
    command: ["hyprsunset", "--temperature", "4000"]
    environment: root.ownedEnvironment("night-light")
    onStarted: root.processStarted("night-light", nightLightProcess, "night-light helper", true, "user-action")
    onExited: function(exitCode) {
      root.processStopped("night-light", nightLightProcess, exitCode)
      root.refreshSystemState()
    }
  }

  Process {
    id: wtypeCheck
    command: ["bash", "-c", "command -v wtype >/dev/null 2>&1"]
    environment: root.ownedEnvironment("wtype-check")
    onStarted: root.processStarted("wtype-check", wtypeCheck, "input backend capability probe", false, "startup")
    onExited: function(exitCode) {
      root.processStopped("wtype-check", wtypeCheck, exitCode)
      root.wtypeAvailable = exitCode === 0
    }
  }

  Process {
    id: textWatch
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    environment: root.ownedEnvironment("clipboard-text")
    stdout: SplitParser { onRead: function(line) { root.addClipboardJson(line) } }
    onStarted: {
      root.processStarted("clipboard-text", textWatch, "event-driven text clipboard watcher", true, "bounded-backoff")
      var state = {}
      for (var key in root.clipboardRestartState) state[key] = root.clipboardRestartState[key]
      if (!state.startedAt) state.startedAt = Date.now()
      root.clipboardRestartState = state
    }
    onExited: function(exitCode) { root.clipboardWatcherExited("clipboard-text", exitCode) }
  }

  Process {
    id: imageWatch
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    environment: root.ownedEnvironment("clipboard-image")
    stdout: SplitParser { onRead: function(line) { root.addClipboardJson(line) } }
    onStarted: {
      root.processStarted("clipboard-image", imageWatch, "event-driven image clipboard watcher", true, "bounded-backoff")
      var state = {}
      for (var key in root.clipboardRestartState) state[key] = root.clipboardRestartState[key]
      if (!state.startedAt) state.startedAt = Date.now()
      root.clipboardRestartState = state
    }
    onExited: function(exitCode) { root.clipboardWatcherExited("clipboard-image", exitCode) }
  }

  Process {
    id: copyProcess
    property string secret: ""
    environment: root.ownedEnvironment("clipboard-copy")
    stdinEnabled: true
    onStarted: {
      root.processStarted("clipboard-copy", copyProcess, "clipboard secret pipe", false, "user-action")
      write(secret)
      secret = ""
    }
    onExited: function(exitCode) { root.processStopped("clipboard-copy", copyProcess, exitCode) }
  }

  Process {
    id: diagnosticsCopyProcess
    property string payload: ""
    command: ["wl-copy", "--type", "text/plain"]
    environment: root.ownedEnvironment("diagnostics-copy")
    stdinEnabled: true
    onStarted: {
      root.processStarted("diagnostics-copy", diagnosticsCopyProcess, "diagnostics clipboard copy", false, "user-action")
      write(payload)
      payload = ""
    }
    onExited: function(exitCode) { root.processStopped("diagnostics-copy", diagnosticsCopyProcess, exitCode) }
  }

  Process {
    id: doctorProcess
    command: [root.sourcePath("cli/omanome"), "doctor"]
    environment: root.ownedEnvironment("doctor")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.doctorOutput = text }
    onStarted: root.processStarted("doctor", doctorProcess, "diagnostic doctor command", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("doctor", doctorProcess, exitCode)
      root.doctorRunning = false
      if (exitCode !== 0 && root.doctorOutput === "") root.doctorOutput = "doctor unavailable (exit " + exitCode + ")"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: updateProcess
    environment: root.ownedEnvironment("update")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateOutput = text }
    onStarted: root.processStarted("update", updateProcess, "update inspection command", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("update", updateProcess, exitCode)
      root.updateRunning = false
      if (exitCode !== 0 && root.updateOutput === "") root.updateOutput = "update check unavailable (exit " + exitCode + ")"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: rollbackProcess
    environment: root.ownedEnvironment("rollback")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.rollbackOutput = text }
    onStarted: root.processStarted("rollback", rollbackProcess, "rollback inventory command", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("rollback", rollbackProcess, exitCode)
      root.rollbackRunning = false
      if (exitCode !== 0 && root.rollbackOutput === "") root.rollbackOutput = "rollback inventory unavailable (exit " + exitCode + ")"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: recoveryProcess
    environment: root.ownedEnvironment("recovery")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.recoveryOutput = text }
    onStarted: root.processStarted("recovery", recoveryProcess, "recovery command", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("recovery", recoveryProcess, exitCode)
      root.recoveryRunning = false
      if (exitCode !== 0 && root.recoveryOutput === "") root.recoveryOutput = "recovery unavailable (exit " + exitCode + ")"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: backupProcess
    environment: root.ownedEnvironment("backup")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.backupOutput = text }
    onStarted: root.processStarted("backup", backupProcess, "config backup command", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("backup", backupProcess, exitCode)
      root.backupRunning = false
      if (exitCode !== 0 && root.backupOutput === "") root.backupOutput = "config backup unavailable (exit " + exitCode + ")"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: supportBundleProcess
    environment: root.ownedEnvironment("support-bundle")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.supportBundleOutput = text }
    onStarted: root.processStarted("support-bundle", supportBundleProcess, "support bundle command", false, "user-action")
    onExited: function(exitCode) {
      root.processStopped("support-bundle", supportBundleProcess, exitCode)
      root.supportBundleRunning = false
      if (exitCode !== 0 && root.supportBundleOutput === "") root.supportBundleOutput = "support bundle unavailable (exit " + exitCode + ")"
      root.stateRevision++
      root.stateUpdated()
    }
  }

  Process {
    id: recorderProcess
    environment: root.ownedEnvironment("recorder")
    onStarted: root.processStarted("recorder", recorderProcess, "screen recording", true, "user-action")
    onExited: function(exitCode) {
      root.processStopped("recorder", recorderProcess, exitCode)
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
    id: rotationRestart
    interval: 1000
    repeat: false
    onTriggered: root.refreshRotationBackend()
  }

  Timer {
    id: inputBackendRestart
    interval: 1000
    repeat: false
    onTriggered: root.startNativeInputBackend()
  }

  Timer {
    id: oskPolicyTimer
    interval: 120
    repeat: false
    onTriggered: root.reconcileOskPolicy()
  }

  Timer {
    id: clipboardMaintenance
    interval: 300000
    repeat: true
    running: root.enhancementsActive() && root.configReady && root.cfg("clipboard.enabled", true)
    onTriggered: root.pruneClipboard()
  }

  Timer {
    id: integrationRefresh
    interval: 30000
    repeat: false
    onTriggered: root.refreshIntegrations()
  }

  Timer {
    id: systemRefresh
    interval: 250
    repeat: false
    onTriggered: root.refreshSystemState()
  }

  Timer {
    id: systemFallbackRefresh
    interval: 120000
    repeat: true
    running: root.configReady
    onTriggered: root.refreshSystemState()
  }

  Timer {
    id: inputFlush
    // performance: allow-fast-timer — one-shot input coalescing, never a poll.
    interval: 16
    repeat: false
    onTriggered: root.flushInputQueue()
  }

  Timer {
    id: inputModeCommit
    interval: 320
    repeat: false
    onTriggered: root.commitInputMode()
  }

  Timer {
    id: effectRefresh
    interval: 60000
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
    active: root.enhancementsActive() && root.configReady && root.cfg("dock.enabled", true)
    source: Qt.resolvedUrl("views/Dock.qml")
    onLoaded: if (item && "service" in item) item.service = root
  }

  Loader {
    id: windowControlsLoader
    active: root.enhancementsActive() && root.configReady && root.cfg("windowControls.enabled", true)
    source: Qt.resolvedUrl("views/WindowControls.qml")
    onLoaded: if (item && "service" in item) item.service = root
  }

  Loader {
    id: annotationLoader
    active: root.enhancementsActive() && root.annotationVisible
    source: Qt.resolvedUrl("views/Annotation.qml")
    onLoaded: {
      if (item && "service" in item) item.service = root
    }
  }

  Timer {
    id: deviceRefresh
    interval: 120000
    repeat: true
    running: root.configReady
    onTriggered: root.refreshDevices()
  }

  Timer {
    id: multitaskingLaunchTimeout
    interval: 12000
    repeat: false
    onTriggered: root.resolveMultitaskingLaunch()
  }

  function shutdown() {
    if (root.shuttingDown) return
    root.shuttingDown = true
    var timers = [
      performanceSnapshotTimeout, configWriteDebounce, processRegistryWriteDebounce,
      clipboardWriteDebounce, deviceRefreshDebounce, postureTransition,
      keyboardTransitionTimer, modeTransitionTimer, dockedModeTimer, adaptivePreviewTimer, orientationTransition, wobblyConfigDebounce, clipboardRestart, rotationRestart,
      inputBackendRestart, oskPolicyTimer, clipboardMaintenance, integrationRefresh,
      systemRefresh, systemFallbackRefresh, inputFlush, inputModeCommit, effectRefresh,
      initialConfigSave, deviceRefresh, multitaskingLaunchTimeout
    ]
    for (var timerIndex = 0; timerIndex < timers.length; timerIndex++)
      if (timers[timerIndex]) timers[timerIndex].stop()

    root.clipboardWatching = false
    root.inputQueue = []
    root.pendingCommands = ({})
    root.multitaskingLaunch = null
    root.multitaskingLaunchTarget = null
    root.multitaskingPairLaunch = null
    root.inputNativePending = 0
    root.ownedProcesses = []
    var processes = [
      commandProcess, inputProcess, inputBackendProbe, inputBackendProcess,
      shortcutBindsProcess,
      screenshotProcess, performanceSnapshotProcess, directoryProcess,
      configRecoveryProcess, devicesProcess, deviceMonitorProcess,
      sessionMonitorProcess, monitorsProcess, clientsProcess, systemStateProcess,
      effectsInfoProcess, wobblyControlProcess, wobblyConfigProcess,
      forceQuitTermProcess, forceQuitKillProcess, wifiScanProcess,
      bluetoothScanProcess, audioScanProcess, rotationApplyProcess,
      rotationRollbackProcess, rotationProcess, nightLightProcess, wtypeCheck,
      textWatch, imageWatch, copyProcess, diagnosticsCopyProcess, doctorProcess,
      updateProcess, rollbackProcess, recoveryProcess, backupProcess,
      supportBundleProcess, recorderProcess
    ]
    for (var processIndex = 0; processIndex < processes.length; processIndex++)
      if (processes[processIndex] && processes[processIndex].running) processes[processIndex].running = false
    if (root.processRegistryReady && root.directoriesReady) root.persistProcessRegistry()
  }

  IpcHandler {
    target: "io.omanome.shell"

    function ping(): string { return "ok" }
    function status(): string { return root.statusJson() }
    function enable(): string { return root.setMasterEnabled(true) ? "ok" : "unavailable" }
    function disable(): string { return root.setMasterEnabled(false) ? "ok" : "unavailable" }
    function suspend(): string { return root.setSuspended(true) ? "ok" : "unavailable" }
    function resume(): string { return root.setSuspended(false) ? "ok" : "unavailable" }
    function feature(id: string, enabled: string): string {
      var row = root.featureState(id)
      if (!row || !row.available) return "unavailable"
      if (enabled === "toggle") return root.toggleFeature(id) ? "ok" : "unavailable"
      return root.setConfig(row.configPath, enabled === "true") ? "ok" : "unavailable"
    }
    function profile(name: string): string { return root.setAdaptiveProfile(name) ? "ok" : "unavailable" }
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
    function multitaskingShortcut(action: string): string {
      var result = root.executeMultitaskingShortcut(action)
      return result && result.ok === true ? "ok" : "unavailable"
    }
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
    SnapAssistModel.setLayoutEngine(LayoutEngineModel)
    SplitViewModel.setLayoutEngine(LayoutEngineModel)
    root.refreshFeatureStates()
    root.reloadPaths()
    root.refreshIntegrations()
    root.ensureDirectories()
    root.refreshDevices()
    root.refreshSystemState()
    root.refreshEffectBackend()
    wtypeCheck.running = true
    root.startInputBackendProbe()
    root.startDeviceMonitor()
  }

  Component.onDestruction: root.shutdown()
}
