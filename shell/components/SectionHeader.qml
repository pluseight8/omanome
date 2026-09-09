import QtQuick
import qs.Commons

Item {
  id: root
  property string title: ""
  property string subtitle: ""
  property var tokens: null
  readonly property var hostService: findHostService()
  implicitHeight: titleText.implicitHeight + (subtitle !== "" ? subtitleText.implicitHeight + root.space(4) : 0)
  implicitWidth: Math.max(titleText.implicitWidth, subtitleText.implicitWidth)

  Column {
    anchors.fill: parent
    spacing: root.space(4)
    Text {
      id: titleText
      text: root.title
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: root.fontSize("title")
      font.bold: true
    }
    Text {
      id: subtitleText
      text: root.subtitle
      visible: root.subtitle !== ""
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: root.fontSize("caption")
      wrapMode: Text.WordWrap
    }
  }

  function space(value) { return root.tokens && typeof root.tokens.space === "function" ? root.tokens.space(value) : Style.space(value) }
  function findHostService() {
    var candidate = root.parent
    while (candidate) {
      if (candidate.service !== undefined && candidate.service !== null && typeof candidate.service.cfg === "function") return candidate.service
      candidate = candidate.parent
    }
    return null
  }
  function fontSize(role) {
    if (root.tokens && typeof root.tokens.fontSize === "function") return root.tokens.fontSize(role)
    var base = role === "title" ? Style.font.title : Style.font.caption
    var scale = Number(root.hostService ? root.hostService.cfg("accessibility.textScale", 1) : 1)
    return Math.max(1, Math.round(Number(base) * Math.max(0.9, Math.min(1.5, scale))))
  }
}
