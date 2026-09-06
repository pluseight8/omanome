import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "components"

// The single Omanome panel is a normal Omarchy panel entry point. The host
// supplies the matching headless Service instance; views are lazy-loaded so
// opening the shell costs little when the user only wants the bar widget.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property string activeView: "overview"
  property string payloadView: ""

  function sourceFor(view) {
    var name = String(view || "overview")
    var known = ["overview", "launcher", "quicksettings", "keyboard", "clipboard", "notifications", "switcher", "settings"]
    if (known.indexOf(name) < 0) name = "overview"
    return Qt.resolvedUrl("views/" + ({ overview: "Overview.qml", launcher: "Launcher.qml", quicksettings: "QuickSettings.qml", keyboard: "Osk.qml", clipboard: "Clipboard.qml", notifications: "Notifications.qml", switcher: "Switcher.qml", settings: "Settings.qml" }[name]))
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (error) { payload = {} }
    if (payload.view) root.activeView = String(payload.view)
    root.opened = true
    if (root.service) root.service.recordInput("touch")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open("{}") }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    focusable: root.opened
    WlrLayershell.namespace: "omanome-shell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.menu.scrim, 0.78)

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }

      Surface {
        id: card
        width: Math.min(parent.width - Style.space(32), Style.space(1220))
        height: Math.min(parent.height - Style.space(32), Style.space(800))
        anchors.centerIn: parent
        surfaceRadius: Style.space(root.service && root.service.cfg("appearance.radius", 18) || 18)
        surfaceColor: Color.menu.background
        surfaceOpacity: root.service ? root.service.surfaceOpacity("settings", root.service.cfg("appearance.opacity", 0.96)) : 0.96

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(50)
            spacing: Style.space(10)

            Text {
              text: root.service ? root.service.tr("omanome", "Omanome") : "Omanome"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.service ? (root.service.detectedMode + " · " + (root.service.lastInput || "keyboard")) : ""
              color: Color.muted
              font.pixelSize: Style.font.caption
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.service && root.service.hasTouchscreen ? "● touchscreen" : "○ desktop"
              color: root.service && root.service.hasTouchscreen ? Color.accent : Color.muted
              font.pixelSize: Style.font.caption
            }
            ActionButton {
              compact: true
              minimumWidth: Style.space(72)
              text: root.service ? root.service.tr("close", "Close") : "Close"
              onClicked: root.close()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(12)

            ColumnLayout {
              Layout.preferredWidth: Style.space(168)
              Layout.fillHeight: true
              spacing: Style.space(5)

              Repeater {
                model: [
                  { key: "overview", icon: "▦", label: "overview" },
                  { key: "launcher", icon: "⌘", label: "launcher" },
                  { key: "quicksettings", icon: "☷", label: "quickSettings" },
                  { key: "keyboard", icon: "⌨", label: "keyboard" },
                  { key: "clipboard", icon: "▣", label: "clipboard" },
                  { key: "notifications", icon: "◌", label: "notifications" },
                  { key: "switcher", icon: "⇄", label: "altTab" },
                  { key: "settings", icon: "⚙", label: "settings" }
                ]
                delegate: ActionButton {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(44)
                  minimumHeight: Style.space(44)
                  compact: true
                  icon: modelData.icon
                  text: root.service ? root.service.tr(modelData.label, modelData.label) : modelData.label
                  checked: root.activeView === modelData.key
                  onClicked: root.activeView = modelData.key
                }
              }

              Item { Layout.fillHeight: true }
              Text {
                Layout.fillWidth: true
                text: root.service ? root.service.tr("standardBar", "Standard Omarchy bar is preserved") : "Standard Omarchy bar is preserved"
                color: Color.muted
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Util.alpha(Color.foreground, 0.12) }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Loader {
                id: contentLoader
                anchors.fill: parent
                source: root.sourceFor(root.activeView)
                asynchronous: true
                onLoaded: {
                  if ("service" in item) item.service = root.service
                  if ("panel" in item) item.panel = root
                }
              }

              Item {
                id: keyCatcher
                anchors.fill: parent
                focus: root.opened
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                  } else if (event.key === Qt.Key_F1) {
                    root.activeView = "overview"
                    event.accepted = true
                  } else if (event.key === Qt.Key_F2) {
                    root.activeView = "launcher"
                    event.accepted = true
                  } else if (event.key === Qt.Key_F3) {
                    root.activeView = "quicksettings"
                    event.accepted = true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
