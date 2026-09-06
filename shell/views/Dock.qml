import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../components"

// An optional, click-through layer-shell dock.  It is mounted by the shared
// Omanome service, not by a second shell process.  The standard Omarchy bar
// remains the owner of the top edge and is never hidden or resized by this UI.
Item {
  id: root

  property var service: null
  property var applications: []
  property var windows: []
  property int revision: 0
  readonly property string position: root.service ? String(root.service.cfg("dock.position", "bottom")) : "bottom"

  function normalizedId(value) {
    return String(value || "").replace(/\.desktop$/, "").toLowerCase()
  }

  function refresh() {
    try { root.applications = DesktopEntries.applications.values || [] } catch (error) { root.applications = [] }
    try { root.windows = ToplevelManager.toplevels.values || [] } catch (error2) { root.windows = [] }
    root.revision++
  }

  function appFor(id) {
    var wanted = root.normalizedId(id)
    for (var i = 0; i < root.applications.length; i++) {
      var app = root.applications[i]
      if (root.normalizedId(app.id || app.desktopId || app.name) === wanted) return app
    }
    return null
  }

  function items() {
    var result = []
    var seen = ({})
    var favorites = root.service ? root.service.cfg("launcher.favorites", []) : []
    if (!Array.isArray(favorites)) favorites = []

    function add(id, app, window) {
      var key = root.normalizedId(id || (app && app.id) || (window && window.appId))
      if (!key || seen[key]) return
      seen[key] = true
      result.push({ id: key, app: app || root.appFor(key), window: window || null })
    }

    for (var f = 0; f < favorites.length; f++) add(favorites[f], root.appFor(favorites[f]), null)
    for (var w = 0; w < root.windows.length; w++) {
      var top = root.windows[w]
      add(top.appId || top.class || top.title, root.appFor(top.appId || top.class), top)
    }
    for (var a = 0; a < root.applications.length && result.length < 12; a++) {
      var entry = root.applications[a]
      add(entry.id || entry.desktopId, entry, null)
    }
    return result
  }

  function activate(item) {
    root.service.recordInput("touch")
    if (item.window && typeof item.window.activate === "function") item.window.activate()
    else if (item.id) root.service.launchApp(item.id)
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.refresh() }
  }
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refresh() }
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: root.service && root.service.cfg("dock.enabled", true) ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: dockWindow
        required property var modelData
        screen: modelData
        visible: true
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omanome-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: dockSurface }

        Surface {
          id: dockSurface
          width: root.position === "bottom" ? Math.min(parent.width - Style.space(32), Style.space(920)) : Style.space(76)
          height: root.position === "bottom" ? Style.space(76) : Math.min(parent.height - Style.space(32), Style.space(720))
          anchors.horizontalCenter: root.position === "bottom" ? parent.horizontalCenter : undefined
          anchors.verticalCenter: root.position === "bottom" ? undefined : parent.verticalCenter
          anchors.bottom: root.position === "bottom" ? parent.bottom : undefined
          anchors.left: root.position === "left" ? parent.left : undefined
          anchors.right: root.position === "right" ? parent.right : undefined
          anchors.bottomMargin: root.position === "bottom" ? Style.space(18) : 0
          anchors.leftMargin: root.position === "left" ? Style.space(18) : 0
          anchors.rightMargin: root.position === "right" ? Style.space(18) : 0
          surfaceRadius: Style.space(22)
          surfaceColor: Color.menu.background
          surfaceOpacity: root.service ? root.service.cfg("dock.backgroundOpacity", 0.82) : 0.82

          GridLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            columns: root.position === "bottom" ? 12 : 1
            spacing: Style.space(8)

            Repeater {
              model: root.revision >= 0 ? root.items() : []
              delegate: ActionButton {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: Style.space(58)
                minimumWidth: Style.space(58)
                compact: true
                icon: modelData.window ? "●" : "○"
                text: modelData.app ? String(modelData.app.name || modelData.id) : String(modelData.id)
                checked: !!modelData.window
                onClicked: root.activate(modelData)
                onPressAndHold: if (modelData.window && modelData.window.minimized !== undefined) modelData.window.minimized = true
              }
            }
          }
        }
      }
    }
  }
}
