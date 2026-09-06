import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../components"

Item {
  id: root
  property var service: null
  property string tool: "pen"
  property color inkColor: "#ff5f56"
  property real inkWidth: 4
  property var strokes: []
  property var redoStrokes: []

  function addPoint(point) {
    if (root.strokes.length === 0) return
    var next = root.strokes.slice()
    var current = next[next.length - 1]
    var updated = { tool: current.tool, color: current.color, width: current.width, points: current.points.concat([point]) }
    next[next.length - 1] = updated
    root.strokes = next
    canvas.requestPaint()
  }

  function beginStroke(point) {
    var next = root.strokes.slice()
    next.push({ tool: root.tool, color: root.inkColor, width: root.inkWidth, points: [point] })
    root.strokes = next
    root.redoStrokes = []
    canvas.requestPaint()
  }

  function undo() {
    if (root.strokes.length === 0) return
    var next = root.strokes.slice()
    var removed = next.pop()
    root.strokes = next
    root.redoStrokes = root.redoStrokes.concat([removed])
    canvas.requestPaint()
  }

  function redo() {
    if (root.redoStrokes.length === 0) return
    var redo = root.redoStrokes.slice()
    var restored = redo.pop()
    root.redoStrokes = redo
    root.strokes = root.strokes.concat([restored])
    canvas.requestPaint()
  }

  PanelWindow {
    id: annotationWindow
    visible: root.service && root.service.annotationVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "omanome-annotation"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      id: backdrop
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.04)

      Surface {
        id: toolbar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Style.space(18)
        width: Math.min(parent.width - Style.space(36), Style.space(920))
        height: Style.space(64)
        surfaceColor: Color.menu.background
        surfaceOpacity: root.service.surfaceOpacity("annotation", 0.94)

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(6)

          Text { text: root.service.tr("annotation", "Annotation"); color: Color.accent; font.pixelSize: Style.font.body; font.bold: true }
          ActionButton { compact: true; text: root.service.tr("pen", "Pen"); checked: root.tool === "pen"; onClicked: { root.tool = "pen"; root.inkWidth = 4 } }
          ActionButton { compact: true; text: root.service.tr("highlighter", "Highlighter"); checked: root.tool === "highlighter"; onClicked: { root.tool = "highlighter"; root.inkWidth = 18 } }
          ActionButton { compact: true; text: root.service.tr("eraser", "Eraser"); checked: root.tool === "eraser"; onClicked: root.tool = "eraser" }
          ActionButton { compact: true; text: "●"; checked: root.inkColor === "#ff5f56"; onClicked: root.inkColor = "#ff5f56" }
          ActionButton { compact: true; text: "●"; checked: root.inkColor === "#f9e2af"; onClicked: root.inkColor = "#f9e2af" }
          ActionButton { compact: true; text: "●"; checked: root.inkColor === "#89b4fa"; onClicked: root.inkColor = "#89b4fa" }
          Item { Layout.fillWidth: true }
          ActionButton { compact: true; text: "↶"; usable: root.strokes.length > 0; onClicked: root.undo() }
          ActionButton { compact: true; text: "↷"; usable: root.redoStrokes.length > 0; onClicked: root.redo() }
          ActionButton { compact: true; text: root.service.tr("clear", "Clear"); onClicked: { root.strokes = []; root.redoStrokes = []; canvas.requestPaint() } }
          ActionButton { compact: true; text: root.service.tr("screenshot", "Screenshot"); onClicked: root.service.annotationScreenshot(false) }
          ActionButton { compact: true; text: root.service.tr("copy", "Copy"); onClicked: root.service.annotationScreenshot(true) }
          ActionButton { compact: true; text: root.service.tr("close", "Close"); onClicked: root.service.annotationVisible = false }
        }
      }

      Canvas {
        id: canvas
        anchors.fill: parent
        anchors.topMargin: toolbar.height + Style.space(32)
        anchors.margins: Style.space(8)
        antialiasing: true

        onPaint: {
          var context = getContext("2d")
          context.clearRect(0, 0, width, height)
          for (var i = 0; i < root.strokes.length; i++) {
            var stroke = root.strokes[i]
            if (!stroke.points || stroke.points.length === 0) continue
            context.beginPath()
            context.lineCap = "round"
            context.lineJoin = "round"
            context.lineWidth = Number(stroke.width || 4)
            context.strokeStyle = stroke.color || "#ff5f56"
            context.globalAlpha = stroke.tool === "highlighter" ? 0.3 : 1
            context.globalCompositeOperation = stroke.tool === "eraser" ? "destination-out" : "source-over"
            context.moveTo(stroke.points[0].x, stroke.points[0].y)
            for (var p = 1; p < stroke.points.length; p++) context.lineTo(stroke.points[p].x, stroke.points[p].y)
            context.stroke()
          }
          context.globalAlpha = 1
          context.globalCompositeOperation = "source-over"
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          hoverEnabled: true
          onPressed: function(mouse) { root.beginStroke({ x: mouse.x, y: mouse.y }) }
          onPositionChanged: function(mouse) { if (pressed) root.addPoint({ x: mouse.x, y: mouse.y }) }
        }
      }
    }
  }
}
