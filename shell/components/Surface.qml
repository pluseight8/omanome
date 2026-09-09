import QtQuick
import qs.Commons

Rectangle {
  id: root
  property var tokens: null
  property real surfaceRadius: root.tokens && root.tokens.radiusLg !== undefined ? root.tokens.radiusLg : Style.space(18)
  property color surfaceColor: Color.menu.background
  property color surfaceBorder: Color.menu.border
  property real surfaceOpacity: 1
  readonly property real effectiveOpacity: root.tokens && root.tokens.reduceTransparency === true ? 1 : surfaceOpacity
  color: Util.alpha(surfaceColor, effectiveOpacity)
  radius: surfaceRadius
  border.width: root.tokens && root.tokens.separatorWidth !== undefined ? root.tokens.separatorWidth : 1
  border.color: Util.alpha(surfaceBorder, root.tokens && root.tokens.borderOpacity !== undefined ? root.tokens.borderOpacity : 0.34)
}
