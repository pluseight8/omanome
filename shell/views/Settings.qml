import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "../components"
import "../models/Apps.js" as Apps
import "../models/Config.js" as Config
import "../models/AdaptiveSettings.js" as AdaptiveSettingsModel
import "../models/Stylus.js" as StylusModel

Item {
  id: root

  property var service: null
  property var panel: null
  property string category: "general"
  property string query: ""
  property string pendingQuery: ""
  property bool mobileDetails: false
  property var multitaskingApplications: []
  property string appPairNameDraft: ""
  property string appPairFirstId: ""
  property string appPairSecondId: ""
  property string appPairRatio: "50/50"
  property string appPairMonitorPolicy: "active"
  property int multitaskingRevision: 0
  property string adaptiveEditorProfile: "desktop"
  property int adaptiveEditorRevision: 0
  property var categories: [
    { key: "general", fallback: "General", description: "Mode, language and profiles", aliases: ["общие", "режим", "язык"] },
    { key: "adaptiveMode", fallback: "Adaptive Mode", description: "Profiles, device rules and safe transitions", aliases: ["adaptive", "profiles", "device rules", "адаптивный режим"] },
    { key: "appearance", fallback: "Appearance", description: "Theme, density and surfaces", aliases: ["вид", "тема", "оформление"] },
    { key: "tabletMode", fallback: "Tablet mode", description: "Desktop, tablet and hybrid behavior", aliases: ["планшет", "сенсорный режим"] },
    { key: "touch", fallback: "Touch", description: "Targets and touch behavior", aliases: ["касание", "сенсор"] },
    { key: "gestures", fallback: "Gestures", description: "Workspace swipe and edge gestures", aliases: ["жесты", "свайп"] },
    { key: "stylus", fallback: "Stylus", description: "Pen, pressure and device mapping", aliases: ["перо", "стилус"] },
    { key: "stylusButtons", fallback: "Stylus buttons", description: "Button actions and eraser", aliases: ["кнопки пера"] },
    { key: "palmRejection", fallback: "Palm rejection", description: "Native input policy and availability", aliases: ["ладонь", "защита"] },
    { key: "handwriting", fallback: "Handwriting", description: "Local handwriting surface", aliases: ["рукописный ввод", "почерк"] },
    { key: "keyboard", fallback: "Keyboard", description: "On-screen keyboard and layers", aliases: ["клавиатура", "osk"] },
    { key: "suggestions", fallback: "Suggestions", description: "Offline suggestions and learning", aliases: ["подсказки", "автозамена"] },
    { key: "windowControls", fallback: "Window controls", description: "Touch-friendly window actions", aliases: ["окна", "кнопки окна"] },
    { key: "dock", fallback: "Dock", description: "Favorites, running apps and reveal", aliases: ["док", "панель"] },
    { key: "overview", fallback: "Overview", description: "Windows, workspaces and search", aliases: ["обзор", "деятельность"] },
    { key: "launcher", fallback: "App Grid", description: "Applications, favorites and folders", aliases: ["приложения", "лаунчер", "сетка"] },
    { key: "multitasking", fallback: "Multitasking", description: "Snap, Split View, App Pairs and restore", aliases: ["многозадачность", "snap", "split", "app pairs", "группы окон"] },
    { key: "workspaces", fallback: "Workspaces", description: "Dynamic or fixed workspace layout", aliases: ["рабочие столы", "пространства"] },
    { key: "quickSettings", fallback: "Quick settings", description: "Tiles and live system controls", aliases: ["быстрые настройки", "переключатели"] },
    { key: "notifications", fallback: "Notifications", description: "Groups, actions and history", aliases: ["уведомления", "центр уведомлений"] },
    { key: "clipboard", fallback: "Clipboard", description: "Private local history", aliases: ["буфер", "история"] },
    { key: "altTab", fallback: "Alt-Tab", description: "Window switcher and previews", aliases: ["переключение окон"] },
    { key: "blur", fallback: "Blur", description: "Compositor blur quality and fallback", aliases: ["размытие", "прозрачность"] },
    { key: "effects", fallback: "Effects", description: "Optional companion effects", aliases: ["эффекты", "wobbly", "куб"] },
    { key: "rotation", fallback: "Rotation", description: "Orientation and sensor backend", aliases: ["поворот", "вращение"] },
    { key: "displays", fallback: "Displays", description: "Monitor targeting and hotplug state", aliases: ["мониторы", "экраны"] },
    { key: "animations", fallback: "Animations", description: "Motion presets and reduced motion", aliases: ["анимации", "движение"] },
    { key: "performance", fallback: "Performance", description: "Quality and frame budget policy", aliases: ["производительность", "gpu"] },
    { key: "battery", fallback: "Battery", description: "Power-aware effects and brightness", aliases: ["батарея", "энергия"] },
    { key: "privacy", fallback: "Privacy", description: "Clipboard and update privacy", aliases: ["приватность", "безопасность"] },
    { key: "accessibility", fallback: "Accessibility", description: "Targets, text, contrast and motion", aliases: ["доступность", "контраст"] },
    { key: "applications", fallback: "Applications", description: "Per-app behavior rules", aliases: ["приложения", "правила"] },
    { key: "shortcuts", fallback: "Shortcuts", description: "Current commands and conflicts", aliases: ["сочетания", "горячие клавиши"] },
    { key: "updates", fallback: "Updates", description: "Check and rollback manually", aliases: ["обновления", "версия"] },
    { key: "backup", fallback: "Backup", description: "Export the versioned Omanome config", aliases: ["резервная копия", "экспорт", "backup"] },
    { key: "recovery", fallback: "Recovery", description: "Recover interrupted updates and inspect rollback points", aliases: ["восстановление", "откат", "recovery"] },
    { key: "diagnostics", fallback: "Diagnostics", description: "Safe runtime health report", aliases: ["диагностика", "doctor"] },
    { key: "about", fallback: "About", description: "Version and compatibility", aliases: ["о программе", "версия"] }
  ]

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
    transitionComponent: "settings"
  }

  readonly property bool compactLayout: tokens.portrait || root.width < tokens.space(760)

  function title(item) { return root.service.tr(item.key, item.fallback) }
  function filteredCategories() {
    var needle = String(root.query || "").toLowerCase().trim()
    if (!needle) return root.categories
    return root.categories.filter(function(item) {
      var value = [item.key, item.fallback, item.description].concat(item.aliases || []).join(" ").toLowerCase()
      return value.indexOf(needle) >= 0
    })
  }

  function selectCategory(key) {
    root.category = String(key || "general")
    root.mobileDetails = true
  }

  function openDeepLink(link) {
    var value = String(link || "").replace(/^settings:\/\//, "").replace(/^\//, "")
    for (var i = 0; i < root.categories.length; i++) if (root.categories[i].key === value) { root.selectCategory(value); return true }
    root.selectCategory("general")
    return false
  }

  function resetCategory() {
    var key = root.category === "stylusButtons" || root.category === "palmRejection" || root.category === "handwriting" || root.category === "suggestions" ? "stylus" : root.category === "adaptiveMode" ? "adaptive" : root.category
    var defaults = Config.get(Config.defaults(), key, null)
    if (defaults !== null) root.service.setConfig(key, defaults)
  }

  function toggle(path) { root.service.setConfig(path, !Boolean(root.service.cfg(path, false))) }
  function percent(path, fallback) { return Math.round(Number(root.service.cfg(path, fallback)) * 100) + "%" }
  function categoryDescription() {
    for (var i = 0; i < root.categories.length; i++) if (root.categories[i].key === root.category) return root.categories[i].description
    return ""
  }

  function adaptiveComponentValue(component, fallback) {
    return root.service && typeof root.service.adaptiveProfileValue === "function"
      ? root.service.adaptiveProfileValue(root.adaptiveEditorProfile, component, fallback) : fallback
  }

  function adaptiveFeatureValue(id, fallback) {
    return root.service && typeof root.service.adaptiveProfileFeature === "function"
      ? root.service.adaptiveProfileFeature(root.adaptiveEditorProfile, id, fallback) : fallback
  }

  function adaptiveFeatureConfigured(id) {
    return root.service && typeof root.service.adaptiveProfileFeatureConfigured === "function"
      ? root.service.adaptiveProfileFeatureConfigured(root.adaptiveEditorProfile, id) : false
  }

  function adaptiveChoiceLabel(value) {
    var text = String(value || "")
    if (text === "suppressed") return "Never"
    if (text === "enabled") return "Enabled"
    if (text === "disabled") return "Disabled"
    if (text === "on") return "On"
    if (text === "off") return "Off"
    return text.charAt(0).toUpperCase() + text.slice(1).replace(/-/g, " ")
  }

  function hasStylusButtons() {
    var devices = root.service && Array.isArray(root.service.stylusDevices) ? root.service.stylusDevices : []
    for (var i = 0; i < devices.length; i++) if (StylusModel.capabilities(devices[i]).buttons > 0) return true
    return false
  }

  function refreshMultitaskingApplications() {
    var result = []
    try {
      var values = DesktopEntries.applications.values || []
      for (var i = 0; i < values.length; i++) {
        var item = Apps.normalize(values[i])
        if (!item || !item.id || item.noDisplay) continue
        result.push({ id: item.id, label: item.name + " · " + item.id, icon: item.icon })
      }
      result.sort(function(a, b) { return a.label.localeCompare(b.label) })
    } catch (error) {
      result = []
    }
    root.multitaskingApplications = result.slice(0, 256)
    if (root.applicationIndex(root.appPairFirstId) < 0) root.appPairFirstId = result.length > 0 ? result[0].id : ""
    if (root.applicationIndex(root.appPairSecondId) < 0) root.appPairSecondId = result.length > 1 ? result[1].id : ""
  }

  function applicationIndex(id) {
    var key = String(id || "")
    for (var i = 0; i < root.multitaskingApplications.length; i++) if (root.multitaskingApplications[i].id === key) return i
    return -1
  }

  function windowGroupEntries() {
    try {
      return root.service && typeof root.service.windowGroupSummaries === "function" ? root.service.windowGroupSummaries() : []
    } catch (error) {
      return []
    }
  }

  function groupLabel(group) {
    var apps = group && Array.isArray(group.apps) ? group.apps : []
    return String(group && group.name || apps.join(" + ") || root.service.tr("windowGroup", "Window group"))
  }

  function setPairMonitorPolicy(policy) {
    var value = String(policy || "active")
    root.appPairMonitorPolicy = value
    root.service.setConfig("multitasking.monitorPolicy", value)
  }

  function saveAppPairFromSettings() {
    var first = String(root.appPairFirstId || "").trim()
    var second = String(root.appPairSecondId || "").trim()
    if (!root.service || !first || !second || first === second || typeof root.service.saveAppPair !== "function") return false
    var options = {
      name: String(root.appPairNameDraft || "").trim(),
      layoutId: "split",
      ratio: root.appPairRatio,
      orientation: "auto",
      preferences: { monitorPolicy: root.appPairMonitorPolicy, targetWorkspace: "" }
    }
    var result = root.service.saveAppPair([first, second], options)
    if (result && result.id) root.appPairNameDraft = ""
    return result
  }

  Component.onCompleted: {
    root.refreshMultitaskingApplications()
    if (!root.compactLayout) root.mobileDetails = true
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refreshMultitaskingApplications() }
  }

  Connections {
    target: root.service
    function onConfigUpdated(path) {
      if (String(path || "").indexOf("multitasking.") === 0) root.multitaskingRevision++
      if (String(path || "").indexOf("adaptive.") === 0 || String(path || "").indexOf("controlCenter.") === 0 || String(path || "").indexOf("accessibility.") === 0)
        root.adaptiveEditorRevision++
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(18)
    spacing: tokens.space(16)

    ColumnLayout {
      id: navigation
      visible: !root.compactLayout || !root.mobileDetails
      Layout.preferredWidth: root.compactLayout ? parent.width : tokens.space(238)
      Layout.fillHeight: true
      spacing: tokens.space(10)

      SectionHeader { Layout.fillWidth: true; title: root.service.tr("settings", "Settings"); subtitle: root.service.tr("settingsHint", "Omanome preferences") }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: tokens.target(44)
        radius: tokens.radius(12)
        color: Util.alpha(Color.foreground, 0.08)
        TextInput {
          anchors.fill: parent
          anchors.leftMargin: tokens.space(12)
          anchors.rightMargin: tokens.space(12)
          verticalAlignment: Text.AlignVCenter
          color: Color.foreground
          font.pixelSize: Style.font.body
          placeholderText: root.service.tr("searchSettings", "Search settings")
          onTextChanged: { root.pendingQuery = text; searchDebounce.restart() }
        }
      }

      Timer {
        id: searchDebounce
        interval: 120
        repeat: false
        onTriggered: root.query = root.pendingQuery
      }

      ListView {
        id: categoryList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: tokens.space(4)
        model: root.filteredCategories()
        delegate: ActionButton {
          required property var modelData
          width: categoryList.width
          minimumHeight: tokens.target(48)
          text: root.title(modelData)
          subtitle: modelData.description
          checked: root.category === modelData.key
          onClicked: root.selectCategory(modelData.key)
        }
      }
    }

    Rectangle { visible: !root.compactLayout; Layout.preferredWidth: 1; Layout.fillHeight: true; color: Util.alpha(Color.foreground, 0.12) }

    Item {
      id: contentHost
      visible: !root.compactLayout || root.mobileDetails
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        spacing: tokens.space(10)

        RowLayout {
          Layout.fillWidth: true
          visible: root.compactLayout
          ActionButton { compact: true; text: root.service.tr("back", "Back"); icon: "‹"; onClicked: root.mobileDetails = false }
          Item { Layout.fillWidth: true }
        }

        SectionHeader {
          Layout.fillWidth: true
          title: root.title({ key: root.category, fallback: root.category })
          subtitle: root.categoryDescription()
        }

        Flickable {
          id: content
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          contentWidth: width
          contentHeight: body.implicitHeight + tokens.space(24)

          Column {
            id: body
            width: content.width
            spacing: tokens.space(12)

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "general"
              ActionButton { width: parent.width; text: root.service.tr("mode", "Mode"); subtitle: root.service.detectedMode; checked: true; onClicked: root.service.setConfig("general.mode", root.service.detectedMode === "desktop" ? "tablet" : "desktop") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["automatic", "desktop", "tablet", "hybrid"]; delegate: ActionButton { required property string modelData; compact: true; text: root.service.tr(modelData, modelData); checked: root.service.cfg("general.mode", "automatic") === modelData; onClicked: root.service.setConfig("general.mode", modelData) } } }
              Text { width: parent.width; text: root.service.tr("profile", "Profile") + ": " + root.service.adaptiveProfile + " → " + root.service.effectiveMode; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: root.service.adaptiveProfiles(); delegate: ActionButton { required property var modelData; compact: true; text: modelData.label; checked: root.service.adaptiveProfile === modelData.id; accessibleDescription: modelData.description; onClicked: root.service.setAdaptiveProfile(modelData.id) } } }
              Flow { width: parent.width; spacing: tokens.space(6); ActionButton { compact: true; text: "System"; checked: root.service.cfg("general.language", "system") === "system"; onClicked: root.service.setConfig("general.language", "system") } ActionButton { compact: true; text: "English"; checked: root.service.cfg("general.language", "system") === "en"; onClicked: root.service.setConfig("general.language", "en") } ActionButton { compact: true; text: "Русский"; checked: root.service.cfg("general.language", "system") === "ru"; onClicked: root.service.setConfig("general.language", "ru") } }
              ActionButton { width: parent.width; text: root.service.tr("largeUi", "Large UI"); subtitle: root.service.tr("largeUiHint", "Increase touch targets and layout density"); checked: root.service.cfg("general.largeUi", false); onClicked: root.toggle("general.largeUi") }
              ActionButton { width: parent.width; text: root.service.tr("reduceMotion", "Reduce motion"); subtitle: root.service.tr("reduceMotionHint", "Also disables expensive motion-driven effects"); checked: root.service.cfg("general.reduceMotion", false); onClicked: root.toggle("general.reduceMotion") }
              SectionHeader { width: parent.width; title: root.service.tr("omanomeBarWidget", "Omanome Bar Widget"); subtitle: root.service.tr("omanomeBarWidgetHint", "Optional entry in the existing standard Omarchy bar") }
              ActionButton { width: parent.width; text: root.service.tr("showOmanomeWidget", "Show Omanome widget"); subtitle: root.service.tr("widgetOptionalHint", "Omanome keeps working when the widget is hidden"); checked: root.service.cfg("controlCenter.widget.enabled", true); onClicked: root.toggle("controlCenter.widget.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["left", "center", "right"]; delegate: ActionButton { required property string modelData; compact: true; text: root.service.tr("widgetPosition" + modelData, modelData.charAt(0).toUpperCase() + modelData.slice(1)); checked: root.service.cfg("controlCenter.widget.position", "right") === modelData; onClicked: root.service.setConfig("controlCenter.widget.position", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("widgetLabel", "Show widget label"); subtitle: root.service.tr("widgetLabelHint", "Keep the bar entry compact by default"); checked: root.service.cfg("controlCenter.widget.showLabel", false); onClicked: root.toggle("controlCenter.widget.showLabel") }
              Text { width: parent.width; text: root.service.tr("widgetPlacementNote", "Placement uses only the official bar widget slots; no overlay or replacement bar is created."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              SectionHeader { width: parent.width; title: root.service.tr("runtimeControl", "Runtime control"); subtitle: root.service.tr("runtimeControlHint", "Temporary controls; OFF is not uninstall") }
              ActionButton { width: parent.width; text: root.service.masterEnabled ? root.service.tr("disableOmanome", "Disable Omanome") : root.service.tr("enableOmanome", "Enable Omanome"); subtitle: root.service.masterEnabled ? root.service.tr("masterOffHint", "Enhancements stop safely; native input and Omarchy remain active") : root.service.tr("masterOnHint", "Restore Omanome enhancements without reinstalling"); checked: root.service.masterEnabled; usable: !root.service.safeMode; onClicked: root.service.setMasterEnabled(!root.service.masterEnabled) }
              ActionButton { width: parent.width; text: root.service.suspended ? root.service.tr("resume", "Resume Omanome") : root.service.tr("suspend", "Suspend Omanome"); subtitle: root.service.suspended ? root.service.tr("resumeHint", "Resume enhancements") : root.service.tr("suspendHint", "Pause enhancements without changing preferences"); checked: root.service.suspended; onClicked: root.service.setSuspended(!root.service.suspended) }
            }

            Column {
              width: parent.width
              spacing: tokens.space(10)
              visible: root.category === "adaptiveMode"

              SectionHeader { width: parent.width; title: root.service.tr("adaptiveMode", "Adaptive Mode"); subtitle: root.service.tr("adaptiveModeHint", "Capability-aware policies with explicit safety precedence") }
              ActionButton { width: parent.width; text: root.service.cfg("adaptive.enabled", true) ? root.service.tr("adaptiveEnabled", "Adaptive Mode") : root.service.tr("adaptiveDisabled", "Adaptive Mode disabled"); subtitle: root.service.cfg("adaptive.enabled", true) ? root.service.tr("adaptiveEnabledHint", "Hardware signals may select Auto behavior") : root.service.tr("adaptiveDisabledHint", "Manual profiles and user toggles remain available"); checked: root.service.cfg("adaptive.enabled", true); onClicked: root.toggle("adaptive.enabled") }
              ActionButton { width: parent.width; text: root.service.tr("automaticTransitions", "Automatic transitions"); subtitle: root.service.tr("automaticTransitionsHint", "Keep the last stable mode when signals are uncertain"); checked: root.service.cfg("adaptive.automaticTransitions", true); usable: root.service.cfg("adaptive.enabled", true); onClicked: root.toggle("adaptive.automaticTransitions") }
              Text { width: parent.width; text: root.service.tr("adaptiveRuntime", "Runtime") + ": " + root.service.adaptiveProfile + " → " + root.service.effectiveMode + (root.service.adaptiveState.preview ? " · preview " + root.service.adaptiveState.previewProfile : "") + " · " + (root.service.dockedModeSummary().active ? root.service.tr("docked", "Docked") : root.service.tr("undocked", "Undocked")); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

              SectionHeader { width: parent.width; title: root.service.tr("physicalKeyboards", "Physical Keyboards"); subtitle: root.service.tr("physicalKeyboardsHint", "Attach/detach transitions are debounced and capability-based") }
              Text { width: parent.width; text: String(root.service.keyboardTransitionSummary().phase || "Disconnected") + " · " + String(root.service.keyboardTransitionSummary().connectedCount || 0) + " connected · " + (root.service.keyboardTransitionSummary().stableConnected ? root.service.tr("stable", "stable") : root.service.tr("waiting", "waiting")); color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["nothing", "hide-osk", "hybrid", "desktop", "ask"]; delegate: ActionButton { required property string modelData; compact: true; text: root.adaptiveChoiceLabel(modelData); checked: root.service.cfg("adaptive.externalKeyboardPolicy", "hybrid") === modelData; onClicked: root.service.setConfig("adaptive.externalKeyboardPolicy", modelData) } } }
              Text { width: parent.width; text: root.service.tr("externalKeyboardPolicy", "External keyboard policy"); color: Color.muted; font.pixelSize: Style.font.caption }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["ignore", "generic", "hybrid", "desktop", "ask"]; delegate: ActionButton { required property string modelData; compact: true; text: root.adaptiveChoiceLabel(modelData); checked: root.service.cfg("adaptive.unknownKeyboardPolicy", "hybrid") === modelData; onClicked: root.service.setConfig("adaptive.unknownKeyboardPolicy", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("deviceHotplug", "Monitor keyboard hotplug"); subtitle: root.service.inputDeviceMonitorAvailable ? root.service.tr("eventDriven", "Event-driven monitor active") : root.service.inputDeviceMonitorReason; checked: root.service.cfg("input.deviceHotplug", true); onClicked: root.toggle("input.deviceHotplug") }
              Flow { width: parent.width; spacing: tokens.space(6); ActionButton { compact: true; text: root.service.tr("detachableKeyboard", "Detachable"); checked: root.service.cfg("input.suppressOskOnDetachableKeyboard", true); onClicked: root.toggle("input.suppressOskOnDetachableKeyboard") } ActionButton { compact: true; text: root.service.tr("bluetoothKeyboard", "Bluetooth"); checked: root.service.cfg("input.suppressOskOnBluetoothKeyboard", true); onClicked: root.toggle("input.suppressOskOnBluetoothKeyboard") } ActionButton { compact: true; text: root.service.tr("physicalKeyboard", "Physical"); checked: root.service.cfg("input.suppressOskOnPhysicalKeyboard", true); onClicked: root.toggle("input.suppressOskOnPhysicalKeyboard") } }

              SectionHeader { width: parent.width; title: root.service.tr("deviceRules", "Device Rules"); subtitle: root.service.tr("deviceRulesHint", "Remembered rules are local metadata; raw device names never enter diagnostics") }
              Text { width: parent.width; text: root.service.cfg("adaptive.deviceRules", []).length + " rule(s) · " + root.service.keyboardDeviceSummaries().length + " current keyboard(s)"; color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; text: root.service.tr("forgetDeviceRules", "Forget remembered device rules"); subtitle: root.service.tr("forgetDeviceRulesHint", "Clear per-device preferences without changing global policies"); usable: root.service.cfg("adaptive.deviceRules", []).length > 0; onClicked: root.service.setConfig("adaptive.deviceRules", []) }
              Text { width: parent.width; text: root.service.tr("deviceRulesSafety", "Unknown or incomplete devices fail closed and do not force a mode change."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

              SectionHeader { width: parent.width; title: root.service.tr("modeTransitions", "Mode Transitions"); subtitle: root.service.tr("modeTransitionsHint", "Local choreography preserves windows, Split View and App Pairs") }
              ActionButton { width: parent.width; text: root.service.tr("transitionAnimations", "Animate mode transitions"); checked: root.service.cfg("adaptive.transition.enabled", true); onClicked: root.toggle("adaptive.transition.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["smooth", "snappy", "minimal"]; delegate: ActionButton { required property string modelData; compact: true; text: root.adaptiveChoiceLabel(modelData); checked: root.service.cfg("adaptive.transition.animationPreset", "smooth") === modelData; onClicked: root.service.setConfig("adaptive.transition.animationPreset", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("transitionOsd", "Show transition OSD"); subtitle: root.service.tr("transitionOsdHint", "Short status feedback; no terminal command spam"); checked: root.service.cfg("adaptive.transition.showOsd", true); onClicked: root.toggle("adaptive.transition.showOsd") }
              Text { width: parent.width; text: root.service.tr("transitionDebounce", "Debounce") + ": " + root.service.cfg("adaptive.transition.debounceMs", 260) + " ms · " + root.service.tr("stabilityWindow", "stability") + ": " + root.service.cfg("adaptive.transition.stabilityMs", 420) + " ms"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { width: parent.width; from: 80; to: 800; stepSize: 10; value: root.service.cfg("adaptive.transition.debounceMs", 260); onMoved: root.service.setConfig("adaptive.transition.debounceMs", Math.round(value)) }
              Slider { width: parent.width; from: 0; to: 1200; stepSize: 10; value: root.service.cfg("adaptive.transition.stabilityMs", 420); onMoved: root.service.setConfig("adaptive.transition.stabilityMs", Math.round(value)) }

              SectionHeader { width: parent.width; title: root.service.tr("profiles", "Profiles"); subtitle: root.service.tr("profilesHint", "Select a stable profile or edit a temporary policy overlay") }
              Flow {
                width: parent.width
                spacing: tokens.space(8)
                Repeater {
                  model: root.service.adaptiveProfiles()
                  delegate: Rectangle {
                    required property var modelData
                    width: root.compactLayout ? parent.width : Math.max(tokens.space(220), (parent.width - tokens.space(8)) / 2)
                    height: tokens.space(136)
                    radius: tokens.radius(14)
                    color: modelData.selected ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.06)
                    border.width: modelData.selected ? 1 : 0
                    border.color: Color.accent
                    Accessible.name: modelData.label + " profile"
                    Accessible.description: modelData.description
                    MouseArea { anchors.fill: parent; z: 0; onClicked: { root.adaptiveEditorProfile = modelData.id; root.service.setAdaptiveProfile(modelData.id) } }
                    Column {
                      anchors.fill: parent
                      anchors.margins: tokens.space(10)
                      spacing: tokens.space(4)
                      z: 1
                      Text { width: parent.width; text: modelData.label; color: modelData.selected ? Color.accent : Color.foreground; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                      Text { width: parent.width; height: tokens.space(32); text: modelData.description; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; elide: Text.ElideRight }
                      Text { width: parent.width; text: modelData.configured ? (modelData.componentCount + " component override(s) · " + modelData.featureCount + " feature override(s)") : root.service.tr("profileDefaults", "Built-in defaults"); color: Color.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                      Row {
                        spacing: tokens.space(5)
                        ActionButton { compact: true; minimumWidth: tokens.space(72); text: modelData.selected ? root.service.tr("selected", "Selected") : root.service.tr("use", "Use"); checked: modelData.selected; onClicked: { root.adaptiveEditorProfile = modelData.id; root.service.setAdaptiveProfile(modelData.id) } }
                        ActionButton { compact: true; minimumWidth: tokens.space(82); text: root.service.tr("preview", "Preview"); onClicked: { root.adaptiveEditorProfile = modelData.id; root.service.beginAdaptivePreview(modelData.id, 6000) } }
                      }
                    }
                  }
                }
              }

              SectionHeader { width: parent.width; title: root.service.tr("profileDetail", "Profile detail") + " · " + root.adaptiveEditorProfile; subtitle: root.service.tr("profileDetailHint", "Changes are stored only in the selected profile overlay") }
              Row { spacing: tokens.space(6); ActionButton { compact: true; text: root.service.tr("useProfile", "Use profile"); onClicked: root.service.setAdaptiveProfile(root.adaptiveEditorProfile) } ActionButton { compact: true; text: root.service.tr("preview", "Preview"); onClicked: root.service.beginAdaptivePreview(root.adaptiveEditorProfile, 6000) } ActionButton { compact: true; text: root.service.tr("resetProfile", "Reset selected profile"); onClicked: root.service.resetAdaptiveProfile(root.adaptiveEditorProfile) } }
              Text { width: parent.width; visible: root.service.adaptivePreviewSummary().active; text: root.service.tr("previewActive", "Preview active") + ": " + root.service.adaptivePreviewSummary().profile + " · " + Math.ceil(root.service.adaptivePreviewSummary().remainingMs / 1000) + " s"; color: Color.accent; font.pixelSize: Style.font.caption }
              ActionButton { width: parent.width; visible: root.service.adaptivePreviewSummary().active; text: root.service.tr("cancelPreview", "Cancel preview"); onClicked: root.service.cancelAdaptivePreview("settings-cancel") }
              Flow { width: parent.width; visible: root.adaptiveEditorProfile === "custom"; spacing: tokens.space(6); Repeater { model: ["auto", "desktop", "tablet", "hybrid"]; delegate: ActionButton { required property string modelData; compact: true; text: root.adaptiveChoiceLabel(modelData); checked: root.service.cfg("adaptive.profiles.custom.mode", "auto") === modelData; onClicked: root.service.setConfig("adaptive.profiles.custom.mode", modelData) } } }
              Text { width: parent.width; visible: root.adaptiveEditorProfile === "custom"; text: root.service.tr("customModeHint", "Custom mode chooses a base mode; component policies below refine it without changing global settings."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

              SectionHeader { width: parent.width; title: root.service.tr("componentBehavior", "Component Behavior"); subtitle: root.service.tr("componentBehaviorHint", "Per-profile affordances; accessibility minimums still win") }
              Repeater {
                model: root.service.adaptiveProfileComponents()
                delegate: Column {
                  id: componentRow
                  required property var modelData
                  property var componentDef: modelData
                  width: parent.width
                  spacing: tokens.space(4)
                  Text { width: parent.width; text: componentRow.componentDef.label + " · " + root.adaptiveChoiceLabel(root.adaptiveComponentValue(componentRow.componentDef.key, componentRow.componentDef.type === "boolean" ? true : "")); color: Color.foreground; font.pixelSize: Style.font.body }
                  Text { width: parent.width; text: componentRow.componentDef.description; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
                  Flow {
                    width: parent.width
                    spacing: tokens.space(5)
                    Repeater {
                      model: componentRow.componentDef.values
                      delegate: ActionButton {
                        required property string modelData
                        compact: true
                        text: root.adaptiveChoiceLabel(modelData)
                        checked: componentRow.componentDef.type === "boolean" ? root.adaptiveComponentValue(componentRow.componentDef.key, true) === (modelData === "on") : String(root.adaptiveComponentValue(componentRow.componentDef.key, "")) === modelData
                        onClicked: root.service.setAdaptiveComponent(root.adaptiveEditorProfile, componentRow.componentDef.key, componentRow.componentDef.type === "boolean" ? modelData === "on" : modelData)
                      }
                    }
                  }
                }
              }

              SectionHeader { width: parent.width; title: root.service.tr("profileFeatures", "Profile feature toggles"); subtitle: root.service.tr("profileFeaturesHint", "These are temporary profile overrides; user preferences remain separate") }
              Flow { width: parent.width; spacing: tokens.space(5); Repeater { model: root.service.adaptiveProfileFeatures(); delegate: ActionButton { required property var modelData; compact: true; text: modelData.label + (root.adaptiveFeatureConfigured(modelData.id) ? " · custom" : ""); checked: root.adaptiveFeatureValue(modelData.id, true); onClicked: root.service.setAdaptiveFeatureOverride(root.adaptiveEditorProfile, modelData.id, !root.adaptiveFeatureValue(modelData.id, true)) } } }

              SectionHeader { width: parent.width; title: root.service.tr("dockedMode", "Docked Mode"); subtitle: root.service.tr("dockedModeSettingsHint", "Optional external monitor policy for Auto only") }
              ActionButton { width: parent.width; text: root.service.tr("dockedModeEnabled", "Enable Docked mode"); subtitle: root.service.dockedModeSummary().reason; checked: root.service.cfg("adaptive.dockedMode.enabled", true); onClicked: root.toggle("adaptive.dockedMode.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["external-monitor-and-keyboard", "external-monitor"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "external-monitor" ? root.service.tr("externalMonitor", "External monitor") : root.service.tr("externalMonitorAndKeyboard", "Monitor + keyboard"); checked: root.service.cfg("adaptive.dockedMode.trigger", "external-monitor-and-keyboard") === modelData; onClicked: root.service.setConfig("adaptive.dockedMode.trigger", modelData) } } }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["desktop", "tablet", "hybrid"]; delegate: ActionButton { required property string modelData; compact: true; text: root.adaptiveChoiceLabel(modelData); checked: root.service.cfg("adaptive.dockedMode.profile", "desktop") === modelData; onClicked: root.service.setConfig("adaptive.dockedMode.profile", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("keepTouch", "Keep internal touch enabled"); subtitle: root.service.tr("keepTouchHint", "Docked desktop affordances do not disable the tablet screen"); checked: root.service.cfg("adaptive.dockedMode.keepTouch", true); onClicked: root.toggle("adaptive.dockedMode.keepTouch") }
              ActionButton { width: parent.width; text: root.service.tr("restoreAutoState", "Restore previous Auto state"); subtitle: root.service.tr("restoreAutoStateHint", "Undocking returns the last stable automatic mode"); checked: root.service.cfg("adaptive.dockedMode.restoreAutoState", true); onClicked: root.toggle("adaptive.dockedMode.restoreAutoState") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["preserve", "auto", "locked", "unchanged"]; delegate: ActionButton { required property string modelData; compact: true; text: root.adaptiveChoiceLabel(modelData); checked: root.service.cfg("adaptive.dockedMode.rotation", "preserve") === modelData; onClicked: root.service.setConfig("adaptive.dockedMode.rotation", modelData) } } }
              Text { width: parent.width; text: root.service.tr("dockedRuntime", "Runtime") + ": " + (root.service.dockedModeSummary().active ? root.service.tr("docked", "Docked") : root.service.tr("undocked", "Undocked")) + " · " + root.service.dockedModeSummary().monitorCount + " monitor(s) · " + root.service.dockedModeSummary().keyboardCount + " keyboard(s)"; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

              SectionHeader { width: parent.width; title: root.service.tr("adaptiveNotifications", "Notifications"); subtitle: root.service.tr("adaptiveNotificationsHint", "Short OSD feedback without changing the standard bar") }
              ActionButton { width: parent.width; text: root.service.tr("transitionOsd", "Transition OSD"); checked: root.service.cfg("adaptive.transition.showOsd", true); onClicked: root.toggle("adaptive.transition.showOsd") }
              ActionButton { width: parent.width; text: root.service.tr("controlCenterOsd", "Control Center status OSD"); checked: root.service.cfg("controlCenter.osd.enabled", true); onClicked: root.toggle("controlCenter.osd.enabled") }
              ActionButton { width: parent.width; text: root.service.tr("notificationPopups", "Adaptive notification popups"); subtitle: root.service.componentPolicy.notificationPopups ? root.service.tr("enabled", "Enabled") : root.service.tr("profileSuppressed", "Suppressed by profile"); checked: root.service.cfg("notifications.enabled", true); onClicked: root.toggle("notifications.enabled") }

              SectionHeader { width: parent.width; title: root.service.tr("adaptiveAdvanced", "Advanced"); subtitle: root.service.tr("adaptiveAdvancedHint", "Acyclic precedence: safety → accessibility → user → profile → Auto → defaults") }
              Text { width: parent.width; text: root.service.tr("precedence", "Precedence") + ": Safety → Accessibility → Manual feature override → Profile → Auto device mode → Defaults"; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; text: root.service.tr("automaticChanges", "Allow automatic component changes"); subtitle: root.service.tr("automaticChangesHint", "Disable this for a complete manual escape hatch"); checked: root.service.cfg("adaptive.automaticTransitions", true); onClicked: root.toggle("adaptive.automaticTransitions") }
              ActionButton { width: parent.width; text: root.service.tr("openAccessibility", "Open Accessibility"); subtitle: root.service.tr("openAccessibilityHint", "Accessibility minimums always override density reductions"); onClicked: root.selectCategory("accessibility") }
              ActionButton { width: parent.width; text: root.service.tr("resetAdaptive", "Reset Adaptive Mode settings"); subtitle: root.service.tr("resetAdaptiveHint", "Only the adaptive section is reset"); onClicked: root.resetCategory() }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "appearance"
              ActionButton { width: parent.width; text: root.service.tr("theme", "Theme"); subtitle: root.service.tr("followOmarchy", "Follows Omarchy theme tokens"); checked: true; usable: false }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["comfortable", "compact"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("appearance.density", "comfortable") === modelData; onClicked: root.service.setConfig("appearance.density", modelData) } } }
              Text { text: root.service.tr("surfaceRadius", "Surface radius") + ": " + root.service.cfg("appearance.radius", 18) + " px"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { width: parent.width; from: 8; to: 32; value: root.service.cfg("appearance.radius", 18); onMoved: root.service.setConfig("appearance.radius", Math.round(value)) }
              Text { text: root.service.tr("surfaceOpacity", "Surface opacity") + ": " + percent("appearance.opacity", 0.96); color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { width: parent.width; from: 0.65; to: 1; value: root.service.cfg("appearance.opacity", 0.96); onMoved: root.service.setConfig("appearance.opacity", Math.round(value * 100) / 100) }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "tabletMode" || root.category === "touch" || root.category === "gestures"
              ActionButton { width: parent.width; text: root.service.tr("touchscreen", "Touchscreen"); subtitle: root.service.hasTouchscreen ? root.service.tr("detected", "Detected") : root.service.tr("notDetected", "Not detected"); checked: root.service.hasTouchscreen && root.service.cfg("tabletMode.enabled", true); usable: root.service.hasTouchscreen; onClicked: root.toggle("tabletMode.enabled") }
              ActionButton { width: parent.width; text: root.service.tr("automaticAdaptation", "Automatic adaptation"); subtitle: root.service.lastInput + " · " + root.service.detectedMode; checked: root.service.cfg("tabletMode.autoFromTouch", true); onClicked: root.toggle("tabletMode.autoFromTouch") }
              Text { text: root.service.tr("touchTarget", "Touch target") + ": " + root.service.cfg("tabletMode.touchTarget", 48) + " px · " + root.service.responsiveState.breakpoint + " · " + root.service.responsiveState.orientation; color: Color.muted; font.pixelSize: Style.font.caption }
              Slider { width: parent.width; from: 40; to: 72; value: root.service.cfg("tabletMode.touchTarget", 48); onMoved: root.service.setConfig("tabletMode.touchTarget", Math.round(value)) }
              Flow { width: parent.width; visible: root.category === "tabletMode"; spacing: tokens.space(6); Repeater { model: ["adaptive", "bottom", "left", "right"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "adaptive" ? root.service.tr("adaptive", "Adaptive") : modelData; checked: root.service.cfg("tabletMode.dockPreference", "adaptive") === modelData || (modelData === "left" && root.service.cfg("tabletMode.dockPreference", "adaptive") === "side"); onClicked: root.service.setConfig("tabletMode.dockPreference", modelData === "left" ? "side" : modelData) } } }
              Text { width: parent.width; visible: root.category === "tabletMode"; text: root.service.tr("modeReason", "Mode reason") + ": " + root.service.tabletModeState.reason + " · Dock " + root.service.tabletProfile.dockPosition + " · " + (root.service.tabletProfile.oskAutoShow ? root.service.tr("oskReady", "OSK adaptive") : root.service.tr("desktop", "Desktop")); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; visible: root.category !== "tabletMode"; text: root.service.tr("invertWorkspaceSwipe", "Invert workspace swipe"); checked: root.service.cfg("touch.invert", false); onClicked: root.toggle("touch.invert") }
              Text { width: parent.width; visible: root.category === "gestures"; text: root.service.statusObject().touch.workspaceSwipe ? root.service.tr("gesturesReady", "Workspace swipe is enabled") : root.service.tr("gesturesUnavailable", "Workspace swipe is disabled for the active fullscreen policy"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "stylus" || root.category === "stylusButtons" || root.category === "palmRejection" || root.category === "handwriting"
              ActionButton { width: parent.width; visible: root.category === "stylus"; text: root.service.tr("stylus", "Stylus"); subtitle: root.service.hasStylus ? root.service.stylusDevices.length + " device(s)" : root.service.tr("notDetected", "Not detected"); checked: root.service.cfg("stylus.enabled", true); usable: root.service.hasStylus; onClicked: root.toggle("stylus.enabled") }
              ActionButton { width: parent.width; visible: root.category === "palmRejection"; text: root.service.tr("palmRejection", "Palm rejection"); subtitle: root.service.hasStylus ? root.service.tr("nativePolicy", "Native libinput policy") : root.service.tr("stylusUnavailable", "Stylus device not detected"); checked: root.service.cfg("stylus.palmRejection", "automatic") !== "off"; usable: root.service.hasStylus; onClicked: root.service.setConfig("stylus.palmRejection", root.service.cfg("stylus.palmRejection", "automatic") === "off" ? "automatic" : "off") }
              ActionButton { width: parent.width; visible: root.category === "handwriting"; text: root.service.tr("handwriting", "Handwriting"); subtitle: root.service.inputBackendAvailable ? root.service.tr("localBackend", "Local input backend available") : root.service.tr("optionalBackend", "Optional local input backend is not installed"); checked: root.service.cfg("keyboard.mode", "standard") === "handwriting"; usable: root.service.inputBackendAvailable; onClicked: root.service.setConfig("keyboard.mode", "handwriting") }
              ActionButton { width: parent.width; visible: root.category === "stylusButtons"; text: root.service.tr("stylusButtons", "Stylus buttons"); subtitle: root.hasStylusButtons() ? root.service.tr("mappingShown", "Generic mapping is available") : root.service.tr("noStylusButtons", "No button-capable stylus detected"); checked: root.hasStylusButtons(); usable: false }
              ActionButton { width: parent.width; visible: root.category === "stylus"; text: root.service.tr("annotation", "Annotation"); subtitle: root.service.cfg("stylus.annotation", true) ? root.service.tr("overlayAvailable", "Overlay available from Quick Settings") : root.service.tr("disabled", "Disabled"); checked: root.service.cfg("stylus.annotation", true); onClicked: root.toggle("stylus.annotation") }
              Text { width: parent.width; visible: root.category === "stylus"; text: root.service.tr("stylusCapabilities", "Pressure, tilt, rotation, proximity and eraser capabilities are passed through to native Wayland tablet clients."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Repeater { visible: root.category === "stylus"; model: root.service.stylusDevices; delegate: Column { required property var modelData; width: parent.width; property var info: StylusModel.diagnostics(modelData, "hyprland"); Text { width: parent.width; text: info.name + " · " + info.type + " · " + info.backend; color: Color.foreground; font.pixelSize: Style.font.body; elide: Text.ElideRight } Text { width: parent.width; text: "pressure " + (info.pressure ? "yes" : "no") + " · tilt " + (info.tiltX || info.tiltY ? "yes" : "no") + " · eraser " + (info.eraser ? "yes" : "no") + " · buttons " + info.buttons; color: Color.muted; font.pixelSize: Style.font.caption } } }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "keyboard" || root.category === "suggestions"
              ActionButton { width: parent.width; text: root.service.tr("keyboard", "Keyboard"); subtitle: root.service.inputBackendAvailable ? root.service.tr("nativeWayland", "Native Wayland") : (root.service.wtypeAvailable ? root.service.tr("wtypeFallback", "wtype fallback") : root.service.tr("backendUnavailable", "input backend unavailable")); checked: root.service.cfg("keyboard.enabled", true); onClicked: root.toggle("keyboard.enabled") }
              ActionButton { width: parent.width; visible: root.category === "keyboard"; text: root.service.tr("autoShowKeyboard", "Auto-show on editable fields"); subtitle: root.service.inputBackendAvailable ? root.service.tr("inputBackendReady", "Optional input-method backend") : root.service.tr("optionalBackend", "Requires optional input-method companion"); checked: root.service.cfg("keyboard.autoShow", true); usable: root.service.inputBackendAvailable; onClicked: root.toggle("keyboard.autoShow") }
              ActionButton { width: parent.width; visible: root.category === "suggestions"; text: root.service.tr("suggestions", "Suggestions"); subtitle: root.service.inputBackendAvailable ? root.service.tr("offlineEngine", "Local engine available") : root.service.tr("noCloudPrediction", "No cloud prediction is enabled"); checked: root.service.cfg("keyboard.suggestions", true); usable: root.service.inputBackendAvailable; onClicked: root.toggle("keyboard.suggestions") }
              ActionButton { width: parent.width; visible: root.category === "keyboard"; text: root.service.tr("toolbar", "Toolbar"); checked: root.service.cfg("keyboard.toolbar", true); onClicked: root.toggle("keyboard.toolbar") }
              ActionButton { width: parent.width; visible: root.category === "keyboard"; text: root.service.tr("keyPopup", "Key popup"); checked: root.service.cfg("keyboard.keyPopup", true); onClicked: root.toggle("keyboard.keyPopup") }
              ActionButton { width: parent.width; visible: root.category === "keyboard"; text: root.service.tr("longPress", "Long-press alternates"); checked: root.service.cfg("keyboard.longPress", true); onClicked: root.toggle("keyboard.longPress") }
              Text { visible: root.category === "keyboard"; text: root.service.tr("keyboardHeight", "Keyboard height") + ": " + root.service.cfg("keyboard.height", 300) + " px"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { visible: root.category === "keyboard"; width: parent.width; from: 220; to: 520; value: root.service.cfg("keyboard.height", 300); onMoved: root.service.setConfig("keyboard.height", Math.round(value)) }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "windowControls" || root.category === "dock"
              ActionButton { width: parent.width; visible: root.category === "windowControls"; text: root.service.tr("windowControls", "Window controls"); subtitle: root.service.cfg("windowControls.position", "top-right"); checked: root.service.cfg("windowControls.enabled", true); onClicked: root.toggle("windowControls.enabled") }
              ActionButton { width: parent.width; visible: root.category === "dock"; text: root.service.tr("dock", "Dock"); subtitle: root.service.cfg("dock.position", "bottom"); checked: root.service.cfg("dock.enabled", true); onClicked: root.toggle("dock.enabled") }
              Flow { width: parent.width; visible: root.category === "dock"; spacing: tokens.space(6); Repeater { model: ["bottom", "left", "right"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("dock.position", "bottom") === modelData; onClicked: root.service.setConfig("dock.position", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "dock"; text: root.service.tr("autohide", "Autohide"); subtitle: root.service.cfg("dock.autohideMode", "intelligent"); checked: root.service.cfg("dock.autohide", true); onClicked: root.toggle("dock.autohide") }
              Flow { width: parent.width; visible: root.category === "dock"; spacing: tokens.space(6); Repeater { model: ["never", "autohide", "intelligent", "fullscreen-only"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("dock.autohideMode", "intelligent") === modelData; onClicked: root.service.setConfig("dock.autohideMode", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "dock"; text: root.service.tr("runningApplications", "Running applications"); checked: root.service.cfg("dock.runningApplications", true); onClicked: root.toggle("dock.runningApplications") }
              Text { visible: root.category === "dock"; text: root.service.tr("iconSize", "Icon size") + ": " + root.service.cfg("dock.iconSize", 48) + " px"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { visible: root.category === "dock"; width: parent.width; from: 32; to: 72; value: root.service.cfg("dock.iconSize", 48); onMoved: root.service.setConfig("dock.iconSize", Math.round(value)) }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "overview" || root.category === "launcher" || root.category === "workspaces"
              ActionButton { width: parent.width; visible: root.category === "overview"; text: root.service.tr("overview", "Overview"); subtitle: root.service.cfg("overview.showAllWorkspaces", false) ? root.service.tr("allWorkspaces", "All workspaces") : root.service.tr("currentWorkspace", "Current workspace first"); checked: root.service.cfg("overview.enabled", true); onClicked: root.toggle("overview.enabled") }
              ActionButton { width: parent.width; visible: root.category === "overview"; text: root.service.tr("showAllWorkspaces", "Show all workspaces"); checked: root.service.cfg("overview.showAllWorkspaces", false); onClicked: root.toggle("overview.showAllWorkspaces") }
              Flow { width: parent.width; visible: root.category === "workspaces"; spacing: tokens.space(6); Repeater { model: ["dynamic", "fixed"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("overview.workspaceMode", "dynamic") === modelData; onClicked: root.service.setConfig("overview.workspaceMode", modelData) } } }
              Text { visible: root.category === "workspaces"; text: root.service.tr("fixedWorkspaceCount", "Fixed workspace count") + ": " + root.service.cfg("overview.fixedWorkspaceCount", 5); color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { visible: root.category === "workspaces"; width: parent.width; from: 1; to: 10; value: root.service.cfg("overview.fixedWorkspaceCount", 5); onMoved: root.service.setConfig("overview.fixedWorkspaceCount", Math.round(value)) }
              Flow { width: parent.width; visible: root.category === "workspaces"; spacing: tokens.space(6); Repeater { model: ["horizontal", "vertical"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("overview.workspaceOrientation", "horizontal") === modelData; onClicked: root.service.setConfig("overview.workspaceOrientation", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "launcher"; text: root.service.tr("launcher", "App grid"); subtitle: root.service.cfg("launcher.categories", true) ? root.service.tr("categoriesEnabled", "Categories enabled") : root.service.tr("allApps", "All applications"); checked: root.service.cfg("launcher.enabled", true); onClicked: root.toggle("launcher.enabled") }
              Text { visible: root.category === "launcher"; text: root.service.tr("gridColumns", "Grid columns") + ": " + root.service.cfg("launcher.gridColumns", 6) + " · adaptive to viewport"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { visible: root.category === "launcher"; width: parent.width; from: 3; to: 10; value: root.service.cfg("launcher.gridColumns", 6); onMoved: root.service.setConfig("launcher.gridColumns", Math.round(value)) }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "quickSettings" || root.category === "notifications" || root.category === "clipboard"
              ActionButton { width: parent.width; visible: root.category === "quickSettings"; text: root.service.tr("quickSettings", "Quick settings"); subtitle: root.service.systemState.wifiAvailable ? root.service.tr("liveBackend", "Live backend") : root.service.tr("someBackendsUnavailable", "Some backends unavailable"); checked: true; usable: false }
              ActionButton { width: parent.width; visible: root.category === "notifications"; text: root.service.tr("notifications", "Notifications"); subtitle: root.service.cfg("notifications.groupByApp", true) ? root.service.tr("groupedByApp", "Grouped by app") : root.service.tr("flatHistory", "Flat history"); checked: root.service.cfg("notifications.enabled", true); onClicked: root.toggle("notifications.enabled") }
              ActionButton { width: parent.width; visible: root.category === "notifications"; text: root.service.tr("doNotDisturb", "Do not disturb"); subtitle: root.service.systemState.dndAvailable ? root.service.tr("nativeService", "Omarchy notification service") : root.service.tr("backendUnavailable", "Backend unavailable"); checked: root.service.systemState.dnd === true; usable: root.service.systemState.dndAvailable; onClicked: root.service.setDoNotDisturb(!root.service.systemState.dnd) }
              ActionButton { width: parent.width; visible: root.category === "clipboard"; text: root.service.tr("clipboard", "Clipboard"); subtitle: root.service.clipboardHistory.length + " entries · " + root.service.tr("privacyAware", "privacy-aware"); checked: root.service.cfg("clipboard.enabled", true); onClicked: root.toggle("clipboard.enabled") }
              ActionButton { width: parent.width; visible: root.category === "clipboard"; text: root.service.tr("privateMode", "Private mode"); subtitle: root.service.tr("stopCapture", "Stop capture and keep existing history"); checked: root.service.cfg("privacy.clipboardPrivate", false); onClicked: root.toggle("privacy.clipboardPrivate") }
              ActionButton { width: parent.width; visible: root.category === "clipboard"; text: root.service.tr("clearUnpinned", "Clear unpinned clipboard"); onClicked: root.service.clearClipboardUnpinned() }
            }

            Column {
              width: parent.width
              spacing: tokens.space(12)
              visible: root.category === "multitasking"

              SectionHeader { width: parent.width; title: root.service.tr("snapAssist", "Snap Assist"); subtitle: root.service.tr("snapAssistHint", "Preview safe zones while dragging a window") }
              ActionButton { width: parent.width; text: root.service.tr("multitaskingEnabled", "Multitasking"); subtitle: root.service.cfg("multitasking.enabled", true) ? root.service.tr("multitaskingReady", "Snap and Split View are available") : root.service.tr("disabled", "Disabled"); checked: root.service.cfg("multitasking.enabled", true); onClicked: root.toggle("multitasking.enabled") }
              ActionButton { width: parent.width; text: root.service.tr("snapEdgeZones", "Edge zones"); subtitle: root.service.tr("snapEdgeZonesHint", "Use the target monitor geometry and reserved bar/dock space"); checked: root.service.cfg("multitasking.snapAssist.edgeZones", true); usable: root.service.cfg("multitasking.enabled", true); onClicked: root.toggle("multitasking.snapAssist.edgeZones") }
              ActionButton { width: parent.width; text: root.service.tr("snapPreview", "Preview before commit"); subtitle: root.service.tr("snapPreviewHint", "A visual preview never moves a real window"); checked: root.service.cfg("multitasking.snapAssist.preview", true); usable: root.service.cfg("multitasking.enabled", true); onClicked: root.toggle("multitasking.snapAssist.preview") }
              Text { width: parent.width; text: root.service.tr("snapSensitivity", "Snap sensitivity") + ": " + Number(root.service.cfg("multitasking.snapAssist.sensitivity", 1.0)).toFixed(2); color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { width: parent.width; from: 0.5; to: 1.5; stepSize: 0.05; value: root.service.cfg("multitasking.snapAssist.sensitivity", 1.0); enabled: root.service.cfg("multitasking.enabled", true); onMoved: root.service.setConfig("multitasking.snapAssist.sensitivity", Math.round(value * 20) / 20) }
              Text { width: parent.width; text: root.service.tr("snapDwell", "Touch dwell") + ": " + root.service.cfg("multitasking.snapAssist.dwellMs", 220) + " ms · stylus " + root.service.cfg("multitasking.snapAssist.stylusDwellMs", 120) + " ms"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { width: parent.width; from: 80; to: 600; stepSize: 10; value: root.service.cfg("multitasking.snapAssist.dwellMs", 220); enabled: root.service.cfg("multitasking.enabled", true); onMoved: root.service.setConfig("multitasking.snapAssist.dwellMs", Math.round(value)) }
              Flow { width: parent.width; spacing: tokens.space(6); ActionButton { compact: true; text: root.service.tr("portraitLayouts", "Portrait layouts"); checked: root.service.cfg("multitasking.snapAssist.portraitLayouts", true); onClicked: root.toggle("multitasking.snapAssist.portraitLayouts") } ActionButton { compact: true; text: root.service.tr("autoSecondWindowPicker", "Second-window picker"); checked: root.service.cfg("multitasking.snapAssist.autoSecondWindowPicker", true); onClicked: root.toggle("multitasking.snapAssist.autoSecondWindowPicker") } }
              Text { width: parent.width; text: root.service.tr("layoutCatalog", "Layouts") + ": " + root.service.cfg("multitasking.layouts", []).length + " configured · " + root.service.cfg("multitasking.customLayouts", []).length + " custom"; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

              SectionHeader { width: parent.width; title: root.service.tr("tabletSwitcher", "Tablet switcher"); subtitle: root.service.tr("tabletSwitcherHint", "Large cards with horizontal touch navigation") }
              ActionButton { width: parent.width; text: root.service.tr("tabletSwitcherEnabled", "Tablet task switcher"); subtitle: root.service.tr("tabletSwitcherEnabledHint", "Automatically uses large cards for touch and stylus input"); checked: root.service.cfg("multitasking.tabletSwitcher.enabled", true); onClicked: root.toggle("multitasking.tabletSwitcher.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["automatic", "always", "never"]; delegate: ActionButton { required property string modelData; compact: true; text: root.service.tr(modelData, modelData); checked: root.service.cfg("multitasking.tabletSwitcher.mode", "automatic") === modelData; onClicked: root.service.setConfig("multitasking.tabletSwitcher.mode", modelData) } } }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["current-workspace", "current-monitor", "all-workspaces"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "current-workspace" ? root.service.tr("currentWorkspace", "Current workspace") : modelData === "current-monitor" ? root.service.tr("currentMonitor", "Current monitor") : root.service.tr("allWorkspaces", "All workspaces"); checked: root.service.cfg("multitasking.tabletSwitcher.scope", "current-workspace") === modelData; onClicked: root.service.setConfig("multitasking.tabletSwitcher.scope", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("closeOnSwipe", "Swipe up to close"); subtitle: root.service.tr("closeOnSwipeHint", "Disabled by default to prevent accidental closes"); checked: root.service.cfg("multitasking.tabletSwitcher.closeOnSwipe", false); onClicked: root.toggle("multitasking.tabletSwitcher.closeOnSwipe") }

              SectionHeader { width: parent.width; title: root.service.tr("layoutPersistence", "Layout persistence"); subtitle: root.service.tr("layoutPersistenceHint", "Only app identities and layout metadata are saved") }
              ActionButton { width: parent.width; text: root.service.tr("layoutPersistenceEnabled", "Remember layouts"); checked: root.service.cfg("multitasking.layoutPersistence.enabled", true); onClicked: root.toggle("multitasking.layoutPersistence.enabled") }
              ActionButton { width: parent.width; text: root.service.tr("recentLayouts", "Recent layouts"); subtitle: (root.service.layoutPersistenceSummary ? root.service.layoutPersistenceSummary().recentCount : 0) + " / " + root.service.cfg("multitasking.layoutPersistence.maxRecent", 12); checked: root.service.cfg("multitasking.layoutPersistence.recentEnabled", true); onClicked: root.toggle("multitasking.layoutPersistence.recentEnabled") }
              Text { width: parent.width; text: root.service.tr("layoutMetadataOnly", "Saved layouts never contain window addresses, PIDs, titles or document contents."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

              SectionHeader { width: parent.width; title: root.service.tr("splitView", "Split View"); subtitle: root.service.tr("splitViewHint", "Two-window layout with a large, transactional divider") }
              ActionButton { width: parent.width; text: root.service.tr("splitDivider", "Divider handle"); subtitle: root.service.cfg("multitasking.splitView.handleSize", 48) + " px touch target"; checked: root.service.cfg("multitasking.splitView.divider", true); onClicked: root.toggle("multitasking.splitView.divider") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["33/67", "40/60", "50/50", "60/40", "67/33"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("multitasking.splitView.defaultRatio", "50/50") === modelData; onClicked: root.service.setConfig("multitasking.splitView.defaultRatio", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("rememberRatio", "Remember manual ratio"); subtitle: root.service.tr("rememberRatioHint", "Manual resize updates the group instead of being overwritten"); checked: root.service.cfg("multitasking.splitView.rememberRatio", true); onClicked: root.toggle("multitasking.splitView.rememberRatio") }
              ActionButton { width: parent.width; text: root.service.tr("autoConvertRotation", "Convert on rotation"); checked: root.service.cfg("multitasking.splitView.autoConvertOnRotation", true); onClicked: root.toggle("multitasking.splitView.autoConvertOnRotation") }
              ActionButton { width: parent.width; text: root.service.tr("dividerAutohide", "Auto-hide divider"); subtitle: root.service.cfg("multitasking.splitView.autoHideMs", 1800) + " ms"; checked: root.service.cfg("multitasking.splitView.autoHide", true); onClicked: root.toggle("multitasking.splitView.autoHide") }

              SectionHeader { width: parent.width; title: root.service.tr("appPairs", "App Pairs"); subtitle: root.service.tr("appPairsHint", "Save two application identities and restore their split layout") }
              Rectangle {
                width: parent.width
                height: tokens.target(48)
                radius: tokens.radius(12)
                color: Util.alpha(Color.foreground, 0.06)
                border.width: 1
                border.color: Util.alpha(Color.foreground, 0.16)
                TextInput {
                  anchors.fill: parent
                  anchors.leftMargin: tokens.space(12)
                  anchors.rightMargin: tokens.space(12)
                  verticalAlignment: Text.AlignVCenter
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  text: root.appPairNameDraft
                  placeholderText: root.service.tr("appPairName", "Pair name (optional)")
                  onTextChanged: root.appPairNameDraft = text
                }
              }
              RowLayout {
                width: parent.width
                spacing: tokens.space(8)
                ComboBox {
                  id: pairFirstApplication
                  Layout.fillWidth: true
                  model: root.multitaskingApplications
                  textRole: "label"
                  valueRole: "id"
                  currentIndex: root.applicationIndex(root.appPairFirstId)
                  Accessible.name: root.service.tr("appA", "Application A")
                  onActivated: function(index) { if (index >= 0 && index < root.multitaskingApplications.length) root.appPairFirstId = root.multitaskingApplications[index].id }
                }
                ComboBox {
                  id: pairSecondApplication
                  Layout.fillWidth: true
                  model: root.multitaskingApplications
                  textRole: "label"
                  valueRole: "id"
                  currentIndex: root.applicationIndex(root.appPairSecondId)
                  Accessible.name: root.service.tr("appB", "Application B")
                  onActivated: function(index) { if (index >= 0 && index < root.multitaskingApplications.length) root.appPairSecondId = root.multitaskingApplications[index].id }
                }
              }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["33/67", "40/60", "50/50", "60/40", "67/33"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.appPairRatio === modelData; onClicked: root.appPairRatio = modelData } } }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["active", "original", "ask"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "active" ? root.service.tr("activeMonitor", "Active monitor") : modelData === "original" ? root.service.tr("originalMonitor", "Original monitor") : root.service.tr("ask", "Ask"); checked: root.appPairMonitorPolicy === modelData; onClicked: root.setPairMonitorPolicy(modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("saveAppPair", "Save App Pair"); subtitle: root.multitaskingApplications.length < 2 ? root.service.tr("notEnoughApps", "At least two visible applications are required") : root.service.tr("saveAppPairHint", "Only app IDs and layout metadata are stored"); usable: root.multitaskingApplications.length >= 2 && root.appPairFirstId !== root.appPairSecondId; onClicked: root.saveAppPairFromSettings() }
              Repeater {
                model: root.multitaskingRevision >= 0 ? root.windowGroupEntries() : []
                delegate: Surface {
                  required property var modelData
                  width: parent.width
                  height: tokens.target(66)
                  surfaceRadius: tokens.radius(12)
                  surfaceColor: Color.foreground
                  surfaceOpacity: 0.05
                  Row {
                    anchors.fill: parent
                    anchors.margins: tokens.space(8)
                    spacing: tokens.space(8)
                    Column {
                      width: parent.width - tokens.space(92)
                      anchors.verticalCenter: parent.verticalCenter
                      Text { width: parent.width; text: root.groupLabel(modelData); color: Color.foreground; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                      Text { width: parent.width; text: String(modelData.type || "group") + " · " + String(modelData.layout && modelData.layout.ratio || "50/50") + " · " + String(modelData.monitorPolicy || "active"); color: Color.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                    }
                    ActionButton { anchors.verticalCenter: parent.verticalCenter; compact: true; text: root.service.tr("delete", "Delete"); accessibleName: root.service.tr("deleteGroup", "Delete window group"); onClicked: root.service.removeWindowGroup(modelData.id) }
                  }
                }
              }

              SectionHeader { width: parent.width; title: root.service.tr("windowGroups", "Window Groups"); subtitle: root.service.tr("windowGroupsHint", "Runtime identities stay ephemeral; persistent data is metadata only") }
              Text { width: parent.width; text: root.service.windowGroupEntries().length + " group(s) · " + root.service.tr("groupLifecycleHint", "Groups break gracefully when a member closes or is manually retiled"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; text: root.service.tr("breakRuntimeGroups", "Break active group"); subtitle: root.service.tr("breakRuntimeGroupsHint", "Use the list above to remove a saved group; live Split View remains compositor-owned"); usable: false }

              SectionHeader { width: parent.width; title: root.service.tr("floatingWindows", "Floating Windows"); subtitle: root.service.tr("floatingWindowsHint", "Real Hyprland floating windows; no fake freeform container") }
              ActionButton { width: parent.width; text: root.service.tr("floatingEnabled", "Floating mode"); checked: root.service.cfg("multitasking.floating.enabled", true); onClicked: root.toggle("multitasking.floating.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); ActionButton { compact: true; text: root.service.tr("miniWindow", "Mini window"); checked: root.service.cfg("multitasking.floating.miniEnabled", true); onClicked: root.toggle("multitasking.floating.miniEnabled") } ActionButton { compact: true; text: root.service.tr("pictureInPicture", "Picture-in-picture"); checked: root.service.cfg("multitasking.floating.pictureInPicture", true); onClicked: root.toggle("multitasking.floating.pictureInPicture") } ActionButton { compact: true; text: root.service.tr("keepAbove", "Keep above"); checked: root.service.cfg("multitasking.floating.keepAbove", true); onClicked: root.toggle("multitasking.floating.keepAbove") } }
              Flow { width: parent.width; spacing: tokens.space(6); ActionButton { compact: true; text: root.service.tr("edgeSnap", "Edge snap"); checked: root.service.cfg("multitasking.floating.edgeSnap", true); onClicked: root.toggle("multitasking.floating.edgeSnap") } ActionButton { compact: true; text: root.service.tr("rememberPosition", "Remember position"); checked: root.service.cfg("multitasking.floating.rememberPosition", true); onClicked: root.toggle("multitasking.floating.rememberPosition") } ActionButton { compact: true; text: root.service.tr("resizeHandle", "Resize handle"); checked: root.service.cfg("multitasking.floating.resizeHandle", true); onClicked: root.toggle("multitasking.floating.resizeHandle") } }
              ActionButton { width: parent.width; text: root.service.tr("windowThrow", "Window throw"); subtitle: root.service.tr("windowThrowHint", "Experimental and disabled by default"); checked: root.service.cfg("multitasking.experimentalWindowThrow", false); onClicked: root.toggle("multitasking.experimentalWindowThrow") }

              SectionHeader { width: parent.width; title: root.service.tr("gestures", "Gestures"); subtitle: root.service.tr("gestureCoordinatorHint", "One coordinator owns edge gestures; drawing apps and fullscreen policies can opt out") }
              Text { width: parent.width; text: "← edge → " + root.service.tr("snapAssist", "Snap Assist") + "   ·   ↑ bottom → " + root.service.tr("overview", "Overview") + "   ·   3 fingers ↔ " + root.service.tr("workspace", "Workspace") + "   ·   top-right → " + root.service.tr("quickSettings", "Quick settings"); color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; text: root.service.tr("gestureCoordinator", "Gesture coordinator"); subtitle: root.service.tr("gestureCoordinatorStatus", "Touchscreen gesture ownership is explicit and event-driven"); checked: root.service.cfg("multitasking.gestures.enabled", true); onClicked: root.toggle("multitasking.gestures.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: [{ key: "workspaceSwipe", label: "Workspace swipe" }, { key: "overviewSwipe", label: "Overview swipe" }, { key: "dockReveal", label: "Dock reveal" }, { key: "quickSettings", label: "Quick settings" }]; delegate: ActionButton { required property var modelData; compact: true; text: root.service.tr(modelData.key, modelData.label); checked: root.service.cfg("multitasking.gestures." + modelData.key, true); onClicked: root.toggle("multitasking.gestures." + modelData.key) } } }
              ActionButton { width: parent.width; text: root.service.tr("touchscreenOnly", "Touchscreen gestures only"); subtitle: root.service.tr("touchscreenOnlyHint", "Touchpad settings remain separate"); checked: root.service.cfg("multitasking.gestures.touchscreenOnly", true); onClicked: root.toggle("multitasking.gestures.touchscreenOnly") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["suppress-in-fullscreen", "allow-in-fullscreen"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "suppress-in-fullscreen" ? root.service.tr("suppressFullscreen", "Suppress in fullscreen") : root.service.tr("allowFullscreen", "Allow in fullscreen"); checked: root.service.cfg("multitasking.gestures.conflictPolicy", "suppress-in-fullscreen") === modelData; onClicked: root.service.setConfig("multitasking.gestures.conflictPolicy", modelData) } } }

              SectionHeader { width: parent.width; title: root.service.tr("workspaceNavigation", "Workspace Navigation"); subtitle: root.service.tr("workspaceNavigationHint", "Uses the existing Hyprland workspace model") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["swipe", "buttons", "keyboard"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("multitasking.workspaceNavigation.mode", "swipe") === modelData; onClicked: root.service.setConfig("multitasking.workspaceNavigation.mode", modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("workspaceOverlay", "Workspace switcher overlay"); checked: root.service.cfg("multitasking.workspaceNavigation.showOverlay", true); onClicked: root.toggle("multitasking.workspaceNavigation.showOverlay") }
              ActionButton { width: parent.width; text: root.service.tr("activateEmptyWorkspace", "Activate empty workspace"); checked: root.service.cfg("multitasking.workspaceNavigation.activateEmpty", true); onClicked: root.toggle("multitasking.workspaceNavigation.activateEmpty") }

              SectionHeader { width: parent.width; title: root.service.tr("multiMonitor", "Multi-monitor"); subtitle: root.service.tr("multiMonitorHint", "Zones and recovery are calculated per output") }
              ActionButton { width: parent.width; text: root.service.tr("multiMonitorEnabled", "Multi-monitor layouts"); checked: root.service.cfg("multitasking.multiMonitor.enabled", true); onClicked: root.toggle("multitasking.multiMonitor.enabled") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["active", "original", "ask"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "active" ? root.service.tr("activeMonitor", "Active monitor") : modelData === "original" ? root.service.tr("originalMonitor", "Original monitor") : root.service.tr("ask", "Ask"); checked: root.service.cfg("multitasking.monitorPolicy", "active") === modelData; onClicked: root.setPairMonitorPolicy(modelData) } } }
              ActionButton { width: parent.width; text: root.service.tr("hotplugRecovery", "Recover on monitor disconnect"); subtitle: root.service.monitors.length + " monitor(s) detected"; checked: root.service.cfg("multitasking.multiMonitor.hotplugRecovery", true); onClicked: root.toggle("multitasking.multiMonitor.hotplugRecovery") }

              SectionHeader { width: parent.width; title: root.service.tr("sessionRestore", "Session Restore"); subtitle: root.service.tr("sessionRestoreHint", "Only Omanome-managed group metadata is considered") }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["off", "ask", "automatic"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "off" ? root.service.tr("off", "Off") : modelData === "ask" ? root.service.tr("ask", "Ask") : root.service.tr("automatic", "Automatic"); checked: root.service.cfg("multitasking.sessionRestore", "ask") === modelData; onClicked: root.service.setConfig("multitasking.sessionRestore", modelData) } } }
              Text { width: parent.width; text: root.service.windowGroupRestoreSummary ? root.service.windowGroupRestoreSummary().policy + " · " + root.service.windowGroupRestoreSummary().reason : root.service.tr("restoreNotPrepared", "Restore plan is not prepared"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; text: root.service.tr("restoreSafety", "Restore safety"); subtitle: root.service.tr("restoreSafetyHint", "Off and Ask never launch applications without an explicit user action"); checked: root.service.cfg("multitasking.sessionRestore", "ask") !== "automatic"; usable: false }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "effects" || root.category === "blur" || root.category === "animations" || root.category === "performance" || root.category === "battery"
              ActionButton { width: parent.width; visible: root.category === "effects"; text: root.service.tr("advancedEffects", "Advanced compositor effects"); subtitle: root.service.cfg("effects.enabled", true) ? root.service.tr("nativeWhenAvailable", "Native backends when available") : root.service.tr("effectsDisabled", "Effects bypassed"); checked: root.service.cfg("effects.enabled", true); onClicked: root.toggle("effects.enabled") }
              ActionButton { width: parent.width; visible: root.category === "effects"; text: root.service.tr("wobbly", "Wobbly windows"); subtitle: root.service.statusObject().wobbly.reason; checked: root.service.statusObject().wobbly.enabled; usable: root.service.statusObject().wobbly.available; onClicked: root.toggle("wobbly.enabled") }
              ActionButton { width: parent.width; visible: root.category === "blur"; text: root.service.tr("blur", "Blur surfaces"); subtitle: root.service.statusObject().effects.blur ? root.service.tr("hyprlandBlur", "Hyprland layer-rule blur") : root.service.tr("backendUnavailable", "Backend unavailable"); checked: root.service.cfg("blur.enabled", true); usable: root.service.statusObject().effects.blur; onClicked: root.toggle("blur.enabled") }
              Text { width: parent.width; visible: root.category === "blur"; text: root.service.tr("previewState", "Live previews") + ": " + (root.service.statusObject().preview.available ? root.service.tr("available", "available") : root.service.statusObject().preview.reason); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Flow { width: parent.width; visible: root.category === "animations"; spacing: tokens.space(6); Repeater { model: ["GNOME", "Smooth", "Snappy", "Minimal", "Disabled"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("animations.preset", "GNOME") === modelData; onClicked: root.service.setConfig("animations.preset", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "animations"; text: root.service.tr("reduceMotion", "Reduced motion"); checked: root.service.cfg("accessibility.reducedMotion", false) || root.service.cfg("general.reduceMotion", false); onClicked: root.toggle("accessibility.reducedMotion") }
              Text { width: parent.width; visible: root.category === "performance" || root.category === "battery"; text: root.service.tr("activePerformanceMode", "Active performance mode") + ": " + String(root.service.performanceState.mode || "balanced") + " · " + root.service.tr("previewStreams", "preview streams") + ": " + String(root.service.performanceState.previewStreams || 0) + " · " + root.service.tr("blurPasses", "blur passes") + ": " + String(root.service.performanceState.blurPasses || 0); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Flow { width: parent.width; visible: root.category === "performance" || root.category === "battery"; spacing: tokens.space(6); Repeater { model: ["automatic", "quality", "balanced", "performance", "battery-saver"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "automatic" ? root.service.tr("automaticMode", "Automatic") : modelData === "quality" ? root.service.tr("qualityMode", "Quality") : modelData === "battery-saver" ? root.service.tr("batterySaverMode", "Battery saver") : modelData === "performance" ? root.service.tr("performanceMode", "Performance") : root.service.tr("balancedMode", "Balanced"); checked: root.service.cfg("performance.mode", "balanced") === modelData; onClicked: root.service.setConfig("performance.mode", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "performance" || root.category === "battery"; text: root.service.tr("adaptiveQuality", "Adaptive quality"); subtitle: root.service.cfg("performance.qualityPreset", "balanced"); checked: root.service.cfg("performance.adaptiveQuality", true); onClicked: root.toggle("performance.adaptiveQuality") }
              ActionButton { width: parent.width; visible: root.category === "performance"; text: root.service.performanceSnapshotRunning ? root.service.tr("running", "Running…") : root.service.tr("refreshPerformanceSnapshot", "Refresh owner-only metrics"); subtitle: root.service.tr("refreshPerformanceSnapshotHint", "One bounded sample; foreign processes are excluded"); usable: !root.service.performanceSnapshotRunning; onClicked: root.service.requestPerformanceSnapshot() }
              Text { width: parent.width; visible: root.category === "performance"; text: root.service.performanceSnapshot.ownerCpuPercent !== undefined ? "Omanome CPU: " + Number(root.service.performanceSnapshot.ownerCpuPercent).toFixed(3) + "% · System CPU: " + Number(root.service.performanceSnapshot.systemCpuPercent || 0).toFixed(3) + "% · Processes: " + String(root.service.performanceSnapshot.processCount || 0) : root.service.tr("performanceSnapshotNotMeasured", "Owner-only CPU is not sampled until you refresh metrics."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Text { width: parent.width; visible: root.category === "performance" && root.service.performanceSnapshotOutput !== ""; text: root.service.performanceSnapshotOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere; maximumLineCount: 10; elide: Text.ElideRight }
              ActionButton { width: parent.width; visible: root.category === "battery"; text: root.service.tr("disableOnBattery", "Reduce effects on battery"); checked: root.service.cfg("effects.disableOnBattery", true); onClicked: root.toggle("effects.disableOnBattery") }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "rotation" || root.category === "displays"
              ActionButton { width: parent.width; visible: root.category === "rotation"; text: root.service.tr("rotation", "Rotation"); subtitle: root.service.systemState.rotationAvailable ? root.service.cfg("rotation.orientation", "auto") : root.service.tr("rotationUnavailable", "Automatic rotation unavailable: no sensor backend detected"); checked: root.service.cfg("rotation.enabled", true); usable: root.service.systemState.rotationAvailable; onClicked: root.toggle("rotation.enabled") }
              ActionButton { width: parent.width; visible: root.category === "rotation"; text: root.service.tr("rotationLock", "Rotation lock"); checked: root.service.cfg("rotation.lock", false); usable: root.service.systemState.rotationAvailable; onClicked: root.toggle("rotation.lock") }
              Flow { width: parent.width; visible: root.category === "rotation"; spacing: tokens.space(6); Repeater { model: ["auto", "landscape", "portrait", "landscape-flipped", "portrait-flipped"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("rotation.orientation", "auto") === modelData; usable: root.service.systemState.rotationAvailable && (modelData !== "auto" || root.service.systemState.rotationSensorAvailable); onClicked: root.service.setRotationOrientation(modelData) } } }
              Text { width: parent.width; visible: root.category === "displays"; text: root.service.monitors.length + " monitor(s) · " + root.service.responsiveState.logicalWidth + "×" + root.service.responsiveState.logicalHeight + " @ " + root.service.responsiveState.scale; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Repeater { visible: root.category === "displays"; model: root.service.monitors; delegate: Text { required property var modelData; width: parent.width; text: String(modelData.name || modelData.description || "Display") + " · " + String(modelData.width || "?") + "×" + String(modelData.height || "?") + " · scale " + String(modelData.scale || 1); color: Color.foreground; font.pixelSize: Style.font.body } }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "privacy" || root.category === "applications" || root.category === "shortcuts" || root.category === "updates" || root.category === "altTab"
              ActionButton { width: parent.width; visible: root.category === "privacy"; text: root.service.tr("clipboardPrivacy", "Clipboard privacy"); subtitle: root.service.tr("neverLogs", "Typed text and clipboard contents are never logged"); checked: root.service.cfg("privacy.neverLogClipboard", true); usable: false }
              ActionButton { width: parent.width; visible: root.category === "privacy"; text: root.service.tr("updateChecks", "Update checks"); checked: root.service.cfg("privacy.updateChecks", true); onClicked: root.toggle("privacy.updateChecks") }
              ActionButton { width: parent.width; visible: root.category === "applications"; text: root.service.tr("applicationRules", "Application rules"); subtitle: root.service.cfg("applicationRules.rules", []).length + " rule(s) · native client matching"; checked: root.service.cfg("applicationRules.enabled", true); onClicked: root.toggle("applicationRules.enabled") }
              ActionButton { width: parent.width; visible: root.category === "shortcuts"; text: root.service.tr("overviewShortcut", "Overview"); subtitle: root.service.cfg("shortcuts.overview", "SUPER") + " · Omanome namespace only"; usable: false }
              ActionButton { width: parent.width; visible: root.category === "shortcuts"; text: root.service.tr("launcherShortcut", "Launcher"); subtitle: root.service.cfg("shortcuts.launcher", "SUPER+SPACE"); usable: false }
              SectionHeader { width: parent.width; visible: root.category === "shortcuts"; title: root.service.tr("multitaskingShortcuts", "Multitasking shortcuts"); subtitle: root.service.tr("multitaskingShortcutsHint", "User-owned Hyprland bindings; Omanome never installs them silently") }
              Repeater {
                visible: root.category === "shortcuts"
                model: root.service && typeof root.service.multitaskingShortcutEntries === "function" ? root.service.multitaskingShortcutEntries() : []
                delegate: RowLayout {
                  required property var modelData
                  width: parent.width
                  spacing: tokens.space(8)
                  Text { Layout.fillWidth: true; text: root.service.tr(modelData.labelKey, modelData.key); color: Color.foreground; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                  Rectangle {
                    Layout.preferredWidth: Math.min(tokens.space(230), parent.width * 0.42)
                    Layout.preferredHeight: tokens.target(42)
                    radius: tokens.radius(10)
                    color: Util.alpha(Color.foreground, 0.08)
                    border.width: shortcutInput.activeFocus ? 1 : 0
                    border.color: Color.accent
                    TextInput {
                      id: shortcutInput
                      anchors.fill: parent
                      anchors.leftMargin: tokens.space(10)
                      anchors.rightMargin: tokens.space(10)
                      verticalAlignment: Text.AlignVCenter
                      color: Color.foreground
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                      text: root.service.cfg("multitasking.shortcuts." + modelData.key, modelData.binding)
                      selectByMouse: true
                      clip: true
                      onEditingFinished: root.service.setConfig("multitasking.shortcuts." + modelData.key, text.trim())
                      onAccepted: root.service.setConfig("multitasking.shortcuts." + modelData.key, text.trim())
                    }
                  }
                }
              }
              Text { width: parent.width; visible: root.category === "shortcuts"; text: root.service.tr("shortcutBindingNote", "Set these values in your Hyprland config if desired; existing bindings are never replaced"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; visible: root.category === "shortcuts"; text: root.service.shortcutConflictRunning ? root.service.tr("running", "Running…") : root.service.tr("shortcutConflictCheck", "Check Hyprland conflicts"); subtitle: root.service.shortcutConflictText(); usable: !root.service.shortcutConflictRunning; onClicked: root.service.checkShortcutConflicts() }
              ActionButton { width: parent.width; visible: root.category === "updates"; text: root.service.updateRunning ? root.service.tr("running", "Running…") : root.service.tr("checkUpdates", "Check"); subtitle: root.service.tr("manualUpdates", "Updates are never installed automatically"); usable: !root.service.updateRunning; onClicked: root.service.runUpdateCheck() }
              ActionButton { width: parent.width; visible: root.category === "updates"; text: root.service.tr("previewUpdate", "Preview update"); subtitle: root.service.tr("previewUpdateHint", "Dry-run only; no files are changed"); usable: !root.service.updateRunning; onClicked: root.service.runUpdatePreview() }
              Text { width: parent.width; visible: root.category === "updates"; text: root.service.tr("updateHint", "Use explicit CLI actions for channel-aware update, rollback and recovery."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Text { width: parent.width; visible: root.category === "updates" && root.service.updateOutput !== ""; text: root.service.updateOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
              ActionButton { width: parent.width; visible: root.category === "backup"; text: root.service.backupRunning ? root.service.tr("running", "Running…") : root.service.tr("exportBackup", "Export config backup"); subtitle: root.service.tr("exportBackupHint", "Versioned JSON; nothing is uploaded"); usable: !root.service.backupRunning; onClicked: root.service.runBackup() }
              ActionButton { width: parent.width; visible: root.category === "backup" && root.service.backupOutput !== ""; text: root.service.tr("copyBackup", "Copy backup"); subtitle: root.service.tr("copyBackupHint", "Copy the explicit export to the local clipboard"); onClicked: root.service.copyPlainText(root.service.backupOutput) }
              Text { width: parent.width; visible: root.category === "backup" && root.service.backupOutput !== ""; text: root.service.backupOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere; maximumLineCount: 12; elide: Text.ElideRight }
              ActionButton { width: parent.width; visible: root.category === "recovery"; text: root.service.rollbackRunning ? root.service.tr("running", "Running…") : root.service.tr("listRollback", "List rollback points"); subtitle: root.service.tr("listRollbackHint", "Inspect snapshots without restoring anything"); usable: !root.service.rollbackRunning; onClicked: root.service.runRollbackList() }
              ActionButton { width: parent.width; visible: root.category === "recovery"; text: root.service.recoveryRunning ? root.service.tr("running", "Running…") : root.service.tr("recoverUpdate", "Recover interrupted update"); subtitle: root.service.tr("recoverUpdateHint", "Restores the journaled snapshot when safe"); usable: !root.service.recoveryRunning; onClicked: root.service.runRecovery() }
              Text { width: parent.width; visible: root.category === "recovery" && root.service.rollbackOutput !== ""; text: root.service.rollbackOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere; maximumLineCount: 12; elide: Text.ElideRight }
              Text { width: parent.width; visible: root.category === "recovery" && root.service.recoveryOutput !== ""; text: root.service.recoveryOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
              ActionButton { width: parent.width; visible: root.category === "altTab"; text: root.service.tr("altTab", "Alt-Tab"); subtitle: root.service.cfg("altTab.style", "coverflow") + " · " + root.service.cfg("altTab.scope", "current-workspace"); checked: true; usable: false }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "accessibility"
              SectionHeader { width: parent.width; title: root.service.tr("accessibility", "Accessibility"); subtitle: root.service.tr("accessibilityHint", "These settings affect Omanome surfaces only") }
              Text { width: parent.width; text: root.service.tr("accessibilityPrecedence", "Accessibility minimum") + ": " + root.service.componentPolicy.touchTargetSize + " px · " + root.service.tr("accessibilityWins", "profile density can never reduce this target"); color: Color.accent; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["default", "large", "extra-large"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("accessibility.touchTargetSize", "default") === modelData; onClicked: root.service.setConfig("accessibility.touchTargetSize", modelData) } } }
              Text { text: root.service.tr("textScale", "Text scale") + ": " + Math.round(Number(root.service.cfg("accessibility.textScale", 1)) * 100) + "%"; color: Color.foreground; font.pixelSize: Style.font.body }
              Slider { width: parent.width; from: 0.9; to: 1.5; stepSize: 0.05; value: root.service.cfg("accessibility.textScale", 1); onMoved: root.service.setConfig("accessibility.textScale", Math.round(value * 20) / 20) }
              ActionButton { width: parent.width; text: root.service.tr("highContrast", "High contrast"); subtitle: root.service.tr("highContrastHint", "Stronger surfaces and focus boundaries"); checked: root.service.cfg("accessibility.highContrast", false); onClicked: root.toggle("accessibility.highContrast") }
              ActionButton { width: parent.width; text: root.service.tr("reducedMotion", "Reduced motion"); subtitle: root.service.tr("reducedMotionHint", "Overview, Dock, Launcher and notifications use short transitions"); checked: root.service.cfg("accessibility.reducedMotion", false); onClicked: root.toggle("accessibility.reducedMotion") }
              ActionButton { width: parent.width; text: root.service.tr("reduceTransparency", "Reduce transparency"); subtitle: root.service.tr("reduceTransparencyHint", "Opaque fallback surfaces; no fake blur"); checked: root.service.cfg("accessibility.reduceTransparency", false); onClicked: root.toggle("accessibility.reduceTransparency") }
              ActionButton { width: parent.width; text: root.service.tr("screenReaderHints", "Screen-reader hints"); checked: root.service.cfg("accessibility.screenReaderHints", true); onClicked: root.toggle("accessibility.screenReaderHints") }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "diagnostics"
              SectionHeader { width: parent.width; title: root.service.tr("diagnostics", "Diagnostics"); subtitle: root.service.tr("diagnosticsHint", "Capability metadata only; personal content is excluded") }
              Text { width: parent.width; text: root.service.diagnosticsText(); color: Color.muted; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
              Row { spacing: tokens.space(8); ActionButton { compact: true; text: root.service.tr("copyDiagnostics", "Copy diagnostics"); onClicked: root.service.copyDiagnostics() } ActionButton { compact: true; text: root.service.doctorRunning ? root.service.tr("running", "Running…") : root.service.tr("runDoctor", "Run doctor"); usable: !root.service.doctorRunning; onClicked: root.service.runDoctor() } }
              ActionButton { width: parent.width; text: root.service.supportBundleRunning ? root.service.tr("running", "Running…") : root.service.tr("supportBundle", "Create support bundle"); subtitle: root.service.tr("supportBundleHint", "Redacted archive; personal config values are excluded"); usable: !root.service.supportBundleRunning; onClicked: root.service.runSupportBundle() }
              Text { width: parent.width; visible: root.service.supportBundleOutput !== ""; text: root.service.supportBundleOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
              Text { width: parent.width; visible: root.service.doctorOutput !== ""; text: root.service.doctorOutput; color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: root.category === "about"
              Text { text: "Omanome " + (root.service.manifest ? root.service.manifest.version : "unknown"); color: Color.accent; font.pixelSize: Style.font.title; font.bold: true }
              Text { width: parent.width; text: root.service.tr("aboutDescription", "A tablet-first desktop experience inside the existing Omarchy/Hyprland shell. The standard bar and other plugins remain untouched."); color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
              Text { width: parent.width; text: "Hyprland " + (root.service.effectBackend.runtime ? root.service.effectBackend.runtime.version : (root.service.hyprlandAvailable ? "available" : "unavailable")) + " · Quickshell " + root.service.statusObject().quickshell + " · " + root.service.responsiveState.breakpoint + " · " + root.service.responsiveState.orientation; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { width: parent.width; text: root.service.tr("exportConfig", "Export config"); subtitle: root.service.tr("exportConfigHint", "Copy the versioned config JSON to the clipboard"); onClicked: root.service.copyPlainText(JSON.stringify(root.service.config, null, 2)) }
              ActionButton { width: parent.width; text: root.service.tr("resetCategory", "Reset this category"); subtitle: root.category; onClicked: root.resetCategory() }
              ActionButton { width: parent.width; text: root.service.tr("resetAll", "Reset all Omanome settings"); subtitle: root.service.tr("resetAllHint", "Only Omanome config is changed"); onClicked: root.service.resetConfig() }
            }

            Column {
              width: parent.width
              spacing: tokens.space(8)
              visible: ["general", "adaptiveMode", "appearance", "tabletMode", "touch", "gestures", "stylus", "stylusButtons", "palmRejection", "handwriting", "keyboard", "suggestions", "windowControls", "dock", "overview", "launcher", "multitasking", "workspaces", "quickSettings", "notifications", "clipboard", "altTab", "blur", "effects", "rotation", "displays", "animations", "performance", "battery", "privacy", "accessibility", "applications", "shortcuts", "updates", "backup", "recovery", "diagnostics", "about"].indexOf(root.category) < 0
              Text { width: parent.width; text: root.service.tr("unavailable", "Unavailable"); color: Color.muted; font.pixelSize: Style.font.body }
              Text { width: parent.width; text: root.categoryDescription(); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
            }
          }
        }
      }
    }
  }
}
