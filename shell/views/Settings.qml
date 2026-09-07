import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../models/Config.js" as Config
import "../models/Stylus.js" as StylusModel

Item {
  id: root

  property var service: null
  property var panel: null
  property string category: "general"
  property string query: ""
  property bool mobileDetails: false
  property var categories: [
    { key: "general", fallback: "General", description: "Mode, language and profiles", aliases: ["общие", "режим", "язык"] },
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
    var key = root.category === "stylusButtons" || root.category === "palmRejection" || root.category === "handwriting" || root.category === "suggestions" ? "stylus" : root.category
    var defaults = Config.get(Config.defaults(), key, null)
    if (defaults !== null) root.service.setConfig(key, defaults)
  }

  function toggle(path) { root.service.setConfig(path, !Boolean(root.service.cfg(path, false))) }
  function percent(path, fallback) { return Math.round(Number(root.service.cfg(path, fallback)) * 100) + "%" }
  function categoryDescription() {
    for (var i = 0; i < root.categories.length; i++) if (root.categories[i].key === root.category) return root.categories[i].description
    return ""
  }

  function hasStylusButtons() {
    var devices = root.service && Array.isArray(root.service.stylusDevices) ? root.service.stylusDevices : []
    for (var i = 0; i < devices.length; i++) if (StylusModel.capabilities(devices[i]).buttons > 0) return true
    return false
  }

  Component.onCompleted: if (!root.compactLayout) root.mobileDetails = true

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
          onTextChanged: root.query = text
        }
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
              Flow { width: parent.width; spacing: tokens.space(6); Repeater { model: ["Desktop", "Tablet", "Stylus", "Performance", "Battery Saver", "GNOME-like"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("general.profile", "Desktop") === modelData; onClicked: root.service.applyProfile(modelData) } } }
              Flow { width: parent.width; spacing: tokens.space(6); ActionButton { compact: true; text: "System"; checked: root.service.cfg("general.language", "system") === "system"; onClicked: root.service.setConfig("general.language", "system") } ActionButton { compact: true; text: "English"; checked: root.service.cfg("general.language", "system") === "en"; onClicked: root.service.setConfig("general.language", "en") } ActionButton { compact: true; text: "Русский"; checked: root.service.cfg("general.language", "system") === "ru"; onClicked: root.service.setConfig("general.language", "ru") } }
              ActionButton { width: parent.width; text: root.service.tr("largeUi", "Large UI"); subtitle: root.service.tr("largeUiHint", "Increase touch targets and layout density"); checked: root.service.cfg("general.largeUi", false); onClicked: root.toggle("general.largeUi") }
              ActionButton { width: parent.width; text: root.service.tr("reduceMotion", "Reduce motion"); subtitle: root.service.tr("reduceMotionHint", "Also disables expensive motion-driven effects"); checked: root.service.cfg("general.reduceMotion", false); onClicked: root.toggle("general.reduceMotion") }
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
              ActionButton { width: parent.width; text: root.service.tr("keyboard", "Keyboard"); subtitle: root.service.wtypeAvailable ? root.service.tr("wlroots", "Wayland-native") : root.service.tr("backendUnavailable", "wtype backend unavailable"); checked: root.service.cfg("keyboard.enabled", true); onClicked: root.toggle("keyboard.enabled") }
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
              spacing: tokens.space(8)
              visible: root.category === "effects" || root.category === "blur" || root.category === "animations" || root.category === "performance" || root.category === "battery"
              ActionButton { width: parent.width; visible: root.category === "effects"; text: root.service.tr("advancedEffects", "Advanced compositor effects"); subtitle: root.service.cfg("effects.enabled", true) ? root.service.tr("nativeWhenAvailable", "Native backends when available") : root.service.tr("effectsDisabled", "Effects bypassed"); checked: root.service.cfg("effects.enabled", true); onClicked: root.toggle("effects.enabled") }
              ActionButton { width: parent.width; visible: root.category === "effects"; text: root.service.tr("wobbly", "Wobbly windows"); subtitle: root.service.statusObject().wobbly.reason; checked: root.service.statusObject().wobbly.enabled; usable: root.service.statusObject().wobbly.available; onClicked: root.toggle("wobbly.enabled") }
              ActionButton { width: parent.width; visible: root.category === "blur"; text: root.service.tr("blur", "Blur surfaces"); subtitle: root.service.statusObject().effects.blur ? root.service.tr("hyprlandBlur", "Hyprland layer-rule blur") : root.service.tr("backendUnavailable", "Backend unavailable"); checked: root.service.cfg("blur.enabled", true); usable: root.service.statusObject().effects.blur; onClicked: root.toggle("blur.enabled") }
              Text { width: parent.width; visible: root.category === "blur"; text: root.service.tr("previewState", "Live previews") + ": " + (root.service.statusObject().preview.available ? root.service.tr("available", "available") : root.service.statusObject().preview.reason); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Flow { width: parent.width; visible: root.category === "animations"; spacing: tokens.space(6); Repeater { model: ["GNOME", "Smooth", "Snappy", "Minimal", "Disabled"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("animations.preset", "GNOME") === modelData; onClicked: root.service.setConfig("animations.preset", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "animations"; text: root.service.tr("reduceMotion", "Reduced motion"); checked: root.service.cfg("accessibility.reducedMotion", false) || root.service.cfg("general.reduceMotion", false); onClicked: root.toggle("accessibility.reducedMotion") }
              Text { width: parent.width; visible: root.category === "performance" || root.category === "battery"; text: root.service.tr("activePerformanceMode", "Active performance mode") + ": " + String(root.service.performanceState.mode || "balanced") + " · " + root.service.tr("previewStreams", "preview streams") + ": " + String(root.service.performanceState.previewStreams || 0) + " · " + root.service.tr("blurPasses", "blur passes") + ": " + String(root.service.performanceState.blurPasses || 0); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Flow { width: parent.width; visible: root.category === "performance" || root.category === "battery"; spacing: tokens.space(6); Repeater { model: ["balanced", "performance", "battery-saver"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData === "battery-saver" ? root.service.tr("batterySaverMode", "Battery saver") : modelData === "performance" ? root.service.tr("performanceMode", "Performance") : root.service.tr("balancedMode", "Balanced"); checked: root.service.cfg("performance.mode", "balanced") === modelData; onClicked: root.service.setConfig("performance.mode", modelData) } } }
              ActionButton { width: parent.width; visible: root.category === "performance" || root.category === "battery"; text: root.service.tr("adaptiveQuality", "Adaptive quality"); subtitle: root.service.cfg("performance.qualityPreset", "balanced"); checked: root.service.cfg("performance.adaptiveQuality", true); onClicked: root.toggle("performance.adaptiveQuality") }
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
              ActionButton { width: parent.width; visible: root.category === "shortcuts"; text: root.service.tr("checkConflicts", "Check conflicts"); subtitle: root.service.tr("externalConflictNote", "External Hyprland bindings are shown only when safely available"); usable: false }
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
              visible: ["general", "appearance", "tabletMode", "touch", "gestures", "stylus", "stylusButtons", "palmRejection", "handwriting", "keyboard", "suggestions", "windowControls", "dock", "overview", "launcher", "workspaces", "quickSettings", "notifications", "clipboard", "altTab", "blur", "effects", "rotation", "displays", "animations", "performance", "battery", "privacy", "accessibility", "applications", "shortcuts", "updates", "backup", "recovery", "diagnostics", "about"].indexOf(root.category) < 0
              Text { width: parent.width; text: root.service.tr("unavailable", "Unavailable"); color: Color.muted; font.pixelSize: Style.font.body }
              Text { width: parent.width; text: root.categoryDescription(); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
            }
          }
        }
      }
    }
  }
}
