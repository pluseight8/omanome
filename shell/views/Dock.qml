import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/Dock.js" as DockModel

// Dash-to-Dock style surface. It is one of Omanome's optional views inside
// the existing Quickshell process; it never becomes the Omarchy bar.
Item {
  id: root

  property var service: null
  property var applications: []
  property var windows: []
  property var hyprWindows: []
  property int revision: 0
  property string contextId: ""
  property bool revealed: false
  property bool pointerInside: false
  property bool touchInside: false

  readonly property var dockConfig: root.service ? DockModel.config(root.service.config) : DockModel.config({})
  readonly property string position: root.dockConfig.position
  readonly property string mode: root.dockConfig.mode

  function normalizedId(value) { return DockModel.normalizeId(value) }

  function refresh() {
    try { root.applications = DesktopEntries.applications.values || [] } catch (error) { root.applications = [] }
    try { root.windows = ToplevelManager.toplevels.values || [] } catch (error2) { root.windows = [] }
    try { root.hyprWindows = Hyprland.toplevels.values || [] } catch (error3) { root.hyprWindows = [] }
    root.revision++
  }

  function appFor(id) {
    var key = root.normalizedId(id)
    for (var i = 0; i < root.applications.length; i++) {
      var app = root.applications[i]
      if (root.normalizedId(app.id) === key) return app
    }
    return null
  }

  function windowId(window) {
    if (!window) return ""
    var foreign = window.wayland || window
    return root.normalizedId(foreign.appId || window.appId || window.class || window.startupClass || "")
  }

  function windowWorkspace(window) {
    return window && window.workspace ? Number(window.workspace.id || 0) : 0
  }

  function windowsFor(id) {
    var key = root.normalizedId(id)
    var result = []
    for (var i = 0; i < root.hyprWindows.length; i++) {
      if (root.windowId(root.hyprWindows[i]) !== key) continue
      if (root.dockConfig.workspaceIsolation && root.windowWorkspace(root.hyprWindows[i]) !== Number(Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)) continue
      result.push(root.hyprWindows[i])
    }
    if (result.length > 0) return result
    for (var j = 0; j < root.windows.length; j++) {
      if (root.windowId(root.windows[j]) === key) result.push(root.windows[j])
    }
    return result
  }

  function firstForeign(window) {
    if (!window) return null
    return window.wayland || window
  }

  function items() {
    var favorites = root.service ? root.service.cfg("launcher.favorites", []) : []
    var result = []
    var seen = {}
    function add(id, app) {
      var key = root.normalizedId(id)
      if (!key || seen[key]) return
      var matching = root.windowsFor(key)
      seen[key] = true
      result.push({ id: key, app: app || root.appFor(key), windows: matching, window: matching.length > 0 ? root.firstForeign(matching[0]) : null, running: matching.length > 0, multiple: matching.length > 1 })
    }

    var list = Array.isArray(favorites) ? favorites : []
    for (var f = 0; f < list.length; f++) add(list[f], root.appFor(list[f]))
    for (var w = 0; w < root.hyprWindows.length; w++) add(root.windowId(root.hyprWindows[w]), root.appFor(root.windowId(root.hyprWindows[w])))
    for (var a = 0; a < root.applications.length && result.length < 18; a++) add(root.applications[a].id, root.applications[a])
    return result
  }

  function activate(item) {
    if (!item) return
    root.service.recordInput("touch")
    var clickAction = String(root.service.cfg("dock.clickAction", "activate-or-launch"))
    if (item.window && clickAction !== "launch") {
      if (item.window.activated && clickAction === "activate-or-minimize") item.window.minimized = true
      else item.window.activate()
    } else {
      root.service.launchApp(item.id)
    }
  }

  function middleClick(item) {
    var action = String(root.service.cfg("dock.middleClickAction", "new-window"))
    if (action === "minimize" && item && item.window) item.window.minimized = true
    else if (item) root.service.launchApp(item.id)
  }

  function toggleFavorite(id) {
    root.service.toggleFavoriteApp(id)
    root.contextId = ""
    root.refresh()
  }

  function reorderFavorite(id, index) {
    var favorites = root.service.cfg("launcher.favorites", [])
    root.service.setConfig("launcher.favorites", DockModel.reorder(favorites, id, index))
    root.contextId = ""
    root.refresh()
  }

  function reveal() {
    root.revealed = true
    hideTimer.stop()
  }

  function scheduleHide() {
    if (!root.dockConfig.autohide || root.pointerInside || root.touchInside) return
    hideTimer.interval = Math.max(120, Number(root.service.cfg("dock.hideDelay", 650)))
    hideTimer.restart()
  }

  function shouldHide() {
    if (!root.dockConfig.autohide) return false
    if (root.pointerInside || root.touchInside || root.contextId !== "") return false
    var mode = root.dockConfig.autohideMode
    if (mode === "always-visible") return false
    if (mode === "fullscreen" && !(Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen)) return false
    return true
  }

  function hiddenForScreen(screen) {
    if (!root.dockConfig.autohide || root.revealed) return false
    return root.shouldHide()
  }

  function monitorMatches(screen) {
    var monitor = String(root.service ? root.service.cfg("dock.monitor", "active") : "active")
    if (monitor === "all" || monitor === "active") return true
    return String(screen && screen.name || "") === monitor
  }

  Connections { target: ToplevelManager.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: ToplevelManager; function onActiveToplevelChanged() { root.refresh() } }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland; function onFocusedWorkspaceChanged() { root.refresh() } }

  Timer {
    id: hideTimer
    interval: 650
    repeat: false
    onTriggered: if (root.shouldHide()) root.revealed = false
  }

  Component.onCompleted: {
    root.revealed = !root.dockConfig.autohide
    root.refresh()
  }

  Variants {
    model: root.service && root.service.cfg("dock.enabled", true) ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: dockWindow
        required property var modelData
        screen: modelData
        visible: root.monitorMatches(modelData) && !root.hiddenForScreen(modelData)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omanome-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: dockSurface }

        Surface {
          id: dockSurface
          width: root.position === "bottom" || root.position === "top" ? (root.mode === "full-width" || root.mode === "panel" ? parent.width - Style.space(24) : Math.min(parent.width - Style.space(32), Style.space(1120))) : Style.space(84)
          height: root.position === "left" || root.position === "right" ? (root.mode === "full-width" || root.mode === "panel" ? parent.height - Style.space(24) : Math.min(parent.height - Style.space(32), Style.space(760))) : Style.space(82)
          anchors.horizontalCenter: root.position === "bottom" || root.position === "top" ? parent.horizontalCenter : undefined
          anchors.verticalCenter: root.position === "left" || root.position === "right" ? parent.verticalCenter : undefined
          anchors.bottom: root.position === "bottom" ? parent.bottom : undefined
          anchors.top: root.position === "top" ? parent.top : undefined
          anchors.left: root.position === "left" ? parent.left : undefined
          anchors.right: root.position === "right" ? parent.right : undefined
          anchors.bottomMargin: root.position === "bottom" ? Style.space(root.service.cfg("dock.margin", 18)) : 0
          anchors.topMargin: root.position === "top" ? Style.space(root.service.cfg("dock.margin", 18)) : 0
          anchors.leftMargin: root.position === "left" ? Style.space(root.service.cfg("dock.margin", 18)) : 0
          anchors.rightMargin: root.position === "right" ? Style.space(root.service.cfg("dock.margin", 18)) : 0
          surfaceRadius: root.mode === "panel" ? 0 : Style.space(root.service.cfg("dock.radius", 22))
          surfaceColor: Color.menu.background
          surfaceOpacity: root.service.cfg("dock.backgroundOpacity", 0.82)
          border.width: root.service.cfg("dock.border", true) ? 1 : 0
          border.color: Util.alpha(Color.menu.border, root.service.cfg("dock.borderOpacity", 0.34))

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: { root.pointerInside = true; root.reveal() }
            onExited: { root.pointerInside = false; root.scheduleHide() }
            onPressed: { root.touchInside = true; root.reveal() }
            onReleased: { root.touchInside = false; root.scheduleHide() }
            onWheel: function(wheel) {
              if (root.service.cfg("dock.scrollAction", "workspace") === "workspace")
                root.service.dispatch(wheel.angleDelta.y > 0 ? "workspace e+1" : "workspace e-1")
            }
          }

          GridLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(root.service.cfg("dock.padding", 10))
            anchors.rightMargin: Style.space(root.service.cfg("dock.padding", 10))
            anchors.topMargin: Style.space(root.service.cfg("dock.padding", 10))
            anchors.bottomMargin: Style.space(root.service.cfg("dock.padding", 10))
            columns: root.position === "left" || root.position === "right" ? 1 : Math.max(1, root.items().length)
            rows: root.position === "left" || root.position === "right" ? Math.max(1, root.items().length) : 1
            columnSpacing: Style.space(root.service.cfg("dock.spacing", 8))
            rowSpacing: Style.space(root.service.cfg("dock.spacing", 8))

            Repeater {
              model: root.revision >= 0 ? root.items() : []
              delegate: Item {
                id: tile
                required property var modelData
                required property int index
                property string dockId: modelData.id
                property bool isFavorite: root.service.isFavoriteApp(dockId)
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: root.position === "left" || root.position === "right" ? Style.space(60) : Style.space(root.dockConfig.minIconSize)
                Layout.minimumHeight: root.position === "bottom" || root.position === "top" ? Style.space(root.dockConfig.minIconSize) : Style.space(60)
                implicitWidth: Style.space(root.dockConfig.iconSize)
                implicitHeight: Style.space(root.dockConfig.iconSize)
                Drag.active: handleDrag.active
                Drag.source: tile
                Drag.keys: ["omanome-dock"]

                Surface {
                  anchors.fill: parent
                  surfaceRadius: Style.space(16)
                  surfaceColor: tile.modelData.running ? Color.accent : Color.foreground
                  surfaceOpacity: tile.modelData.running ? 0.18 : 0.06
                  border.width: tile.modelData.multiple ? 2 : 0
                  border.color: Color.accent

                  Image {
                    anchors.centerIn: parent
                    width: Style.space(root.dockConfig.iconSize - 10)
                    height: width
                    source: root.service.iconPath(tile.modelData.app ? tile.modelData.app.icon : "application-x-executable")
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                  }
                  Text {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.modelData.multiple ? "••" : (tile.modelData.running ? "•" : "")
                    color: Color.accent
                    font.pixelSize: Style.font.caption
                  }
                }

                ActionButton {
                  anchors.fill: parent
                  compact: true
                  usable: true
                  opacity: 0
                  onClicked: root.activate(tile.modelData)
                  onPressAndHold: { root.contextId = tile.dockId; root.reveal() }
                }
                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.RightButton | Qt.MiddleButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) { root.contextId = tile.dockId; root.reveal() }
                    else root.middleClick(tile.modelData)
                  }
                }
                Text {
                  anchors.right: parent.right
                  anchors.top: parent.top
                  text: tile.isFavorite ? "⠿" : ""
                  color: Color.muted
                  font.pixelSize: Style.font.caption
                  visible: tile.isFavorite && root.service.cfg("launcher.dragReorder", true)
                  MouseArea {
                    id: handleDrag
                    anchors.fill: parent
                    drag.target: tile
                    onReleased: {
                      tile.x = 0
                      tile.y = 0
                    }
                  }
                }
                DropArea {
                  anchors.fill: parent
                  keys: ["omanome-dock"]
                  onEntered: if (drag.source && drag.source.dockId) root.reorderFavorite(drag.source.dockId, tile.index)
                }
              }
            }
          }

          Rectangle {
            visible: root.contextId !== ""
            z: 20
            width: Style.space(220)
            height: contextColumn.implicitHeight + Style.space(20)
            x: Math.max(0, Math.min(parent.width - width, parent.width / 2 - width / 2))
            y: root.position === "top" ? parent.height + Style.space(8) : -height - Style.space(8)
            radius: Style.space(14)
            color: Color.menu.background
            border.width: 1
            border.color: Color.menu.border
            Column {
              id: contextColumn
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(5)
              Text { text: root.contextId; color: Color.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
              ActionButton { width: parent.width; compact: true; text: root.service.isFavoriteApp(root.contextId) ? root.service.tr("removeFavorite", "Remove from favorites") : root.service.tr("addFavorite", "Add to favorites"); onClicked: root.toggleFavorite(root.contextId) }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("open", "Open"); onClicked: { root.service.launchApp(root.contextId); root.contextId = "" } }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("minimize", "Minimize"); usable: root.items().length > 0; onClicked: { var rows = root.windowsFor(root.contextId); if (rows.length > 0 && rows[0].wayland) rows[0].wayland.minimized = true; root.contextId = "" } }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("close", "Close"); usable: root.items().length > 0; onClicked: { var rows = root.windowsFor(root.contextId); if (rows.length > 0 && rows[0].wayland) rows[0].wayland.close(); root.contextId = "" } }
            }
          }
        }
      }
    }
  }

  // A separate tiny layer-shell surface keeps a large, touch-friendly reveal
  // target alive while the dock itself is hidden. It does not reserve space.
  Variants {
    model: root.service && root.service.cfg("dock.enabled", true) ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        id: edgeWindow
        required property var modelData
        screen: modelData
        visible: root.monitorMatches(modelData) && root.dockConfig.autohide && !root.revealed && root.shouldHide()
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omanome-dock-reveal"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
          top: root.position === "top"
          bottom: root.position === "bottom"
          left: root.position === "left"
          right: root.position === "right"
        }
        implicitWidth: root.position === "left" || root.position === "right" ? Style.space(root.service.cfg("dock.edgePressure", 12)) : parent.width
        implicitHeight: root.position === "top" || root.position === "bottom" ? Style.space(root.service.cfg("dock.edgePressure", 12)) : parent.height
        mask: Region { item: edgeHit }
        Rectangle {
          id: edgeHit
          anchors.fill: parent
          color: "transparent"
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.reveal()
            onPressed: root.reveal()
          }
        }
      }
    }
  }
}
