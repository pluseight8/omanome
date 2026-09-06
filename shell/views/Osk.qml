import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "../components"
import "../models/Osk.js" as Osk

Item {
  id: root
  property var service: null
  property var panel: null
  property bool shifted: false
  property string language: "en"
  property string layer: "letters"
  property string mode: "standard"

  function refreshLanguage() {
    var configured = String(root.service.cfg("keyboard.layout", "auto"))
    if (configured === "ru" || configured === "en") root.language = configured
    else root.language = String(Quickshell.env("LANG") || "en").indexOf("ru") === 0 ? "ru" : "en"
    root.mode = String(root.service.cfg("keyboard.mode", "standard"))
  }

  function rows() {
    if (root.layer === "numeric") return Osk.rows("numeric", true)
    return Osk.rows(root.language, true)
  }

  function press(key) {
    root.service.recordInput("touch")
    if (key === "Shift") { root.shifted = !root.shifted; return }
    if (key === "123") { root.layer = "numeric"; root.shifted = false; return }
    if (key === "ABC") { root.layer = "letters"; root.shifted = false; return }
    if (key === "Space") { root.service.sendKey("Space", false); root.shifted = false; return }
    if (key === "Backspace" || key === "Enter") { root.service.sendKey(key, false); root.shifted = false; return }
    root.service.sendKey(key, root.shifted)
    root.shifted = false
  }

  Component.onCompleted: root.refreshLanguage()

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        text: root.service.tr("keyboard", "Keyboard")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      ActionButton { compact: true; text: "EN"; checked: root.language === "en"; onClicked: { root.language = "en"; root.service.setConfig("keyboard.layout", "en") } }
      ActionButton { compact: true; text: "RU"; checked: root.language === "ru"; onClicked: { root.language = "ru"; root.service.setConfig("keyboard.layout", "ru") } }
      Item { Layout.fillWidth: true }
      ActionButton { compact: true; text: "Standard"; checked: root.mode === "standard"; onClicked: { root.mode = "standard"; root.service.setConfig("keyboard.mode", "standard") } }
      ActionButton { compact: true; text: "Floating"; checked: root.mode === "floating"; onClicked: { root.mode = "floating"; root.service.setConfig("keyboard.mode", "floating") } }
      ActionButton { compact: true; text: "Split"; checked: root.mode === "split"; onClicked: { root.mode = "split"; root.service.setConfig("keyboard.mode", "split") } }
      ActionButton { compact: true; text: "✎"; checked: root.mode === "handwriting"; onClicked: { root.mode = "handwriting"; root.service.setConfig("keyboard.mode", "handwriting") } }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(38)
      radius: Style.space(10)
      color: Util.alpha(Color.foreground, 0.06)
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        Text { text: root.mode === "handwriting" ? "Handwriting panel" : "suggestions  ·  clipboard  ·  emoji  ·  edit  ·  voice"; color: Color.muted; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
        Text { text: root.service.wtypeAvailable ? "Wayland" : "backend missing"; color: root.service.wtypeAvailable ? Color.accent : Color.urgent; font.pixelSize: Style.font.caption }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.mode === "handwriting"

      Surface {
        anchors.fill: parent
        surfaceColor: Util.alpha(Color.background, 0.48)
        Text {
          anchors.centerIn: parent
          text: "✎  Write with a stylus\n\nLocal recognition backend: pluggable\nNo cloud upload is performed by Omanome."
          color: Color.muted
          horizontalAlignment: Text.AlignHCenter
          font.pixelSize: Style.font.body
        }
      }
    }

    Column {
      id: keyRows
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.space(7)
      visible: root.mode !== "handwriting"

      Repeater {
        model: root.rows()
        delegate: Flow {
          required property var modelData
          width: keyRows.width
          height: Style.space(58)
          spacing: Style.space(6)

          Repeater {
            model: modelData
            delegate: ActionButton {
              required property string modelData
              height: Style.space(54)
              minimumHeight: Style.space(54)
              minimumWidth: modelData === "Space" ? Math.max(Style.space(190), keyRows.width * 0.28) : (modelData.length > 6 ? Style.space(112) : Style.space(52))
              text: modelData === "Backspace" ? "⌫" : (modelData === "Enter" ? "↵" : modelData)
              checked: modelData === "Shift" && root.shifted
              onClicked: root.press(modelData)
            }
          }
        }
      }
    }
  }
}
