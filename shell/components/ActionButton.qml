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
  property string accessibleName: ""
  property string accessibleDescription: ""
  property real minimumWidth: 96
  property real minimumHeight: 48
  property color foreground: Color.foreground
  property color accent: Color.accent
  signal clicked()
  signal pressAndHold()

  implicitWidth: Math.max(minimumWidth, content.implicitWidth + Style.space(24))
  implicitHeight: compact ? Style.space(38) : Math.max(minimumHeight, content.implicitHeight + Style.space(18))
  opacity: usable ? 1 : 0.42

  Accessible.name: root.accessibleName !== "" ? root.accessibleName : root.text
  Accessible.description: root.accessibleDescription !== "" ? root.accessibleDescription : root.subtitle
  Accessible.role: Accessible.Button
  Accessible.checked: root.checked

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: Style.space(12)
    color: root.checked ? Util.alpha(root.accent, 0.22) : (mouse.containsMouse ? Util.alpha(root.foreground, 0.10) : Util.alpha(root.foreground, 0.05))
    border.width: root.checked ? 1 : (mouse.containsMouse ? 1 : 0)
    border.color: root.checked ? root.accent : Util.alpha(root.foreground, 0.28)

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        visible: root.icon !== ""
        text: root.icon
        color: root.checked ? root.accent : root.foreground
        font.family: Style.font.family
        font.pixelSize: root.compact ? Style.font.body : Style.font.title
        verticalAlignment: Text.AlignVCenter
      }

      Column {
        spacing: 1
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: root.text
          color: root.checked ? root.accent : root.foreground
          font.family: Style.font.family
          font.pixelSize: root.compact ? Style.font.caption : Style.font.body
          font.bold: root.checked
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Style.space(240))
        }

        Text {
          visible: root.subtitle !== ""
          text: root.subtitle
          color: Util.alpha(root.foreground, 0.64)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Style.space(240))
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
      onClicked: root.clicked()
      onPressAndHold: root.pressAndHold()
    }
  }
}
