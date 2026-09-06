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
  property bool capsLocked: false
  property var modifierState: ({ Control: false, Alt: false, Super: false })
  property string language: "en"
  property string inputLayer: "letters"
  property string mode: "standard"
  property bool showModifierRow: true
  property bool showNumberRow: true
  property bool showNavigationRow: true
  property bool showFunctionRow: false
  property bool capsEnabled: true

  function refreshLanguage() {
    var configured = String(root.service.cfg("keyboard.layout", "auto"))
    if (configured === "ru" || configured === "en") root.language = configured
    else root.language = String(Quickshell.env("LANG") || "en").indexOf("ru") === 0 ? "ru" : "en"
    root.mode = String(root.service.cfg("keyboard.mode", "standard"))
    root.showNumberRow = root.service.cfg("keyboard.showNumberRow", true) === true
    root.showModifierRow = root.service.cfg("keyboard.showModifierRow", true) === true
    root.showNavigationRow = root.service.cfg("keyboard.showNavigationRow", true) === true
    root.showFunctionRow = root.service.cfg("keyboard.showFunctionRow", false) === true
    root.capsEnabled = root.service.cfg("keyboard.capsLock", true) === true
  }

  function rows() {
    var source = root.inputLayer === "numeric" ? Osk.rows("numeric", false) : (root.inputLayer === "function" ? Osk.rows("function", false) : Osk.rows(root.language, root.showNumberRow))
    if (root.capsEnabled || root.inputLayer === "numeric") return source
    var filtered = []
    for (var i = 0; i < source.length; i++) filtered.push(source[i].filter(function(key) { return key !== "Caps" }))
    return filtered
  }

  function modifierKeys() {
    return ["Control", "Alt", "Super", "Tab", "Esc", "Fn"]
  }

  function isModifier(key) {
    return ["Control", "Alt", "Super"].indexOf(String(key || "")) >= 0
  }

  function activeModifiers() {
    var result = []
    if (root.shifted) result.push("shift")
    if (root.modifierState.Control) result.push("ctrl")
    if (root.modifierState.Alt) result.push("alt")
    if (root.modifierState.Super) result.push("logo")
    return result
  }

  function clearOneShotModifiers() {
    root.modifierState = ({ Control: false, Alt: false, Super: false })
  }

  function press(key) {
    root.service.recordInput("touch")
    if (key === "Shift") { root.shifted = !root.shifted; return }
    if (key === "Caps") {
      root.service.sendKey("Caps", false)
      root.capsLocked = !root.capsLocked
      return
    }
    if (key === "Fn") {
      root.inputLayer = root.inputLayer === "function" ? "letters" : "function"
      root.clearOneShotModifiers()
      root.shifted = false
      return
    }
    if (isModifier(key)) {
      var next = {}
      for (var modifier in root.modifierState) next[modifier] = root.modifierState[modifier]
      next[key] = !Boolean(next[key])
      root.modifierState = next
      return
    }
    if (key === "123") { root.inputLayer = "numeric"; root.shifted = false; root.clearOneShotModifiers(); return }
    if (key === "ABC") { root.inputLayer = "letters"; root.shifted = false; root.clearOneShotModifiers(); return }
    var modifiers = root.activeModifiers()
    if (modifiers.length > 0) root.service.sendModifiedKey(key, modifiers)
    else if (key === "Space") root.service.sendKey("Space", false)
    else if (key === "Backspace" || key === "Enter" || key === "Tab" || key === "Esc") root.service.sendKey(key, false)
    else root.service.sendKey(key, root.shifted)
    root.clearOneShotModifiers()
    root.shifted = false
    if (root.inputLayer === "function") root.inputLayer = "letters"
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

    ColumnLayout {
      id: keyRows
      Layout.fillHeight: true
      width: root.mode === "floating" ? parent.width * 0.82 : ((root.mode === "one-handed" || root.mode === "thumb") ? parent.width * 0.64 : parent.width)
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.space(7)
      visible: root.mode !== "handwriting"

      Flow {
        width: keyRows.width
        height: root.showModifierRow ? Style.space(58) : 0
        visible: root.showModifierRow
        spacing: Style.space(6)

        Repeater {
          model: root.modifierKeys()
          delegate: ActionButton {
            required property string modelData
            height: Style.space(54)
            minimumHeight: Style.space(54)
            minimumWidth: modelData === "Control" || modelData === "Super" ? Style.space(90) : Style.space(68)
            text: modelData === "Control" ? "Ctrl" : modelData
            checked: (root.isModifier(modelData) && root.modifierState[modelData] === true) || modelData === "Fn" && root.inputLayer === "function"
            onClicked: root.press(modelData)
          }
        }
      }

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
              text: modelData === "Backspace" ? "⌫" : (modelData === "Enter" ? "↵" : (modelData === "Caps" ? "⇪" : (root.shifted && modelData.length === 1 ? modelData.toUpperCase() : modelData)))
              checked: (modelData === "Shift" && root.shifted) || (modelData === "Caps" && root.capsLocked)
              onClicked: root.press(modelData)
            }
          }
        }
      }
    }
  }
}
