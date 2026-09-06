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
  function hasStylusButtons() {
    var devices = root.service && Array.isArray(root.service.stylusDevices) ? root.service.stylusDevices : []
    for (var i = 0; i < devices.length; i++) {
      if (StylusModel.capabilities(devices[i]).buttons > 0) return true
    }
    return false
  }

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
          ActionButton { width: parent.width; text: "Large UI"; subtitle: "Requires a host-wide Style token API; touch target size is available below"; checked: root.service.cfg("general.largeUi", false); usable: false }
          ActionButton { width: parent.width; text: "Reduce motion"; subtitle: "Requires a host-wide animation policy API"; checked: root.service.cfg("general.reduceMotion", false); usable: false }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "appearance"
          ActionButton { width: parent.width; text: "Theme"; subtitle: "Follows Omarchy Color tokens; independent plugin theme backend unavailable"; checked: root.service.cfg("appearance.theme", "follow-omarchy") === "follow-omarchy"; usable: false }
          ActionButton { width: parent.width; text: "Large UI"; subtitle: "Requires a host-wide Style token API; touch target size is available in Tablet mode"; checked: root.service.cfg("general.largeUi", false); usable: false }
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
          ActionButton { width: parent.width; text: "Module"; subtitle: "View lifecycle is owned by the single Omanome panel"; checked: root.service.cfg(root.category + ".enabled", true); usable: false }
          ActionButton { width: parent.width; text: "Visual style"; subtitle: "The current native layout has no alternate style backend"; checked: false; usable: false }
          ActionButton { width: parent.width; text: "Show all workspaces"; visible: root.category === "overview"; checked: root.service.cfg("overview.showAllWorkspaces", true); onClicked: root.toggle("overview.showAllWorkspaces") }
          Text { visible: root.category === "launcher"; text: "Grid columns: " + root.service.cfg("launcher.gridColumns", 6); color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { visible: root.category === "launcher"; width: parent.width; from: 3; to: 10; value: root.service.cfg("launcher.gridColumns", 6); onMoved: root.service.setConfig("launcher.gridColumns", Math.round(value)) }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "notifications"
          ActionButton { width: parent.width; text: root.service.tr("notifications", "Notifications"); subtitle: root.service.cfg("notifications.enabled", true) ? "Native Omarchy notification service" : "Disabled"; checked: root.service.cfg("notifications.enabled", true); onClicked: root.toggle("notifications.enabled") }
          ActionButton { width: parent.width; text: "Group by app"; subtitle: "Grouping is owned by Omarchy's native notification service"; checked: root.service.cfg("notifications.groupByApp", true); usable: false }
          ActionButton { width: parent.width; text: root.service.tr("doNotDisturb", "Do not disturb"); subtitle: root.service.systemState.dndAvailable ? "Omarchy notification service" : "Notification backend unavailable"; checked: root.service.systemState.dnd === true; usable: root.service.systemState.dndAvailable === true; onClicked: root.service.setDoNotDisturb(!root.service.systemState.dnd) }
          Text { width: parent.width; text: "The notification center reuses Omarchy's native service; no second notification daemon is started."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "rotation" || root.category === "updates" || root.category === "shortcuts"
          ActionButton { width: parent.width; text: root.service.tr(root.category, root.category); subtitle: root.category === "rotation" ? (root.service.systemState.rotationAvailable ? root.service.cfg("rotation.orientation", "auto") : "Hyprland transform backend unavailable") : (root.category === "updates" ? "Updates are managed by the Omarchy plugin manager" : "user-owned Hyprland bindings"); checked: root.service.cfg(root.category + ".enabled", true); usable: root.category === "rotation" ? root.service.systemState.rotationAvailable : false; onClicked: if (root.category === "rotation") root.toggle("rotation.enabled") }
          ActionButton { width: parent.width; text: "Rotation lock"; visible: root.category === "rotation"; checked: root.service.cfg("rotation.lock", false); usable: root.service.systemState.rotationAvailable; onClicked: root.toggle("rotation.lock") }
          Row { visible: root.category === "rotation"; spacing: Style.space(8); Repeater { model: ["auto", "landscape", "portrait", "landscape-flipped", "portrait-flipped"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData; checked: root.service.cfg("rotation.orientation", "auto") === modelData; usable: root.service.systemState.rotationAvailable && (modelData !== "auto" || root.service.systemState.rotationSensorAvailable); onClicked: root.service.setRotationOrientation(modelData) } } }
          Text { width: parent.width; visible: root.category === "rotation"; text: root.service.systemState.rotationSensorAvailable ? "Auto rotation backend: " + String(root.service.systemState.rotationSensorBackend || "unknown") + (root.service.systemState.rotationDbusAvailable ? " · D-Bus available" : "") : "Auto rotation unavailable: install iio-sensor-proxy/monitor-sensor; manual Hyprland transforms remain available."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; visible: root.category === "rotation"; text: "Dynamic target: " + (root.service.statusObject().rotation.targets.join(", ") || "focused monitor fallback") + " · touch/tablet transforms are applied in the same batch."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          ActionButton { width: parent.width; text: "Automatic install"; visible: root.category === "updates"; subtitle: "The official Omarchy updater requires an explicit user command"; checked: root.service.cfg("updates.automaticInstall", false); usable: false }
          Text { width: parent.width; visible: root.category === "shortcuts"; text: "Omanome exposes namespaced shell commands and never overwrites existing keybindings. Assign the commands shown in README to your own Hyprland config."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "tabletMode" || root.category === "touch" || root.category === "gestures"
          ActionButton { width: parent.width; text: root.service.tr("touchscreen", "Touchscreen"); subtitle: root.service.hasTouchscreen ? root.service.tr("detectedDevices", "Detected") : root.service.tr("disabled", "Not detected"); checked: root.service.hasTouchscreen && root.service.cfg("tabletMode.enabled", true); usable: root.service.hasTouchscreen; onClicked: root.service.setConfig("tabletMode.enabled", !root.service.cfg("tabletMode.enabled", true)) }
          ActionButton { width: parent.width; text: "Automatic adaptation"; subtitle: "Touch/stylus mode switching follows real device input"; checked: root.service.cfg("tabletMode.autoFromTouch", true); onClicked: root.toggle("tabletMode.autoFromTouch") }
          Text { text: "Touch target: " + root.service.cfg("tabletMode.touchTarget", 48) + " logical px · host Style token unavailable"; color: Color.muted; font.pixelSize: Style.font.caption }
          Slider { width: parent.width; from: 40; to: 72; value: root.service.cfg("tabletMode.touchTarget", 48); enabled: false }
          ActionButton { width: parent.width; text: "Three-finger action"; subtitle: "Requires a gesture-event API; Hyprland swipe settings are supported below"; checked: false; usable: false }
          ActionButton { width: parent.width; text: "Four-finger action"; subtitle: "Requires a gesture-event API; Hyprland swipe settings are supported below"; checked: false; usable: false }
          ActionButton { width: parent.width; text: "Invert workspace swipe"; checked: root.service.cfg("touch.invert", false); onClicked: root.toggle("touch.invert") }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "stylus"
          ActionButton { width: parent.width; text: root.service.tr("stylus", "Stylus"); subtitle: root.service.hasStylus ? root.service.stylusDevices.length + " device(s) · automatic mode " + (root.service.cfg("stylus.enabled", true) ? "enabled" : "disabled") : root.service.tr("disabled", "Not detected"); checked: root.service.cfg("stylus.enabled", true); usable: root.service.hasStylus; onClicked: root.toggle("stylus.enabled") }
          ActionButton { width: parent.width; text: root.service.tr("palmRejection", "Palm rejection"); subtitle: "Native libinput policy · custom filter unavailable"; checked: root.service.cfg("stylus.palmRejection", "automatic") !== "off"; usable: false }
          ActionButton { width: parent.width; text: root.service.tr("annotation", "Annotation"); subtitle: root.service.cfg("stylus.annotation", true) ? "Overlay available from Quick Settings" : "Disabled"; checked: root.service.cfg("stylus.annotation", true); onClicked: root.toggle("stylus.annotation") }
          Text { text: root.service.tr("pressure", "Pressure") + ": " + root.service.cfg("stylus.pressureMin", 0) + " – " + root.service.cfg("stylus.pressureMax", 1) + " · " + root.service.cfg("stylus.pressureCurve", "linear"); color: Color.foreground; font.pixelSize: Style.font.body }
          Text { width: parent.width; text: "Pressure/tilt/rotation/proximity/eraser/barrel capabilities are passed through to native Wayland tablet clients; Omanome does not synthesize mouse events."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: root.service.tr("detectedDevices", "Detected devices") + ": " + (root.service.stylusDevices.length || 0); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Repeater {
            model: root.service.stylusDevices
            delegate: Column {
              id: deviceCard
              required property var modelData
              width: parent.width
              property var info: StylusModel.diagnostics(modelData, "hyprland")
              spacing: Style.space(3)
              Text { width: parent.width; text: deviceCard.info.name + " · " + deviceCard.info.type + " · " + deviceCard.info.backend + " · output " + deviceCard.info.mappedOutput; color: Color.foreground; font.pixelSize: Style.font.body; elide: Text.ElideRight }
              Text { width: parent.width; text: "pressure " + (deviceCard.info.pressure ? "yes" : "no") + " · tilt X/Y " + (deviceCard.info.tiltX ? "yes" : "no") + "/" + (deviceCard.info.tiltY ? "yes" : "no") + " · rotation " + (deviceCard.info.rotation ? "yes" : "no") + " · distance " + (deviceCard.info.distance ? "yes" : "no") + " · proximity " + (deviceCard.info.proximity ? "yes" : "no") + " · eraser " + (deviceCard.info.eraser ? "yes" : "no") + " · buttons " + deviceCard.info.buttons; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
            }
          }
          Text { width: parent.width; text: "Button mapping is shown for the generic device contract. A portable libinput button-event hook is not exposed by the current Omarchy public API, so mappings remain unavailable until an input companion is installed."; color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Repeater { visible: root.hasStylusButtons(); model: ["primary", "secondary", "tertiary", "eraser"]; delegate: ActionButton { required property string modelData; width: parent.width; text: modelData; subtitle: String(root.service.cfg("stylus.buttonMap." + modelData, "right-click")); usable: false } }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "keyboard"
          ActionButton { width: parent.width; text: root.service.tr("keyboard", "Keyboard"); subtitle: root.service.wtypeAvailable ? root.service.tr("wlroots", "Wayland-native") : "wtype unavailable"; checked: root.service.cfg("keyboard.enabled", true); onClicked: root.toggle("keyboard.enabled") }
          ActionButton { width: parent.width; text: "Auto-show on editable fields"; subtitle: root.service.inputBackendAvailable ? "Optional input-method backend" : "Requires optional input-method companion"; checked: root.service.cfg("keyboard.autoShow", true); usable: root.service.inputBackendAvailable; onClicked: root.toggle("keyboard.autoShow") }
          ActionButton { width: parent.width; text: "Suggestions and learning"; subtitle: "Requires a local input-method engine; no engine is bundled"; checked: root.service.cfg("keyboard.learning", false); usable: false }
          ActionButton { width: parent.width; text: "Toolbar"; checked: root.service.cfg("keyboard.toolbar", true); onClicked: root.toggle("keyboard.toolbar") }
          ActionButton { width: parent.width; text: "Key popup"; checked: root.service.cfg("keyboard.keyPopup", true); onClicked: root.toggle("keyboard.keyPopup") }
          ActionButton { width: parent.width; text: "Long-press alternates"; checked: root.service.cfg("keyboard.longPress", true); onClicked: root.toggle("keyboard.longPress") }
          ActionButton { width: parent.width; text: "Space cursor mode"; subtitle: root.service.inputBackendAvailable ? "Persistent input backend available" : "Requires optional persistent input backend"; checked: root.service.cfg("keyboard.spaceCursor", true); usable: root.service.inputBackendAvailable; onClicked: root.toggle("keyboard.spaceCursor") }
          Text { text: "Keyboard height: " + root.service.cfg("keyboard.height", 300) + " logical px"; color: Color.foreground; font.pixelSize: Style.font.body }
          Slider { width: parent.width; from: 220; to: 520; value: root.service.cfg("keyboard.height", 300); onMoved: root.service.setConfig("keyboard.height", Math.round(value)) }
          ActionButton { width: parent.width; text: "Number row"; checked: root.service.cfg("keyboard.showNumberRow", true); onClicked: root.toggle("keyboard.showNumberRow") }
          ActionButton { width: parent.width; text: "Modifier row"; checked: root.service.cfg("keyboard.showModifierRow", true); onClicked: root.toggle("keyboard.showModifierRow") }
          ActionButton { width: parent.width; text: "Navigation keys"; checked: root.service.cfg("keyboard.showNavigationRow", true); onClicked: root.toggle("keyboard.showNavigationRow") }
          ActionButton { width: parent.width; text: "Function layer"; checked: root.service.cfg("keyboard.showFunctionRow", false); onClicked: root.toggle("keyboard.showFunctionRow") }
          ActionButton { width: parent.width; text: "Caps Lock key"; checked: root.service.cfg("keyboard.capsLock", true); onClicked: root.toggle("keyboard.capsLock") }
          Row { spacing: Style.space(8); Repeater { model: ["standard", "floating", "split", "thumb", "one-handed-left", "one-handed-right", "handwriting"]; delegate: ActionButton { required property string modelData; compact: true; text: modelData.replace("one-handed-", ""); checked: root.service.cfg("keyboard.mode", "standard") === modelData; onClicked: root.service.setConfig("keyboard.mode", modelData) } } }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "clipboard" || root.category === "privacy"
          ActionButton { width: parent.width; text: root.service.tr("clipboard", "Clipboard"); subtitle: root.service.clipboardHistory.length + " entries · never logged"; checked: root.service.cfg("clipboard.enabled", true); onClicked: root.toggle("clipboard.enabled") }
          ActionButton { width: parent.width; text: root.service.tr("privateMode", "Private mode"); subtitle: "Stop capture and keep existing history"; checked: root.service.cfg("privacy.clipboardPrivate", false); onClicked: root.toggle("privacy.clipboardPrivate") }
          ActionButton { width: parent.width; text: "Persist pinned only"; subtitle: "Requires pinning UI in a future history backend"; checked: root.service.cfg("clipboard.persistPinnedOnly", false); usable: false }
          ActionButton { width: parent.width; text: "Clear clipboard history"; onClicked: root.service.clearClipboard() }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.category === "effects" || root.category === "blur"
          ActionButton { width: parent.width; text: "Blur surfaces"; subtitle: "Requires a version-pinned compositor blur companion; solid surfaces remain available"; checked: root.service.cfg("blur.enabled", true); usable: false }
          ActionButton { width: parent.width; text: "Wobbly windows"; subtitle: root.service.tr("effectsUnavailable", "Optional compositor effects are disabled until a compatible companion is installed."); checked: false; usable: false }
          ActionButton { width: parent.width; text: "Desktop cube"; subtitle: root.service.tr("effectsUnavailable", "Optional compositor effects are disabled until a compatible companion is installed."); checked: false; usable: false }
          ActionButton { width: parent.width; text: "Reduce effects on battery"; subtitle: "Requires a compositor effects backend"; checked: root.service.cfg("effects.disableOnBattery", true); usable: false }
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
          Text { text: "Omanome 0.3.0"; color: Color.accent; font.pixelSize: Style.font.title; font.bold: true }
          Text { width: parent.width; text: "GNOME-inspired touch and stylus experience inside the existing Omarchy/Hyprland shell. It stays a single Omarchy plugin and never replaces the standard bar."; color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "Detected: Hyprland " + (root.service.hyprlandAvailable ? "yes" : "no") + " · touchscreen " + (root.service.hasTouchscreen ? "yes" : "no") + " · stylus " + (root.service.hasStylus ? "yes" : "no") + " · wtype " + (root.service.wtypeAvailable ? "yes" : "no"); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          ActionButton { width: parent.width; text: root.service.tr("reset", "Reset"); subtitle: "Reset Omanome config only"; onClicked: root.service.resetConfig() }
        }
      }
    }
  }
}
