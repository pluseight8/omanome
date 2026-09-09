import QtQuick
import qs.Commons

Item {
  id: root

  property string text: ""
  property string icon: ""
  property string subtitle: ""
  property bool checked: false
  property bool usable: true
  property bool compact: false
  property bool focusable: true
  property bool pressed: false
  property var tokens: null
  readonly property var hostService: findHostService()
  property bool reducedMotion: root.tokens ? root.tokens.reducedMotion === true : !!(root.hostService && (root.hostService.cfg("general.reduceMotion", false) === true || root.hostService.cfg("accessibility.reducedMotion", false) === true))
  property real motionDuration: root.tokens && root.tokens.animationFast !== undefined ? root.tokens.animationFast : Math.max(0, Math.round(120 * Number(root.hostService ? root.hostService.cfg("animations.durationScale", 1) : 1)))
  property string iconName: ""
  property string accessibleName: ""
  property string accessibleDescription: ""
  property real minimumWidth: 96
  property real minimumHeight: 48
  property color foreground: Color.foreground
  property color accent: Color.accent
  signal clicked()
  signal pressAndHold()
  signal released()

  function findHostService() {
    var candidate = root.parent
    while (candidate) {
      if (candidate.service !== undefined && candidate.service !== null && typeof candidate.service.cfg === "function") return candidate.service
      candidate = candidate.parent
    }
    return null
  }
  function space(value) { return root.tokens && typeof root.tokens.space === "function" ? root.tokens.space(value) : Style.space(value) }
  function radius(value) { return root.tokens && typeof root.tokens.radius === "function" ? root.tokens.radius(value) : Style.space(value) }
  function fontSize(role) {
    var base = role === "title" ? Style.font.title : role === "caption" ? Style.font.caption : Style.font.body
    var scale = root.tokens && typeof root.tokens.fontSize === "function" ? 1 : Number(root.hostService ? root.hostService.cfg("accessibility.textScale", 1) : 1)
    return root.tokens && typeof root.tokens.fontSize === "function" ? root.tokens.fontSize(role) : Math.max(1, Math.round(Number(base) * Math.max(0.9, Math.min(1.5, scale))))
  }

  implicitWidth: Math.max(minimumWidth, content.implicitWidth + root.space(24))
  implicitHeight: compact ? root.space(38) : Math.max(minimumHeight, content.implicitHeight + root.space(18))
  opacity: usable ? 1 : 0.42
  activeFocusOnTab: root.focusable && root.usable

  function activateFromKeyboard(event) {
    if (!root.usable) return
    root.clicked()
    if (event) event.accepted = true
  }

  Keys.onReturnPressed: function(event) { root.activateFromKeyboard(event) }
  Keys.onEnterPressed: function(event) { root.activateFromKeyboard(event) }
  Keys.onSpacePressed: function(event) { root.activateFromKeyboard(event) }

  Accessible.name: root.accessibleName !== "" ? root.accessibleName : root.text
  Accessible.description: root.accessibleDescription !== "" ? root.accessibleDescription : root.subtitle
  Accessible.role: Accessible.Button
  Accessible.checked: root.checked

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: root.radius(12)
    color: root.checked ? Util.alpha(root.accent, 0.22) : (root.pressed ? Util.alpha(root.foreground, 0.15) : (mouse.containsMouse ? Util.alpha(root.foreground, 0.10) : Util.alpha(root.foreground, 0.05)))
    border.width: root.checked || root.pressed ? 1 : (mouse.containsMouse ? 1 : 0)
    border.color: root.checked ? root.accent : Util.alpha(root.foreground, root.tokens && root.tokens.borderOpacity !== undefined ? root.tokens.borderOpacity : 0.28)

    Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : root.motionDuration } }
    Behavior on border.color { ColorAnimation { duration: root.reducedMotion ? 0 : root.motionDuration } }

    Rectangle {
      id: focusRing
      objectName: "focusRing"
      anchors.fill: parent
      anchors.margins: -root.space(2)
      radius: root.radius(14)
      color: "transparent"
      border.width: root.activeFocus ? (root.tokens && root.tokens.focusRingWidth !== undefined ? root.tokens.focusRingWidth : root.space(2)) : 0
      border.color: root.accent
      visible: root.activeFocus
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: root.space(8)

      Icon {
        visible: root.icon !== "" || root.iconName !== ""
        name: root.iconName !== "" ? root.iconName : root.icon
        fallback: root.icon
        iconColor: root.checked ? root.accent : root.foreground
        size: root.compact ? root.fontSize("body") : root.fontSize("title")
      }

      Column {
        spacing: root.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: root.text
          color: root.checked ? root.accent : root.foreground
          font.family: Style.font.family
          font.pixelSize: root.compact ? root.fontSize("caption") : root.fontSize("body")
          font.bold: root.checked
          elide: Text.ElideRight
          width: Math.min(implicitWidth, root.space(240))
        }

        Text {
          visible: root.subtitle !== ""
          text: root.subtitle
          color: Util.alpha(root.foreground, root.tokens && root.tokens.mutedOpacity !== undefined ? root.tokens.mutedOpacity : 0.64)
          font.family: Style.font.family
          font.pixelSize: root.fontSize("caption")
          elide: Text.ElideRight
          width: Math.min(implicitWidth, root.space(240))
        }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      enabled: root.usable
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onPressed: { root.pressed = true; root.forceActiveFocus() }
      onClicked: root.clicked()
      onPressAndHold: root.pressAndHold()
      onReleased: { root.pressed = false; root.released() }
      onCanceled: root.pressed = false
    }
  }
}
