import QtQuick
import qs.Commons

Rectangle {
  id: root
  property real surfaceRadius: Style.space(18)
  property color surfaceColor: Color.menu.background
  property color surfaceBorder: Color.menu.border
  property real surfaceOpacity: 1
  color: Util.alpha(surfaceColor, surfaceOpacity)
  radius: surfaceRadius
  border.width: 1
  border.color: Util.alpha(surfaceBorder, 0.34)
}
