import QtQuick
import qs.Commons

Item {
  id: root
  property string title: ""
  property string subtitle: ""
  implicitHeight: titleText.implicitHeight + (subtitle !== "" ? subtitleText.implicitHeight + Style.space(4) : 0)
  implicitWidth: Math.max(titleText.implicitWidth, subtitleText.implicitWidth)

  Column {
    anchors.fill: parent
    spacing: Style.space(4)
    Text {
      id: titleText
      text: root.title
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      id: subtitleText
      text: root.subtitle
      visible: root.subtitle !== ""
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
