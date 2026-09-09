import QtQuick
import qs.Commons
import "IconGlyphs.js" as IconGlyphs

Text {
  id: root

  property string name: ""
  property string fallback: "•"
  property real size: Style.font.body
  property color iconColor: Color.foreground
  property string accessibleLabel: ""

  text: IconGlyphs.glyph(root.name, root.fallback)
  color: root.iconColor
  font.family: Style.font.family
  font.pixelSize: root.size
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  Accessible.ignored: root.accessibleLabel === ""
  Accessible.name: root.accessibleLabel
}
