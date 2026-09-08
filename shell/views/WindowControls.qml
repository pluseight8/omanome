import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../components"

// Touch-sized controls for the active foreign toplevel.  These call the
// public Toplevel operations exposed by Quickshell/Hyprland, so they do not
// draw a fake titlebar over every client or rewrite client decorations.
Item {
  id: root

  property var service: null
  property var activeWindow: null
  property int revision: 0

  function refresh() {
    try { root.activeWindow = ToplevelManager.activeToplevel } catch (error) { root.activeWindow = null }
    root.revision++
  }

  function outputName(output) {
    if (!output) return ""
    return String(output.name || output.id || "")
  }

  function belongsTo(output) {
    if (!root.activeWindow) return false
    var monitor = root.activeWindow.monitor
    if (!monitor) return true
    var actual = root.outputName(monitor)
    return !actual || actual === root.outputName(output)
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.refresh() }
  }
  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: root.service
    function onFloatingRevisionChanged() { root.refresh() }
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: root.service && root.service.cfg("windowControls.enabled", true) ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: controlsWindow
        required property var modelData
        screen: modelData
        visible: root.activeWindow !== null && root.belongsTo(modelData) && root.service.tabletProfile.windowControls === true && (root.service.cfg("windowControls.show", "tablet") !== "tablet" || root.service.detectedMode !== "desktop")
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omanome-window-controls"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: toolbar }

        Surface {
          id: toolbar
          width: Math.min(parent.width - Style.space(24), Style.space(520))
          height: Style.space(112)
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: Style.space(42)
          anchors.rightMargin: Style.space(18)
          surfaceRadius: Style.space(16)
          surfaceColor: Color.menu.background
          surfaceOpacity: root.service.surfaceOpacity("windowControls", root.service.cfg("windowControls.opacity", 0.94))

          GridLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(5)
            columns: 3

            ActionButton {
              Layout.preferredWidth: Style.space(150)
              Layout.fillWidth: true
              Layout.fillHeight: true
              minimumWidth: Style.space(48)
              icon: "—"
              text: root.service.tr("minimize", "Minimize")
              onClicked: if (root.activeWindow) root.activeWindow.minimized = true
            }
            ActionButton {
              Layout.fillWidth: true
              Layout.fillHeight: true
              minimumWidth: Style.space(48)
              icon: "□"
              text: root.service.tr("maximize", "Maximize")
              onClicked: if (root.activeWindow) root.activeWindow.maximized = !root.activeWindow.maximized
            }
            ActionButton {
              Layout.preferredWidth: Style.space(150)
              Layout.fillWidth: true
              Layout.fillHeight: true
              minimumWidth: Style.space(48)
              icon: root.service && root.service.floatingWindowState(root.activeWindow).floating ? "▣" : "□"
              text: root.service && root.service.floatingWindowState(root.activeWindow).floating ? root.service.tr("tileWindow", "Tile") : root.service.tr("floatWindow", "Float")
              onClicked: if (root.activeWindow && root.service) root.service.toggleWindowFloating(root.activeWindow)
            }
            ActionButton {
              Layout.preferredWidth: Style.space(150)
              Layout.fillWidth: true
              Layout.fillHeight: true
              minimumWidth: Style.space(48)
              icon: "×"
              text: root.service.tr("close", "Close")
              onClicked: if (root.activeWindow && typeof root.activeWindow.close === "function") root.activeWindow.close()
            }
            ActionButton {
              Layout.preferredWidth: Style.space(150)
              Layout.fillWidth: true
              Layout.fillHeight: true
              minimumWidth: Style.space(48)
              icon: "◇"
              text: root.service.tr("miniWindow", "Mini")
              Accessible.description: root.service.tr("miniWindowHint", "Resize and move the active window to a safe floating corner")
              onClicked: if (root.activeWindow && root.service) root.service.setWindowMini(root.activeWindow, {})
            }
            ActionButton {
              Layout.preferredWidth: Style.space(150)
              Layout.fillWidth: true
              Layout.fillHeight: true
              minimumWidth: Style.space(48)
              icon: "▣"
              text: root.service.tr("pictureInPicture", "PiP")
              Accessible.description: root.service.tr("pictureInPictureHint", "Resize, move and pin the active window on the current monitor")
              onClicked: if (root.activeWindow && root.service) root.service.setWindowPictureInPicture(root.activeWindow, {})
            }
          }
        }
      }
    }
  }
}
