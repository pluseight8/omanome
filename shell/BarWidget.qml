import QtQuick
import qs.Commons
import qs.Ui

// A small extension mounted by Omarchy's own bar. The host still owns the
// slots, spacing and shell lifecycle; this widget only renders the Omanome
// state and routes the click to the existing plugin panel entry point.
BarWidget {
  id: root
  moduleName: "io.omanome.shell"

  readonly property var service: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
                                ? root.bar.shell.serviceFor(root.moduleName) : null
  readonly property bool widgetEnabled: root.setting("enabled", true) !== false && (!root.service || root.service.cfg("controlCenter.widget.enabled", true) !== false)
  readonly property bool masterEnabled: !root.service || root.service.masterEnabled === true
  readonly property bool suspended: root.service && root.service.suspended === true
  readonly property bool safeMode: root.service && root.service.safeMode === true
  readonly property bool attention: root.service && String(root.service.lastError || "") !== ""
  readonly property bool partial: root.service && root.service.featureStateSummary ? root.service.featureStateSummary.partial === true : false
  readonly property string mode: root.service ? String(root.service.detectedMode || "desktop") : "desktop"
  readonly property string statusState: root.safeMode ? "safe" : root.suspended ? "suspended" : !root.masterEnabled ? "off" : root.attention ? "attention" : root.partial ? "partial" : "active"
  readonly property string visualState: root.statusState !== "active" ? root.statusState : root.mode === "tablet" ? "tablet" : "desktop"
  readonly property color iconColor: ["safe", "partial", "attention"].indexOf(root.statusState) >= 0
                                      ? (root.bar ? root.bar.urgent : Color.urgent)
                                      : (root.bar ? root.bar.barForeground : Color.foreground)

  visible: root.widgetEnabled
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  function open(view, contextMenu) {
    var payload = JSON.stringify({ view: String(view || "control-center"), contextMenu: contextMenu === true })
    if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
      return root.bar.shell.summon(root.moduleName, payload) === true
    return false
  }

  Component {
    id: omanomeIcon
    Item {
      implicitWidth: Style.bar.iconCanvas
      implicitHeight: Style.bar.iconCanvas
      property color strokeColor: root.iconColor
      Canvas {
        id: mark
        anchors.fill: parent
        property color strokeColor: parent.strokeColor
        onStrokeColorChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var inset = width * 0.16
          var radius = width * 0.18
          ctx.strokeStyle = strokeColor
          ctx.fillStyle = strokeColor
          ctx.lineWidth = Math.max(1.5, width * 0.085)
          ctx.beginPath()
          ctx.moveTo(inset + radius, inset)
          ctx.lineTo(width - inset - radius, inset)
          ctx.arc(width - inset - radius, inset + radius, radius, -Math.PI / 2, 0)
          ctx.lineTo(width - inset, height - inset - radius)
          ctx.arc(width - inset - radius, height - inset - radius, radius, 0, Math.PI / 2)
          ctx.lineTo(inset + radius, height - inset)
          ctx.arc(inset + radius, height - inset - radius, radius, Math.PI / 2, Math.PI)
          ctx.lineTo(inset, inset + radius)
          ctx.arc(inset + radius, inset + radius, radius, Math.PI, Math.PI * 1.5)
          ctx.closePath()
          ctx.stroke()
          ctx.beginPath()
          ctx.arc(width * 0.5, height * 0.55, width * 0.11, 0, Math.PI * 2)
          ctx.fill()
        }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: omanomeIcon
    slotSize: Style.bar.statusSlot
    pressable: false
    interactive: false
    tooltipText: root.safeMode ? "Omanome · Safe Mode" : root.suspended ? "Omanome · Suspended" : root.attention ? "Omanome · Attention" : "Omanome · " + root.mode
  }

  MouseArea {
    anchors.fill: button
    enabled: root.widgetEnabled
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) root.open("control-center", true)
      else root.open("control-center", false)
    }
    onPressAndHold: root.open("control-center", true)
    onEntered: if (root.bar) root.bar.showTooltip(root, root.safeMode ? "Omanome · Safe Mode" : root.suspended ? "Omanome · Suspended" : root.attention ? "Omanome · Attention" : "Omanome · " + root.mode)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
