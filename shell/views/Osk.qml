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
  property bool toolbarEnabled: true
  property bool keyPopupEnabled: true
  property bool longPressEnabled: true
  property bool spaceCursorEnabled: true
  property bool spaceCursorMode: false
  property bool modeChooserVisible: false
  property bool toolbarOverflowVisible: false
  property string emojiCategory: "recent"
  property string emojiQuery: ""
  property var popupAlternates: []
  property string popupKey: ""
  property var strokes: []
  property var redoStrokes: []
  property var currentStroke: []
  property string repeatKey: ""
  property real floatingX: 0.5
  property real floatingY: 0.72
  property int lastShiftTap: 0
  property real inkWidth: 4

  function cfg(path, fallback) {
    return root.service ? root.service.cfg(path, fallback) : fallback
  }

  function setCfg(path, value) {
    if (root.service) root.service.setConfig(path, value)
  }

  function refreshLanguage() {
    var configured = String(root.cfg("keyboard.layout", "auto"))
    if (configured === "ru" || configured === "en") root.language = configured
    else root.language = String(Quickshell.env("LANG") || "en").indexOf("ru") === 0 ? "ru" : "en"

    var configuredMode = Osk.normalizeMode(root.cfg("keyboard.mode", "standard"))
    if (["numeric", "symbols", "emoji"].indexOf(configuredMode) >= 0) {
      root.mode = "standard"
      root.inputLayer = configuredMode
    } else {
      root.mode = configuredMode
    }
    root.showNumberRow = root.cfg("keyboard.showNumberRow", true) === true
    root.showModifierRow = root.cfg("keyboard.showModifierRow", true) === true
    root.showNavigationRow = root.cfg("keyboard.showNavigationRow", true) === true
    root.showFunctionRow = root.cfg("keyboard.showFunctionRow", false) === true
    root.capsEnabled = root.cfg("keyboard.capsLock", true) === true
    root.toolbarEnabled = root.cfg("keyboard.toolbar", true) === true
    root.keyPopupEnabled = root.cfg("keyboard.keyPopup", true) === true
    root.longPressEnabled = root.cfg("keyboard.longPress", true) === true
    root.spaceCursorEnabled = root.cfg("keyboard.spaceCursor", true) === true
    root.emojiCategory = String(root.cfg("keyboard.emojiCategory", "recent"))
    root.floatingX = Number(root.cfg("keyboard.floating.x", 0.5))
    root.floatingY = Number(root.cfg("keyboard.floating.y", 0.72))
  }

  Connections {
    target: root.service
    function onConfigUpdated(path) {
      if (String(path || "").indexOf("keyboard.") === 0) root.refreshLanguage()
    }
  }

  function displayLanguage() {
    if (root.inputLayer === "numeric") return "numeric"
    if (root.inputLayer === "symbols") return "symbols"
    if (root.inputLayer === "function") return "function"
    if (root.inputLayer === "editing") return "editing"
    return root.language
  }

  function rows() {
    var source = Osk.rows(root.displayLanguage(), root.showNumberRow)
    if (root.capsEnabled || root.inputLayer !== "letters") return source
    var filtered = []
    for (var i = 0; i < source.length; i++)
      filtered.push(source[i].filter(function(key) { return key !== "Caps" }))
    return filtered
  }

  function splitRows() {
    return Osk.splitRows(root.displayLanguage(), root.showNumberRow)
  }

  function modifierKeys() {
    var keys = ["Control", "Alt", "Super"]
    if (root.showNavigationRow) keys.push("Tab", "Esc", "←", "↑", "↓", "→")
    if (root.showFunctionRow) keys.push("Fn")
    return keys
  }

  function isModifier(key) {
    return ["Control", "Alt", "Super"].indexOf(String(key || "")) >= 0
  }

  function activeModifiers() {
    var result = []
    if (root.shifted || root.capsLocked) result.push("shift")
    if (root.modifierState.Control) result.push("ctrl")
    if (root.modifierState.Alt) result.push("alt")
    if (root.modifierState.Super) result.push("logo")
    return result
  }

  function clearOneShotModifiers() {
    root.modifierState = ({ Control: false, Alt: false, Super: false })
  }

  function setLayer(layer) {
    var next = String(layer || "letters")
    if (["letters", "numeric", "symbols", "function", "editing", "emoji"].indexOf(next) < 0) next = "letters"
    root.inputLayer = next
    root.popupAlternates = []
    root.popupKey = ""
    root.clearOneShotModifiers()
    root.shifted = false
  }

  function setMode(next) {
    var value = Osk.normalizeMode(next)
    if (["numeric", "symbols", "emoji"].indexOf(value) >= 0) {
      root.setLayer(value)
      value = "standard"
    }
    root.mode = value
    root.modeChooserVisible = false
    root.setCfg("keyboard.mode", value)
  }

  function toggleLanguage() {
    root.language = root.language === "ru" ? "en" : "ru"
    root.setCfg("keyboard.layout", root.language)
  }

  function sendEditingAction(key) {
    var shortcuts = {
      SelectAll: "a",
      Copy: "c",
      Cut: "x",
      Paste: "v",
      Undo: "z",
      Redo: "y"
    }
    var value = String(key || "")
    if (shortcuts[value]) return root.service.sendModifiedKey(shortcuts[value], ["ctrl"])
    return false
  }

  function pressShift() {
    if (root.capsLocked) {
      root.capsLocked = false
      root.shifted = false
      root.lastShiftTap = 0
      shiftTapTimer.stop()
      return
    }
    var now = Date.now()
    if (root.lastShiftTap > 0 && now - root.lastShiftTap <= 360) {
      root.capsLocked = true
      root.shifted = false
      root.lastShiftTap = 0
      shiftTapTimer.stop()
      return
    }
    root.shifted = !root.shifted
    root.lastShiftTap = now
    shiftTapTimer.restart()
  }

  function press(key) {
    if (!root.service) return
    root.service.recordInput("touch")
    var value = String(key || "")
    if (value === "Shift") { root.pressShift(); return }
    if (value === "Caps") {
      root.service.sendKey("Caps", false)
      root.capsLocked = !root.capsLocked
      root.shifted = false
      return
    }
    if (value === "Fn") {
      root.setLayer(root.inputLayer === "function" ? "letters" : "function")
      return
    }
    if (isModifier(value)) {
      var next = {}
      for (var modifier in root.modifierState) next[modifier] = root.modifierState[modifier]
      next[value] = !Boolean(next[value])
      root.modifierState = next
      return
    }
    if (value === "123") { root.setLayer("numeric"); return }
    if (value === "ABC") { root.setLayer("letters"); return }
    if (value === "Symbols") { root.setLayer("symbols"); return }
    if (value === "Emoji") { root.setLayer("emoji"); return }
    if (value === "Space" && root.spaceCursorMode) { root.spaceCursorMode = false; return }
    if (Osk.keyAction(value) !== "key") {
      root.sendEditingAction(value)
      root.clearOneShotModifiers()
      root.shifted = false
      return
    }
    var modifiers = root.activeModifiers()
    if (modifiers.length > 0) root.service.sendModifiedKey(value, modifiers)
    else root.service.sendKey(value, root.shifted || root.capsLocked)
    root.clearOneShotModifiers()
    root.shifted = false
    if (root.inputLayer === "function") root.setLayer("letters")
  }

  function keyText(value) {
    var key = String(value || "")
    if (key === "Backspace") return "⌫"
    if (key === "Enter") return "↵"
    if (key === "Caps") return "⇪"
    if (key === "SelectAll") return "All"
    if (key === "Space") return "Space"
    if ((root.shifted || root.capsLocked) && key.length === 1) return key.toUpperCase()
    return key
  }

  function keyWidth(key, available, count) {
    var value = String(key || "")
    if (value === "Space") return Math.max(Style.space(150), available * 0.28)
    if (["Backspace", "SelectAll", "PageUp", "PageDown"].indexOf(value) >= 0) return Style.space(90)
    if (value.length > 6) return Style.space(96)
    return Math.max(Style.space(42), (available - Style.space(6) * Math.max(0, count - 1)) / Math.max(1, count))
  }

  function beginHold(key) {
    var value = String(key || "")
    if (value === "Space" && root.spaceCursorEnabled) {
      root.spaceCursorMode = true
      root.popupAlternates = []
      return
    }
    if (Osk.isRepeatable(value)) {
      root.repeatKey = value
      repeatTimer.interval = Math.max(100, Number(root.cfg("keyboard.repeatDelay", 420)))
      repeatTimer.restart()
      return
    }
    if (!root.longPressEnabled || !Osk.isTextKey(value)) return
    root.popupKey = value
    root.popupAlternates = Osk.alternateKeys(value, root.language)
  }

  function stopHold() {
    repeatTimer.stop()
    root.repeatKey = ""
  }

  function repeatInterval() {
    var configured = Math.max(60, Number(root.cfg("keyboard.repeatRate", 55)))
    if (root.service && root.service.performanceState && root.service.performanceState.mode === "battery-saver") return Math.max(100, configured)
    return configured
  }

  function chooseAlternate(value) {
    root.stopHold()
    root.popupAlternates = []
    root.popupKey = ""
    if (root.service) root.service.typeText(String(value || ""))
  }

  function emojiItems() {
    return Osk.emojiItems(root.emojiCategory, root.emojiQuery)
  }

  function sendEmoji(value) {
    if (!root.service) return
    root.service.typeText(String(value || ""))
    var recent = root.cfg("keyboard.emojiRecent", [])
    if (!Array.isArray(recent)) recent = []
    var next = [String(value || "")]
    for (var i = 0; i < recent.length && next.length < 24; i++)
      if (String(recent[i]) !== String(value || "")) next.push(String(recent[i]))
    root.setCfg("keyboard.emojiRecent", next)
    root.setCfg("keyboard.emojiCategory", root.emojiCategory)
  }

  function toolbarButtons() {
    var all = Osk.toolbarItems()
    if (root.toolbarOverflowVisible || root.width >= Style.space(800)) return all
    return ["suggestions", "clipboard", "emoji", "handwriting", "editing", "more"]
  }

  function toolbarLabel(key) {
    var labels = {
      suggestions: "✦",
      clipboard: "▣",
      emoji: "☺",
      handwriting: "✎",
      editing: "↔",
      language: root.language.toUpperCase(),
      mode: "⌨",
      settings: "⚙",
      hide: "⌄",
      more: "…"
    }
    return labels[String(key || "")] || String(key || "")
  }

  function toolbarAction(key) {
    var value = String(key || "")
    if (value === "clipboard" && root.panel) { root.panel.activeView = "clipboard"; return }
    if (value === "emoji") { root.setLayer("emoji"); return }
    if (value === "handwriting") { root.setMode("handwriting"); return }
    if (value === "editing") { root.setLayer("editing"); return }
    if (value === "language") { root.toggleLanguage(); return }
    if (value === "mode") { root.modeChooserVisible = !root.modeChooserVisible; return }
    if (value === "settings" && root.panel) { root.panel.activeView = "settings"; return }
    if (value === "hide" && root.panel) { root.panel.close(); return }
    if (value === "more") { root.toolbarOverflowVisible = !root.toolbarOverflowVisible; return }
  }

  function resetFloatingPosition() {
    root.floatingX = 0.5
    root.floatingY = 0.72
    root.setCfg("keyboard.floating.x", root.floatingX)
    root.setCfg("keyboard.floating.y", root.floatingY)
  }

  function commitFloatingPosition() {
    if (keyboardHost.width <= 0 || keyboardHost.height <= 0) return
    root.floatingX = Math.max(0.12, Math.min(0.88, root.floatingX))
    root.floatingY = Math.max(0.18, Math.min(0.88, root.floatingY))
    root.setCfg("keyboard.floating.x", root.floatingX)
    root.setCfg("keyboard.floating.y", root.floatingY)
  }

  function startInk(x, y) {
    root.currentStroke = [{ x: x, y: y }]
    root.strokes = root.strokes.concat([root.currentStroke])
    root.redoStrokes = []
    inkCanvas.requestPaint()
  }

  function moveInk(x, y) {
    if (!root.currentStroke || root.currentStroke.length === 0) return
    root.currentStroke = root.currentStroke.concat([{ x: x, y: y }])
    var next = root.strokes.slice()
    next[next.length - 1] = root.currentStroke
    root.strokes = next
    inkCanvas.requestPaint()
  }

  function endInk() { root.currentStroke = [] }

  function clearInk() {
    root.strokes = []
    root.redoStrokes = []
    inkCanvas.requestPaint()
  }

  function undoInk() {
    if (root.strokes.length === 0) return
    var next = root.strokes.slice()
    root.redoStrokes = root.redoStrokes.concat([next.pop()])
    root.strokes = next
    inkCanvas.requestPaint()
  }

  function redoInk() {
    if (root.redoStrokes.length === 0) return
    var next = root.redoStrokes.slice()
    root.strokes = root.strokes.concat([next.pop()])
    root.redoStrokes = next
    inkCanvas.requestPaint()
  }

  Component.onCompleted: root.refreshLanguage()

  Timer {
    id: shiftTapTimer
    interval: 380
    repeat: false
    onTriggered: root.lastShiftTap = 0
  }

  Timer {
    id: repeatTimer
    interval: 420
    repeat: true
    onTriggered: {
      root.press(root.repeatKey)
      interval = root.repeatInterval()
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        text: root.service ? root.service.tr("keyboard", "Keyboard") : "Keyboard"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      ActionButton { compact: true; text: "EN"; checked: root.language === "en"; onClicked: { root.language = "en"; root.setCfg("keyboard.layout", "en") } }
      ActionButton { compact: true; text: "RU"; checked: root.language === "ru"; onClicked: { root.language = "ru"; root.setCfg("keyboard.layout", "ru") } }
      Item { Layout.fillWidth: true }
      Text {
        text: root.service && root.service.wtypeAvailable ? "virtual-keyboard-v1" : "backend unavailable"
        color: root.service && root.service.wtypeAvailable ? Color.accent : Color.urgent
        font.pixelSize: Style.font.caption
      }
    }

    Flickable {
      id: toolbarScroller
      Layout.fillWidth: true
      Layout.preferredHeight: root.toolbarEnabled ? Style.space(42) : 0
      visible: root.toolbarEnabled
      clip: true
      contentWidth: toolbarRow.width
      contentHeight: height
      interactive: contentWidth > width

      Row {
        id: toolbarRow
        height: parent.height
        spacing: Style.space(6)
        Repeater {
          model: root.toolbarButtons()
          delegate: ActionButton {
            required property string modelData
            compact: true
            minimumWidth: Style.space(44)
            text: root.toolbarLabel(modelData)
            subtitle: modelData === "suggestions" && (!root.service || !root.service.inputBackendAvailable) ? "offline" : ""
            onClicked: root.toolbarAction(modelData)
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      visible: root.modeChooserVisible
      spacing: Style.space(5)
      Text { text: "Mode"; color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: ["standard", "floating", "split", "thumb", "one-handed-left", "one-handed-right", "handwriting"]
        delegate: ActionButton {
          required property string modelData
          compact: true
          text: modelData.replace("one-handed-", "").replace("-", " ")
          checked: root.mode === modelData
          onClicked: root.setMode(modelData)
        }
      }
      ActionButton { compact: true; text: "Reset"; visible: root.mode === "floating"; onClicked: root.resetFloatingPosition() }
    }

    RowLayout {
      Layout.fillWidth: true
      visible: root.inputLayer !== "emoji" && root.mode !== "handwriting"
      spacing: Style.space(6)
      ActionButton { compact: true; text: "ABC"; checked: root.inputLayer === "letters"; onClicked: root.setLayer("letters") }
      ActionButton { compact: true; text: "123"; checked: root.inputLayer === "numeric"; onClicked: root.setLayer("numeric") }
      ActionButton { compact: true; text: "§"; checked: root.inputLayer === "symbols"; onClicked: root.setLayer("symbols") }
      ActionButton { compact: true; text: "☺"; checked: root.inputLayer === "emoji"; onClicked: root.setLayer("emoji") }
      ActionButton { compact: true; text: "Edit"; checked: root.inputLayer === "editing"; onClicked: root.setLayer("editing") }
      Item { Layout.fillWidth: true }
      Text {
        visible: root.inputLayer === "letters" && root.cfg("keyboard.suggestions", true)
        text: root.service && root.service.inputBackendAvailable ? "Local suggestions" : "Suggestions require optional local input backend"
        color: root.service && root.service.inputBackendAvailable ? Color.accent : Color.muted
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Item {
      id: keyboardHost
      Layout.fillWidth: true
      Layout.fillHeight: true

      Surface {
        id: keyboardSurface
        property var profile: Osk.modeProfile(root.mode)
        width: Math.min(parent.width, root.mode === "floating" ? parent.width * Number(root.cfg("keyboard.floating.width", 0.82)) : (root.mode === "one-handed-left" || root.mode === "one-handed-right" || root.mode === "thumb" ? parent.width * Number(root.cfg("keyboard.oneHanded.width", 0.72)) : parent.width))
        height: Math.min(parent.height, root.mode === "handwriting" ? parent.height : Math.max(Style.space(220), Number(root.cfg("keyboard.height", 300))))
        x: {
          if (root.mode === "floating") return Math.max(0, Math.min(parent.width - width, parent.width * root.floatingX - width / 2))
          if (root.mode === "one-handed-left") return parent.width * Number(root.cfg("keyboard.oneHanded.offset", 0.04))
          if (root.mode === "one-handed-right") return parent.width - width - parent.width * Number(root.cfg("keyboard.oneHanded.offset", 0.04))
          return (parent.width - width) / 2
        }
        y: root.mode === "floating" ? Math.max(0, Math.min(parent.height - height, parent.height * root.floatingY - height / 2)) : parent.height - height
        surfaceRadius: Style.space(16)
        surfaceColor: Util.alpha(Color.background, 0.72)
        clip: true

        Rectangle {
          visible: root.mode === "floating"
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(88)
          height: Style.space(8)
          radius: height / 2
          color: Util.alpha(Color.foreground, 0.35)
          MouseArea {
            anchors.fill: parent
            property real startX: 0
            property real startY: 0
            onPressed: { startX = mouse.x; startY = mouse.y }
            onPositionChanged: {
              if (!pressed || keyboardHost.width <= 0 || keyboardHost.height <= 0) return
              root.floatingX += (mouse.x - startX) / keyboardHost.width
              root.floatingY += (mouse.y - startY) / keyboardHost.height
              startX = mouse.x
              startY = mouse.y
              root.floatingX = Math.max(0.12, Math.min(0.88, root.floatingX))
              root.floatingY = Math.max(0.18, Math.min(0.88, root.floatingY))
            }
            onReleased: root.commitFloatingPosition()
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(6)
          visible: root.mode !== "handwriting" && !root.spaceCursorMode && root.inputLayer !== "emoji"

          Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: root.showModifierRow ? Style.space(44) : 0
            visible: root.showModifierRow
            spacing: Style.space(4)
            Repeater {
              model: root.modifierKeys()
              delegate: ActionButton {
                required property string modelData
                compact: true
                height: Style.space(40)
                minimumHeight: Style.space(40)
                minimumWidth: ["←", "↑", "↓", "→"].indexOf(modelData) >= 0 ? Style.space(42) : Style.space(62)
                text: modelData === "Control" ? "Ctrl" : modelData
                checked: (root.isModifier(modelData) && root.modifierState[modelData] === true) || (modelData === "Fn" && root.inputLayer === "function")
                onClicked: { root.stopHold(); root.press(modelData) }
                onPressAndHold: root.beginHold(modelData)
                onReleased: root.stopHold()
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(5)
            visible: !Osk.modeProfile(root.mode).split
            Repeater {
              model: root.rows()
              delegate: Flow {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(48)
                spacing: Style.space(4)
                Repeater {
                  model: modelData
                  delegate: ActionButton {
                    required property string modelData
                    compact: true
                    height: Style.space(44)
                    minimumHeight: Style.space(44)
                    minimumWidth: root.keyWidth(modelData, keyboardSurface.width - Style.space(20), parent.model ? parent.model.length : 8)
                    text: root.keyText(modelData)
                    checked: (modelData === "Shift" && root.shifted) || (modelData === "Caps" && root.capsLocked)
                    onClicked: { root.stopHold(); root.press(modelData) }
                    onPressAndHold: root.beginHold(modelData)
                  }
                }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(5)
            visible: Osk.modeProfile(root.mode).split
            Repeater {
              model: root.splitRows()
              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(48)
                spacing: Style.space(Number(root.cfg("keyboard.split.gap", 24)))
                Flow {
                  Layout.fillWidth: true
                  Layout.preferredWidth: keyboardSurface.width * Number(root.cfg("keyboard.split.blockWidth", 0.43))
                  spacing: Style.space(4)
                  Repeater {
                    model: modelData.left
                    delegate: ActionButton {
                      required property string modelData
                      compact: true
                      height: Style.space(44)
                      minimumHeight: Style.space(44)
                      minimumWidth: Style.space(42)
                      text: root.keyText(modelData)
                      onClicked: { root.stopHold(); root.press(modelData) }
                      onPressAndHold: root.beginHold(modelData)
                      onReleased: root.stopHold()
                    }
                  }
                }
                Flow {
                  Layout.fillWidth: true
                  Layout.preferredWidth: keyboardSurface.width * Number(root.cfg("keyboard.split.blockWidth", 0.43))
                  spacing: Style.space(4)
                  Repeater {
                    model: modelData.right
                    delegate: ActionButton {
                      required property string modelData
                      compact: true
                      height: Style.space(44)
                      minimumHeight: Style.space(44)
                      minimumWidth: Style.space(42)
                      text: root.keyText(modelData)
                      onClicked: { root.stopHold(); root.press(modelData) }
                      onPressAndHold: root.beginHold(modelData)
                      onReleased: root.stopHold()
                    }
                  }
                }
              }
            }
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(8)
          visible: root.inputLayer === "emoji"

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(5)
            Repeater {
              model: Osk.emojiCategories()
              delegate: ActionButton {
                required property var modelData
                compact: true
                minimumWidth: Style.space(62)
                text: modelData.label
                checked: root.emojiCategory === modelData.id
                onClicked: { root.emojiCategory = modelData.id; root.emojiQuery = ""; root.setCfg("keyboard.emojiCategory", modelData.id) }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            ActionButton { compact: true; text: "ABC"; onClicked: root.setLayer("letters") }
            TextInput {
              id: emojiSearch
              Layout.fillWidth: true
              height: Style.space(38)
              color: Color.foreground
              text: root.emojiQuery
              clip: true
              onTextChanged: root.emojiQuery = text
              Text { anchors.fill: parent; visible: !parent.text; text: "Search emoji locally"; color: Color.muted; verticalAlignment: Text.AlignVCenter; font.pixelSize: Style.font.caption }
            }
          }

          GridView {
            id: emojiGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: Style.space(62)
            cellHeight: Style.space(54)
            clip: true
            model: root.emojiItems()
            delegate: ActionButton {
              required property string modelData
              width: Style.space(56)
              height: Style.space(48)
              compact: true
              text: modelData
              onClicked: root.sendEmoji(modelData)
            }
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(8)
          visible: root.mode === "handwriting"

          RowLayout {
            Layout.fillWidth: true
            Text { text: "Handwriting"; color: Color.foreground; font.pixelSize: Style.font.body; font.bold: true }
            Text { text: "Ink stays local"; color: Color.accent; font.pixelSize: Style.font.caption }
            Item { Layout.fillWidth: true }
            ActionButton { compact: true; text: "Undo"; onClicked: root.undoInk() }
            ActionButton { compact: true; text: "Redo"; onClicked: root.redoInk() }
            ActionButton { compact: true; text: "Clear"; onClicked: root.clearInk() }
          }

          Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            surfaceColor: Util.alpha(Color.foreground, 0.04)
            Canvas {
              id: inkCanvas
              anchors.fill: parent
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.strokeStyle = Color.accent
                ctx.lineWidth = root.inkWidth
                for (var i = 0; i < root.strokes.length; i++) {
                  var stroke = root.strokes[i]
                  if (!stroke || stroke.length === 0) continue
                  ctx.beginPath()
                  ctx.moveTo(stroke[0].x, stroke[0].y)
                  for (var j = 1; j < stroke.length; j++) ctx.lineTo(stroke[j].x, stroke[j].y)
                  ctx.stroke()
                }
              }
              MouseArea {
                anchors.fill: parent
                onPressed: root.startInk(mouse.x, mouse.y)
                onPositionChanged: if (pressed) root.moveInk(mouse.x, mouse.y)
                onReleased: root.endInk()
              }
            }
            Text {
              anchors.centerIn: parent
              visible: root.strokes.length === 0
              text: root.service && root.service.inputBackendAvailable ? "Write here" : "Write here · recognition backend unavailable"
              color: Color.muted
              font.pixelSize: Style.font.body
            }
          }

          RowLayout {
            Layout.fillWidth: true
            ActionButton { Layout.fillWidth: true; text: "Space"; onClicked: if (root.service) root.service.sendKey("Space", false) }
            ActionButton { compact: true; text: "⌫"; onClicked: if (root.service) root.service.sendKey("Backspace", false) }
            ActionButton { compact: true; text: "↵"; onClicked: if (root.service) root.service.sendKey("Enter", false) }
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(8)
          visible: root.spaceCursorMode
          Text { text: "Space cursor"; color: Color.foreground; font.pixelSize: Style.font.body; font.bold: true }
          Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            surfaceColor: Util.alpha(Color.accent, 0.08)
            Text {
              anchors.centerIn: parent
              text: root.service && root.service.inputBackendAvailable ? "Move on this pad to control the text cursor" : "Optional omanome-input backend required for cursor motion"
              color: Color.muted
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              width: parent.width * 0.8
            }
            MouseArea {
              anchors.fill: parent
              enabled: root.service && root.service.inputBackendAvailable === true && typeof root.service.moveCursor === "function"
              onPositionChanged: if (pressed) root.service.moveCursor(mouse.x - width / 2, mouse.y - height / 2)
              onReleased: root.spaceCursorMode = false
            }
          }
          ActionButton { Layout.fillWidth: true; text: "Return to keyboard"; onClicked: root.spaceCursorMode = false }
        }
      }

      Rectangle {
        visible: root.popupAlternates.length > 0 && root.keyPopupEnabled
        z: 5
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: keyboardSurface.top
        anchors.bottomMargin: Style.space(6)
        width: Math.min(keyboardHost.width - Style.space(24), Math.max(Style.space(180), root.popupAlternates.length * Style.space(48) + Style.space(16)))
        height: Style.space(54)
        radius: Style.space(12)
        color: Color.menu.background
        border.width: 1
        border.color: Util.alpha(Color.accent, 0.55)
        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)
          Repeater {
            model: root.popupAlternates
            delegate: ActionButton {
              required property string modelData
              compact: true
              minimumWidth: Style.space(42)
              text: modelData
              onClicked: root.chooseAlternate(modelData)
            }
          }
        }
      }
    }
  }
}
