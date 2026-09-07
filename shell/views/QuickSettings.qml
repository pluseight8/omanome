import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"

Item {
  id: root
  property var service: null
  property var panel: null
  property bool wifiExpanded: false
  property bool bluetoothExpanded: false
  property bool audioExpanded: false
  property string wifiPassword: ""

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  readonly property bool portrait: tokens.orientation === "portrait"
  readonly property int tileColumns: portrait ? 2 : Math.max(2, Math.min(4, Number(root.service && root.service.responsiveState ? root.service.responsiveState.gridColumns : 4)))

  function system() {
    return root.service ? root.service.systemState : {}
  }

  function audioName(kind) {
    var devices = root.service ? root.service.audioDevices : []
    for (var i = 0; i < devices.length; i++) if (devices[i].kind === kind && devices[i].active) return String(devices[i].name)
    return root.service.tr(kind === "sink" ? "notSelected" : "notSelected", "Not selected")
  }

  function usable(key) {
    var state = root.system()
    if (key === "wifi" || key === "airplane") return state.wifiAvailable === true
    if (key === "bluetooth") return state.bluetoothAvailable === true
    if (key === "volume") return state.volumeAvailable === true
    if (key === "microphone") return state.microphoneAvailable === true
    if (key === "nightLight") return state.nightLightAvailable === true
    if (key === "powerProfile") return state.powerProfileAvailable === true
    if (key === "dnd") return state.dndAvailable === true
    if (key === "rotationLock") return state.rotationAvailable === true
    return true
  }

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
    anchors.margins: tokens.space(22)
    spacing: tokens.space(14)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("quickActions", "Quick actions")
      subtitle: root.service.tr("quickSettingsHint", "Live controls use the session backends available on this system.")
    }

    GridLayout {
      Layout.fillWidth: true
      columns: root.tileColumns
      columnSpacing: tokens.space(10)
      rowSpacing: tokens.space(10)

      Repeater {
        model: root.tiles()
        delegate: ActionButton {
          required property var modelData
          Layout.fillWidth: true
          Layout.minimumHeight: tokens.target(64)
          minimumHeight: tokens.target(64)
          text: modelData.label
          icon: modelData.icon
          usable: root.usable(modelData.key)
          checked: modelData.key === "powerProfile"
                    ? root.service.systemState.powerProfile !== "balanced"
                    : root.service.quickState[modelData.key] === true
          subtitle: modelData.key === "powerProfile"
                    ? String(root.service.systemState.powerProfile || "balanced")
                    : (!usable ? root.service.tr("systemUnavailable", "Backend unavailable") : "")
          onClicked: {
            root.service.recordInput("touch")
            root.service.quickAction(modelData.key)
            if (modelData.key === "wifi") root.wifiExpanded = true
            if (modelData.key === "bluetooth") root.bluetoothExpanded = true
          }
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      visible: root.system().rotationAvailable === true
      spacing: Style.space(5)
      Text {
        text: root.service.tr("rotation", "Rotation") + " · " + (root.service.cfg("rotation.lock", false) ? root.service.tr("locked", "Locked") : root.service.orientation)
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Repeater {
          model: ["auto", "landscape", "portrait", "landscape-flipped", "portrait-flipped"]
          delegate: ActionButton {
            required property string modelData
            compact: true
            text: modelData
            checked: root.service.cfg("rotation.orientation", "auto") === modelData
            usable: modelData !== "auto" || root.system().rotationSensorAvailable === true
            subtitle: modelData === "auto" && !usable ? root.service.tr("systemUnavailable", "Backend unavailable") : ""
            onClicked: root.service.setRotationOrientation(modelData)
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("wifiNetworks", "Wi-Fi networks")
        subtitle: root.system().wifiConnected ? String(root.system().wifiSsid || root.service.tr("connected", "Connected")) : root.service.tr("notConnected", "Not connected")
        icon: "⌁"
        usable: root.system().wifiAvailable === true
        checked: root.wifiExpanded
        onClicked: {
          root.wifiExpanded = !root.wifiExpanded
          if (root.wifiExpanded) root.service.scanWifi()
        }
      }

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("bluetoothDevices", "Bluetooth devices")
        subtitle: root.system().bluetoothPowered ? root.service.tr("powered", "Powered") : root.service.tr("off", "Off")
        icon: "ᛒ"
        usable: root.system().bluetoothAvailable === true
        checked: root.bluetoothExpanded
        onClicked: {
          root.bluetoothExpanded = !root.bluetoothExpanded
          if (root.bluetoothExpanded) root.service.scanBluetooth()
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("audioOutput", "Audio output")
        subtitle: root.audioName("sink")
        icon: "◖"
        usable: root.system().volumeAvailable === true
        checked: root.audioExpanded
        onClicked: { root.audioExpanded = !root.audioExpanded; if (root.audioExpanded) root.service.scanAudio() }
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("audioInput", "Microphone input")
        subtitle: root.audioName("source")
        icon: "◉"
        usable: root.system().microphoneAvailable === true
        checked: root.audioExpanded
        onClicked: { root.audioExpanded = !root.audioExpanded; if (root.audioExpanded) root.service.scanAudio() }
      }
    }

    Flow {
      Layout.fillWidth: true
      visible: root.audioExpanded
      spacing: Style.space(6)
      Repeater {
        model: root.service.audioDevices
        delegate: ActionButton {
          required property var modelData
          compact: true
          text: String(modelData.name || modelData.id)
          subtitle: modelData.kind === "sink" ? root.service.tr("audioOutput", "Audio output") : root.service.tr("audioInput", "Microphone input")
          checked: modelData.active === true
          onClicked: root.service.setAudioDefault(modelData.kind, modelData.id)
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      visible: root.wifiExpanded
      spacing: Style.space(6)

      RowLayout {
        Layout.fillWidth: true
        TextField {
          Layout.fillWidth: true
          placeholderText: root.service.tr("wifiPassword", "Password for secured network")
          echoMode: TextInput.Password
          text: root.wifiPassword
          onTextChanged: root.wifiPassword = text
        }
        ActionButton {
          compact: true
          text: root.service.tr("scan", "Scan")
          onClicked: root.service.scanWifi()
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Repeater {
          model: root.service.wifiNetworks
          delegate: ActionButton {
            required property var modelData
            compact: true
            text: String(modelData.ssid || "") + (Number(modelData.signal) >= 0 ? "  " + Number(modelData.signal) + "%" : "")
            subtitle: modelData.active ? root.service.tr("connected", "Connected") : (String(modelData.security || "") !== "" ? "🔒" : "")
            checked: modelData.active === true
            onClicked: root.service.connectWifi(modelData.ssid, root.wifiPassword)
          }
        }
      }

      Text {
        visible: root.service.wifiNetworks.length === 0
        text: root.service.tr("noNetworks", "No networks found")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      visible: root.bluetoothExpanded
      spacing: Style.space(6)

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.service.tr("bluetoothHint", "Select a discovered device to connect or disconnect.")
          color: Color.muted
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        ActionButton {
          compact: true
          text: root.service.tr("scan", "Scan")
          onClicked: root.service.scanBluetooth()
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Repeater {
          model: root.service.bluetoothDevices
          delegate: ActionButton {
            required property var modelData
            compact: true
            text: String(modelData.name || modelData.address)
            subtitle: modelData.connected ? root.service.tr("connected", "Connected") : String(modelData.address || "")
            checked: modelData.connected === true
            onClicked: modelData.connected ? root.service.disconnectBluetooth(modelData.address) : root.service.connectBluetooth(modelData.address)
          }
        }
      }

      Text {
        visible: root.service.bluetoothDevices.length === 0
        text: root.service.tr("noDevices", "No devices found")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text { text: root.service.tr("volume", "Volume") + "  " + Math.round(Number(root.system().volume || 0)) + "%"; color: Color.foreground; font.pixelSize: Style.font.caption }
        Slider {
          Layout.fillWidth: true
          enabled: root.system().volumeAvailable === true
          from: 0
          to: 1.5
          value: Math.max(0, Math.min(1.5, Number(root.system().volume || 0) / 100))
          onMoved: root.service.setVolume(value)
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text { text: root.service.tr("microphone", "Microphone") + "  " + Math.round(Number(root.system().microphoneVolume || 0)) + "%"; color: Color.foreground; font.pixelSize: Style.font.caption }
        Slider {
          Layout.fillWidth: true
          enabled: root.system().microphoneAvailable === true
          from: 0
          to: 1.5
          value: Math.max(0, Math.min(1.5, Number(root.system().microphoneVolume || 0) / 100))
          onMoved: root.service.setMicrophoneVolume(value)
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text { text: root.service.tr("brightness", "Brightness") + "  " + Math.round(Number(root.system().brightness || 0)) + "%"; color: Color.foreground; font.pixelSize: Style.font.caption }
        Slider {
          Layout.fillWidth: true
          enabled: root.system().brightnessAvailable === true
          from: 0
          to: 100
          value: Math.max(0, Math.min(100, Number(root.system().brightness || 0)))
          onMoved: root.service.setBrightness(value)
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
        subtitle: root.service.wtypeAvailable ? root.service.tr("wtype", "Wayland-native") : root.service.tr("systemUnavailable", "Backend unavailable")
        icon: "⌨"
        usable: root.service.wtypeAvailable && root.service.cfg("keyboard.enabled", true) === true
        onClicked: if (root.panel) root.panel.activeView = "keyboard"
      }

      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("annotation", "Annotation")
        subtitle: root.service.tr("annotationHint", "Draw over the current screen")
        icon: "✎"
        usable: root.service.cfg("stylus.annotation", true)
        onClicked: root.service.toggleAnnotation()
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      Surface {
        Layout.fillWidth: true
        implicitHeight: Style.space(58)
        surfaceColor: Color.menu.background
        Column {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          Text { text: root.service.tr("battery", "Battery"); color: Color.foreground; font.pixelSize: Style.font.caption; font.bold: true }
          Text { text: root.system().batteryAvailable ? Math.round(Number(root.system().batteryPercent)) + "% · " + String(root.system().batteryState) : root.service.tr("batteryUnavailable", "Battery backend unavailable"); color: Color.muted; font.pixelSize: Style.font.caption }
        }
      }

      Surface {
        Layout.fillWidth: true
        implicitHeight: Style.space(58)
        surfaceColor: Color.menu.background
        Column {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          Text { text: root.service.tr("powerProfile", "Power profile"); color: Color.foreground; font.pixelSize: Style.font.caption; font.bold: true }
          Text { text: String(root.system().powerProfile || root.service.tr("unavailable", "Unavailable")); color: Color.muted; font.pixelSize: Style.font.caption }
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
        subtitle: root.service.tr("wfRecorder", "wf-recorder backend")
        usable: root.system().recordingAvailable !== false
        onClicked: root.service.quickAction("recording")
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("forceQuit", "Force quit")
        subtitle: root.service.tr("escCancels", "Esc cancels")
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

    Text {
      Layout.fillWidth: true
      visible: root.service.lastError !== ""
      text: root.service.lastError
      color: Color.accent
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
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
