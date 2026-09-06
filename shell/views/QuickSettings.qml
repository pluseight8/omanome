import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"

Item {
  id: root
  property var service: null
  property var panel: null

  function tiles() {
    return [
      { key: "wifi", label: root.service.tr("wifi", "Wi-Fi"), icon: "⌁" },
      { key: "bluetooth", label: root.service.tr("bluetooth", "Bluetooth"), icon: "ᛒ" },
      { key: "airplane", label: root.service.tr("airplane", "Airplane mode"), icon: "✈" },
      { key: "volume", label: root.service.tr("volume", "Volume"), icon: "◖" },
      { key: "microphone", label: root.service.tr("microphone", "Microphone"), icon: "◉" },
      { key: "nightLight", label: root.service.tr("nightLight", "Night light"), icon: "☼" },
      { key: "dnd", label: root.service.tr("doNotDisturb", "Do not disturb"), icon: "◌" },
      { key: "rotationLock", label: root.service.tr("rotationLock", "Rotation lock"), icon: "⟳" },
      { key: "powerProfile", label: root.service.tr("powerProfile", "Power profile"), icon: "ϟ" }
    ]
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(16)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("quickActions", "Quick actions")
      subtitle: root.service.tr("overviewHint", "Touch-friendly controls that leave the Omarchy bar and other plugins alone.")
    }

    GridLayout {
      Layout.fillWidth: true
      columns: root.width > Style.space(760) ? 4 : 2
      columnSpacing: Style.space(10)
      rowSpacing: Style.space(10)

      Repeater {
        model: root.tiles()
        delegate: ActionButton {
          required property var modelData
          Layout.fillWidth: true
          Layout.minimumHeight: Style.space(64)
          minimumHeight: Style.space(64)
          text: modelData.label
          icon: modelData.icon
          checked: root.service.quickState[modelData.key] === true
          onClicked: {
            root.service.recordInput("touch")
            root.service.quickAction(modelData.key)
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("useTouch", "Touch mode")
        subtitle: root.service.detectedMode
        icon: "✦"
        checked: root.service.detectedMode === "tablet" || root.service.detectedMode === "hybrid"
        onClicked: root.service.setConfig("general.mode", root.service.detectedMode === "desktop" ? "tablet" : "desktop")
      }

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("stylus", "Stylus")
        subtitle: root.service.hasStylus ? root.service.stylusDevices.length + " device(s)" : root.service.tr("disabled", "Not detected")
        icon: "✎"
        checked: root.service.hasStylus
        onClicked: if (root.panel) root.panel.activeView = "settings"
      }

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("showKeyboard", "Show keyboard")
        subtitle: root.service.wtypeAvailable ? root.service.tr("wtype", "Wayland-native") : "wtype unavailable"
        icon: "⌨"
        usable: root.service.wtypeAvailable
        onClicked: if (root.panel) root.panel.activeView = "keyboard"
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text { text: root.service.tr("volume", "Volume"); color: Color.foreground; font.pixelSize: Style.font.caption }
        Slider {
          Layout.fillWidth: true
          from: 0
          to: 1
          value: 0.7
          onMoved: if (root.service) root.service.execute(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", String(Math.round(value * 100)) + "%"])
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text { text: root.service.tr("brightness", "Brightness"); color: Color.foreground; font.pixelSize: Style.font.caption }
        Slider {
          Layout.fillWidth: true
          from: 0
          to: 100
          value: 60
          onMoved: if (root.service) root.service.execute(["brightnessctl", "set", String(Math.round(value)) + "%"])
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("screenshot", "Screenshot")
        icon: "▣"
        onClicked: root.service.quickAction("screenshot")
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("screenRecording", "Screen recording")
        icon: "●"
        checked: root.service.quickState.recording === true
        subtitle: "optional wf-recorder backend"
        onClicked: root.service.quickAction("recording")
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("forceQuit", "Force quit")
        subtitle: "Esc cancels"
        icon: "×"
        onClicked: root.service.quickAction("forceQuit")
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("lock", "Lock")
        icon: "▣"
        onClicked: root.service.quickAction("lock")
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)
      ActionButton { Layout.fillWidth: true; text: root.service.tr("logout", "Log out"); onClicked: root.service.execute(["uwsm", "stop"]) }
      ActionButton { Layout.fillWidth: true; text: root.service.tr("reboot", "Reboot"); onClicked: root.service.execute(["loginctl", "reboot"]) }
      ActionButton { Layout.fillWidth: true; text: root.service.tr("shutdown", "Shut down"); onClicked: root.service.execute(["loginctl", "poweroff"]) }
    }
  }
}
