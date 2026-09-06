import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../models/Stylus.js" as StylusModel

Item {
  id: root
  property var service: null
  property var panel: null
  property string category: "general"
  property var categories: [
    { key: "general", label: "general" }, { key: "appearance", label: "appearance" }, { key: "tabletMode", label: "tabletMode" }, { key: "touch", label: "touch" }, { key: "stylus", label: "stylus" }, { key: "windowControls", label: "windowControls" }, { key: "gestures", label: "gestures" }, { key: "dock", label: "dock" }, { key: "overview", label: "overview" }, { key: "launcher", label: "launcher" }, { key: "keyboard", label: "keyboard" }, { key: "clipboard", label: "clipboard" }, { key: "notifications", label: "notifications" }, { key: "altTab", label: "altTab" }, { key: "blur", label: "blur" }, { key: "effects", label: "effects" }, { key: "rotation", label: "rotation" }, { key: "privacy", label: "privacy" }, { key: "shortcuts", label: "shortcuts" }, { key: "updates", label: "updates" }, { key: "compatibility", label: "compatibility" }, { key: "about", label: "about" }
  ]

  function label(item) { return root.service.tr(item.label, item.label) }
  function toggle(path) { root.service.setConfig(path, !Boolean(root.service.cfg(path, false))) }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.space(18)
    spacing: Style.space(18)

    ListView {
      id: side
      Layout.preferredWidth: Style.space(190)
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(4)
      model: root.categories
      delegate: ActionButton {
        required property var modelData
        width: side.width
        height: Style.space(42)
        minimumHeight: Style.space(42)
        compact: true
        text: root.label(modelData)
        checked: root.category === modelData.key
        onClicked: root.category = modelData.key
      }
    }

    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Util.alpha(Color.foreground, 0.12) }

    Flickable {
      id: content
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: width
      contentHeight: body.implicitHeight

      Column {
        id: body
        width: content.width
        spacing: Style.space(14)

        SectionHeader { width: parent.width; title: root.label({ label: root.category }); subtitle: "Omanome · " + root.category }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "general"
          ActionButton { width: parent.width; text: root.service.tr("mode", "Mode"); subtitle: root.service.detectedMode; checked: true; onClicked: root.service.setConfig("general.mode", root.service.detectedMode === "desktop" ? "tablet" : "desktop") }
          Row { spacing: Style.space(8); Repeater { model: ["automatic", "desktop", "tablet", "hybrid"]; delegate: ActionButton { required property string modelData; compact: true; text: root.service.tr(modelData, modelData); checked: root.service.cfg("general.mode", "automatic") === modelData; onClicked: root.service.setConfig("general.mode", modelData) } } }
          Row { spacing: Style.space(8); Repeater { model: ["Desktop", "Tablet", "Stylus", "Performance", "Battery Saver", "GNOME-like"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("general.profile", "Desktop") === modelData; onClicked: root.service.applyProfile(modelData) } } }
          Row { spacing: Style.space(8); ActionButton { compact: true; text: "System"; checked: root.service.cfg("general.language", "system") === "system"; onClicked: root.service.setConfig("general.language", "system") } ActionButton { compact: true; text: "English"; checked: root.service.cfg("general.language", "system") === "en"; onClicked: root.service.setConfig("general.language", "en") } ActionButton { compact: true; text: "Русский"; checked: root.service.cfg("general.language", "system") === "ru"; onClicked: root.service.setConfig("general.language", "ru") } }
          ActionButton { width: parent.width; text: "Large UI"; subtitle: "Larger touch targets and typography"; checked: root.service.cfg("general.largeUi", false); onClicked: root.toggle("general.largeUi") }
          ActionButton { width: parent.width; text: "Reduce motion"; subtitle: "Disable non-essential animation"; checked: root.service.cfg("general.reduceMotion", false); onClicked: root.toggle("general.reduceMotion") }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "appearance"
          ActionButton { width: parent.width; text: "Theme"; subtitle: root.service.cfg("appearance.theme", "follow-omarchy"); checked: true; onClicked: root.service.setConfig("appearance.theme", root.service.cfg("appearance.theme", "follow-omarchy") === "follow-omarchy" ? "dark" : "follow-omarchy") }
          ActionButton { width: parent.width; text: "Large UI"; subtitle: "Shared typography and touch-target preference"; checked: root.service.cfg("general.largeUi", false); onClicked: root.toggle("general.largeUi") }
          Text { text: "Surface radius: " + root.service.cfg("appearance.radius", 18) + " logical px"; color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { width: parent.width; from: 8; to: 32; value: root.service.cfg("appearance.radius", 18); onMoved: root.service.setConfig("appearance.radius", Math.round(value)) }
          Text { text: "Surface opacity: " + Math.round(root.service.cfg("appearance.opacity", 0.96) * 100) + "%"; color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { width: parent.width; from: 0.65; to: 1; value: root.service.cfg("appearance.opacity", 0.96); onMoved: root.service.setConfig("appearance.opacity", Math.round(value * 100) / 100) }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "windowControls"
          ActionButton { width: parent.width; text: root.service.tr("windowControls", "Window controls"); subtitle: root.service.cfg("windowControls.show", "tablet"); checked: root.service.cfg("windowControls.enabled", true); onClicked: root.toggle("windowControls.enabled") }
          ActionButton { width: parent.width; text: "Visibility"; subtitle: root.service.cfg("windowControls.show", "tablet"); onClicked: root.service.setConfig("windowControls.show", root.service.cfg("windowControls.show", "tablet") === "tablet" ? "always" : "tablet") }
          Text { text: "Opacity: " + Math.round(root.service.cfg("windowControls.opacity", 0.94) * 100) + "%"; color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { width: parent.width; from: 0.45; to: 1; value: root.service.cfg("windowControls.opacity", 0.94); onMoved: root.service.setConfig("windowControls.opacity", Math.round(value * 100) / 100) }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "dock"
          ActionButton { width: parent.width; text: root.service.tr("dock", "Dock"); subtitle: root.service.cfg("dock.position", "bottom"); checked: root.service.cfg("dock.enabled", true); onClicked: root.toggle("dock.enabled") }
          ActionButton { width: parent.width; text: "Position"; subtitle: root.service.cfg("dock.position", "bottom"); onClicked: { var p = root.service.cfg("dock.position", "bottom"); root.service.setConfig("dock.position", p === "bottom" ? "left" : (p === "left" ? "right" : "bottom")) } }
          ActionButton { width: parent.width; text: "Autohide"; checked: root.service.cfg("dock.autohide", true); onClicked: root.toggle("dock.autohide") }
          Text { text: "Icon size: " + root.service.cfg("dock.iconSize", 48) + " logical px"; color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { width: parent.width; from: 32; to: 72; value: root.service.cfg("dock.iconSize", 48); onMoved: root.service.setConfig("dock.iconSize", Math.round(value)) }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "overview" || root.category === "launcher" || root.category === "altTab"
          ActionButton { width: parent.width; text: "Module"; subtitle: root.category; checked: root.service.cfg(root.category + ".enabled", true); onClicked: root.toggle(root.category + ".enabled") }
          ActionButton { width: parent.width; text: "Visual style"; subtitle: root.service.cfg(root.category + ".style", root.category === "altTab" ? "coverflow" : "gnome"); onClicked: root.service.setConfig(root.category + ".style", root.service.cfg(root.category + ".style", root.category === "altTab" ? "coverflow" : "gnome") === "gnome" ? "grid" : "gnome") }
          ActionButton { width: parent.width; text: "Show all workspaces"; visible: root.category === "overview"; checked: root.service.cfg("overview.showAllWorkspaces", true); onClicked: root.toggle("overview.showAllWorkspaces") }
          Text { visible: root.category === "launcher"; text: "Grid columns: " + root.service.cfg("launcher.gridColumns", 6); color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { visible: root.category === "launcher"; width: parent.width; from: 3; to: 10; value: root.service.cfg("launcher.gridColumns", 6); onMoved: root.service.setConfig("launcher.gridColumns", Math.round(value)) }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "notifications"
          ActionButton { width: parent.width; text: root.service.tr("notifications", "Notifications"); subtitle: "Native Omarchy notification service"; checked: root.service.cfg("notifications.enabled", true); onClicked: root.toggle("notifications.enabled") }
          ActionButton { width: parent.width; text: "Group by app"; checked: root.service.cfg("notifications.groupByApp", true); onClicked: root.toggle("notifications.groupByApp") }
          ActionButton { width: parent.width; text: root.service.tr("doNotDisturb", "Do not disturb"); checked: root.service.cfg("notifications.doNotDisturb", false); onClicked: root.toggle("notifications.doNotDisturb") }
          Text { width: parent.width; text: "The notification center reuses Omarchy's native service; no second notification daemon is started."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "rotation" || root.category === "updates" || root.category === "shortcuts"
          ActionButton { width: parent.width; text: root.service.tr(root.category, root.category); subtitle: root.category === "rotation" ? (root.service.systemState.rotationAvailable ? root.service.cfg("rotation.orientation", "auto") : "Hyprland transform backend unavailable") : (root.category === "updates" ? root.service.cfg("updates.channel", "stable") : "user-owned Hyprland bindings"); checked: root.service.cfg(root.category + ".enabled", true); usable: root.category !== "shortcuts" && (root.category !== "rotation" || root.service.systemState.rotationAvailable); onClicked: { if (root.category === "rotation") root.toggle("rotation.enabled"); else if (root.category === "updates") root.service.setConfig("updates.channel", root.service.cfg("updates.channel", "stable") === "stable" ? "beta" : "stable") } }
          ActionButton { width: parent.width; text: "Rotation lock"; visible: root.category === "rotation"; checked: root.service.cfg("rotation.lock", false); usable: root.service.systemState.rotationAvailable; onClicked: root.toggle("rotation.lock") }
          Row { visible: root.category === "rotation"; spacing: Style.space(8); Repeater { model: ["auto", "landscape", "portrait", "landscape-flipped", "portrait-flipped"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("rotation.orientation", "auto") === modelData; usable: root.service.systemState.rotationAvailable && (modelData !== "auto" || root.service.systemState.rotationSensorAvailable); onClicked: root.service.setRotationOrientation(modelData) } } }
          Text { width: parent.width; visible: root.category === "rotation"; text: root.service.systemState.rotationSensorAvailable ? "Auto rotation uses monitor-sensor (iio-sensor-proxy)." : "Auto rotation unavailable: install iio-sensor-proxy/monitor-sensor; manual Hyprland transforms remain available."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          ActionButton { width: parent.width; text: "Automatic install"; visible: root.category === "updates"; checked: root.service.cfg("updates.automaticInstall", false); onClicked: root.toggle("updates.automaticInstall") }
          Text { width: parent.width; visible: root.category === "shortcuts"; text: "Omanome exposes namespaced shell commands and never overwrites existing keybindings. Assign the commands shown in README to your own Hyprland config."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "tabletMode" || root.category === "touch" || root.category === "gestures"
          ActionButton { width: parent.width; text: root.service.tr("touchscreen", "Touchscreen"); subtitle: root.service.hasTouchscreen ? root.service.tr("detectedDevices", "Detected") : root.service.tr("disabled", "Not detected"); checked: root.service.hasTouchscreen; usable: root.service.hasTouchscreen; onClicked: root.service.setConfig("tabletMode.enabled", !root.service.cfg("tabletMode.enabled", true)) }
          ActionButton { width: parent.width; text: "Automatic adaptation"; subtitle: "Touch and stylus input changes target sizing"; checked: root.service.cfg("tabletMode.autoFromTouch", true); onClicked: root.toggle("tabletMode.autoFromTouch") }
          Text { text: "Touch target: " + root.service.cfg("tabletMode.touchTarget", 48) + " logical px"; color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { width: parent.width; from: 40; to: 72; value: root.service.cfg("tabletMode.touchTarget", 48); onMoved: root.service.setConfig("tabletMode.touchTarget", Math.round(value)) }
          ActionButton { width: parent.width; text: "Three-finger action"; subtitle: root.service.cfg("touch.threeFingerAction", "workspace"); onClicked: root.service.setConfig("touch.threeFingerAction", root.service.cfg("touch.threeFingerAction", "workspace") === "workspace" ? "overview" : "workspace") }
          ActionButton { width: parent.width; text: "Four-finger action"; subtitle: root.service.cfg("touch.fourFingerAction", "overview"); onClicked: root.service.setConfig("touch.fourFingerAction", root.service.cfg("touch.fourFingerAction", "overview") === "overview" ? "launcher" : "overview") }
          ActionButton { width: parent.width; text: "Invert workspace swipe"; checked: root.service.cfg("touch.invert", false); onClicked: root.toggle("touch.invert") }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "stylus"
          ActionButton { width: parent.width; text: root.service.tr("stylus", "Stylus"); subtitle: root.service.hasStylus ? root.service.stylusDevices.length + " device(s)" : root.service.tr("disabled", "Not detected"); checked: root.service.cfg("stylus.enabled", true); onClicked: root.toggle("stylus.enabled") }
          ActionButton { width: parent.width; text: root.service.tr("palmRejection", "Palm rejection"); subtitle: "Native libinput policy · custom filter unavailable"; checked: root.service.cfg("stylus.palmRejection", "automatic") !== "off"; usable: false }
          ActionButton { width: parent.width; text: root.service.tr("annotation", "Annotation"); subtitle: root.service.cfg("stylus.annotation", true) ? "Overlay available from Quick Settings" : "Disabled"; checked: root.service.cfg("stylus.annotation", true); onClicked: root.toggle("stylus.annotation") }
          Text { text: root.service.tr("pressure", "Pressure") + ": " + root.service.cfg("stylus.pressureMin", 0) + " – " + root.service.cfg("stylus.pressureMax", 1) + " · " + root.service.cfg("stylus.pressureCurve", "linear"); color: Color.foreground; font.pixelSize: Style.font.body }
          Text { width: parent.width; text: "Pressure/tilt/rotation/proximity/eraser/barrel capabilities are passed through to native Wayland tablet clients; Omanome does not synthesize mouse events."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: root.service.tr("detectedDevices", "Detected devices") + ": " + (root.service.stylusDevices.map(function(device) { var info = StylusModel.capabilities(device); return String(device.name || "stylus") + " [" + Object.keys(info).filter(function(key) { return info[key] === true }).join(", ") + "]" }).join(", ") || "none"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "Button mapping is shown for the generic device contract. A portable libinput button-event hook is not exposed by the current Omarchy public API, so mappings remain unavailable until an input companion is installed."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Repeater { model: ["primary", "secondary", "tertiary", "eraser"]; delegate: ActionButton { required property string modelData; width: parent.width; text: modelData; subtitle: String(root.service.cfg("stylus.buttonMap." + modelData, "right-click")); usable: false } }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "keyboard"
          ActionButton { width: parent.width; text: root.service.tr("keyboard", "Keyboard"); subtitle: root.service.wtypeAvailable ? root.service.tr("wlroots", "Wayland-native") : "wtype unavailable"; checked: root.service.cfg("keyboard.enabled", true); onClicked: root.toggle("keyboard.enabled") }
          ActionButton { width: parent.width; text: "Auto-show on editable fields"; subtitle: "Requires a compositor text-input focus provider"; checked: root.service.cfg("keyboard.autoShow", true); onClicked: root.toggle("keyboard.autoShow") }
          ActionButton { width: parent.width; text: "Suggestions and learning"; subtitle: "Local engine slot; learning is off by default"; checked: root.service.cfg("keyboard.learning", false); onClicked: root.toggle("keyboard.learning") }
          Row { spacing: Style.space(8); Repeater { model: ["standard", "floating", "split", "thumb", "one-handed", "handwriting"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("keyboard.mode", "standard") === modelData; onClicked: root.service.setConfig("keyboard.mode", modelData) } } }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "clipboard" || root.category === "privacy"
          ActionButton { width: parent.width; text: root.service.tr("clipboard", "Clipboard"); subtitle: root.service.clipboardHistory.length + " entries · never logged"; checked: root.service.cfg("clipboard.enabled", true); onClicked: root.toggle("clipboard.enabled") }
          ActionButton { width: parent.width; text: root.service.tr("privateMode", "Private mode"); subtitle: "Stop capture and keep existing history"; checked: root.service.cfg("privacy.clipboardPrivate", false); onClicked: root.toggle("privacy.clipboardPrivate") }
          ActionButton { width: parent.width; text: "Persist pinned only"; subtitle: "Requires pinning UI in a future history backend"; checked: root.service.cfg("clipboard.persistPinnedOnly", false); onClicked: root.toggle("clipboard.persistPinnedOnly") }
          ActionButton { width: parent.width; text: "Clear clipboard history"; onClicked: root.service.clearClipboard() }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "effects" || root.category === "blur"
          ActionButton { width: parent.width; text: "Blur surfaces"; subtitle: "GPU compositor blur is optional per surface"; checked: root.service.cfg("blur.enabled", true); onClicked: root.toggle("blur.enabled") }
          ActionButton { width: parent.width; text: "Wobbly windows"; subtitle: root.service.tr("effectsUnavailable", "Optional compositor effects are disabled until a compatible companion is installed."); checked: false; usable: false }
          ActionButton { width: parent.width; text: "Desktop cube"; subtitle: root.service.tr("effectsUnavailable", "Optional compositor effects are disabled until a compatible companion is installed."); checked: false; usable: false }
          ActionButton { width: parent.width; text: "Reduce effects on battery"; checked: root.service.cfg("effects.disableOnBattery", true); onClicked: root.toggle("effects.disableOnBattery") }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "compatibility"
          ActionButton { width: parent.width; text: root.service.tr("standardBar", "Standard Omarchy bar is preserved"); subtitle: "Omanome declares no replacement 'bar' kind"; checked: true; usable: false }
          ActionButton { width: parent.width; text: "Namespaced IPC"; subtitle: "io.omanome.shell · no shared singleton names"; checked: true; usable: false }
          ActionButton { width: parent.width; text: "Safe fallback"; subtitle: "Disable Omanome with omarchy plugin disable io.omanome.shell"; checked: true; usable: false }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "about"
          Text { text: "Omanome 0.2.0"; color: Color.accent; font.pixelSize: Style.font.title; font.bold: true }
          Text { width: parent.width; text: "GNOME-inspired touch and stylus experience inside the existing Omarchy/Hyprland shell. It stays a single Omarchy plugin and never replaces the standard bar."; color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "Detected: Hyprland " + (root.service.hyprlandAvailable ? "yes" : "no") + " · touchscreen " + (root.service.hasTouchscreen ? "yes" : "no") + " · stylus " + (root.service.hasStylus ? "yes" : "no") + " · wtype " + (root.service.wtypeAvailable ? "yes" : "no"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          ActionButton { width: parent.width; text: root.service.tr("reset", "Reset"); subtitle: "Reset Omanome config only"; onClicked: root.service.resetConfig() }
        }
      }
    }
  }
}
