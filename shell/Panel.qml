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
  property bool transientOverlay: false
  property bool contextMenu: false

  function sourceFor(view) {
    var name = String(view || "overview")
    var known = ["overview", "launcher", "quicksettings", "keyboard", "clipboard", "notifications", "switcher", "settings", "devices", "control-center", "forcequit", "onboarding", "workspace-overlay"]
    if (known.indexOf(name) < 0) name = "overview"
    return Qt.resolvedUrl("views/" + ({ overview: "Overview.qml", launcher: "Launcher.qml", quicksettings: "QuickSettings.qml", keyboard: "Osk.qml", clipboard: "Clipboard.qml", notifications: "Notifications.qml", switcher: "Switcher.qml", settings: "Settings.qml", devices: "DeviceSettings.qml", "control-center": "ControlCenter.qml", forcequit: "ForceQuit.qml", onboarding: "Onboarding.qml", "workspace-overlay": "WorkspaceSwitcher.qml" }[name]))
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (error) { payload = {} }
    if (payload.view) root.activeView = String(payload.view)
    else if (root.service && typeof root.service.needsOnboarding === "function" && root.service.needsOnboarding()) root.activeView = "onboarding"
    root.contextMenu = payload.contextMenu === true
    root.transientOverlay = root.activeView === "workspace-overlay" || root.activeView === "control-center" || payload.transient === true
    if (payload.deepLink) root.payloadView = String(payload.deepLink)
    root.opened = true
    if (root.service) root.service.recordInput("touch")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false; root.transientOverlay = false; root.contextMenu = false; if (root.service && root.service.workspaceSwitcherState) root.service.workspaceSwitcherState = Object.assign({}, root.service.workspaceSwitcherState, { phase: "idle", progress: 0, committed: false, reason: "overlay-closed" }) }
  function showWorkspaceOverlay() { root.activeView = "workspace-overlay"; root.transientOverlay = true; root.opened = true; Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function toggle() { root.opened ? root.close() : root.open("{}") }

  Component.onCompleted: if (root.service) root.service.panel = root
  Component.onDestruction: if (root.service && root.service.panel === root) root.service.panel = null

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
        width: root.activeView === "control-center" ? Math.min(parent.width - Style.space(32), Style.space(560)) : root.transientOverlay ? Math.min(parent.width - Style.space(32), Style.space(680)) : Math.min(parent.width - Style.space(32), Style.space(1220))
        height: root.activeView === "control-center" ? Math.min(parent.height - Style.space(32), Style.space(720)) : root.transientOverlay ? Math.min(parent.height - Style.space(32), Style.space(280)) : Math.min(parent.height - Style.space(32), Style.space(800))
        anchors.centerIn: parent
        surfaceRadius: Style.space(root.service && root.service.cfg("appearance.radius", 18) || 18)
        surfaceColor: Color.menu.background
        surfaceOpacity: root.service ? root.service.surfaceOpacity("settings", root.service.cfg("appearance.opacity", 0.96)) : 0.96

        DesignTokens {
          id: tokens
          service: root.service
          viewportWidth: card.width
          viewportHeight: card.height
          transitionComponent: root.activeView === "quicksettings" ? "quick-settings" : root.activeView === "overview" ? "overview" : root.activeView === "launcher" ? "launcher" : root.activeView === "keyboard" ? "osk" : "settings"
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: tokens.space(14)
          spacing: tokens.space(10)

          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: tokens.target(44)
            spacing: tokens.space(10)
            visible: !root.transientOverlay

            Text {
              text: root.service ? root.service.tr("omanome", "Omanome") : "Omanome"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.service ? ((root.service.adaptiveProfile || "auto") + " → " + (root.service.effectiveMode || root.service.detectedMode) + " · " + (root.service.lastInput || "keyboard")) : ""
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
              visible: !root.transientOverlay
              Layout.preferredWidth: tokens.space(168)
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
                  { key: "settings", icon: "⚙", label: "settings" },
                  { key: "devices", icon: "⌁", label: "devices" }
                ]
                delegate: ActionButton {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: tokens.target(44)
                  minimumHeight: tokens.target(44)
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

            Rectangle { visible: !root.transientOverlay; Layout.preferredWidth: 1; Layout.fillHeight: true; color: Util.alpha(Color.foreground, 0.12) }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Loader {
                id: contentLoader
                active: root.opened
                anchors.fill: parent
                source: root.sourceFor(root.activeView)
                asynchronous: true
                onLoaded: {
                  if ("service" in item) item.service = root.service
                  if ("panel" in item) item.panel = root
                  if (root.payloadView !== "" && typeof item.openDeepLink === "function") {
                    item.openDeepLink(root.payloadView)
                    root.payloadView = ""
                  }
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
