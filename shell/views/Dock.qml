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
  property var draggedApp: null
  property bool appDragActive: false

  function dragInputKind() {
    var kind = String(root.service ? root.service.lastInput : "touch")
    return ["touch", "stylus"].indexOf(kind) >= 0 ? kind : "mouse"
  }

  function beginAppSlotDrag(item) {
    if (!item || item.special || !root.service) return
    root.draggedApp = item
    root.appDragActive = true
    root.reveal()
  }

  function commitAppSlot(zoneId) {
    if (!root.draggedApp || !root.service) return false
    var item = root.draggedApp
    root.draggedApp = null
    root.appDragActive = false
    var result = item.window
      ? root.service.snapWindowToZone(item.window, zoneId, root.dragInputKind(), {})
      : root.service.launchAppToZone(item.id, zoneId, root.dragInputKind(), {})
    root.contextId = ""
    return result
  }

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  readonly property var dockConfig: root.service ? DockModel.config(root.service.config) : DockModel.config({})
  readonly property string position: root.service && root.service.tabletProfile ? String(root.service.tabletProfile.dockPosition || root.dockConfig.position) : root.dockConfig.position
  readonly property string mode: root.dockConfig.mode
  readonly property real effectiveIconSize: root.service && root.service.tabletProfile && root.service.tabletProfile.tabletLike
                                      ? Math.max(Number(root.dockConfig.iconSize), Number(root.service.tabletProfile.touchTarget || 48))
                                      : Number(root.dockConfig.iconSize)

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
    function addSpecial(id, icon, name) {
      result.push({ id: id, special: id, app: { id: id, icon: icon, name: name }, windows: [], window: null, running: false, multiple: false, active: false, urgent: false })
    }

    var list = Array.isArray(favorites) ? favorites : []
    for (var f = 0; f < list.length; f++) add(list[f], root.appFor(list[f]))
    if (root.dockConfig.runningApplications) {
      for (var w = 0; w < root.hyprWindows.length; w++) add(root.windowId(root.hyprWindows[w]), root.appFor(root.windowId(root.hyprWindows[w])))
    }
    if (root.dockConfig.showLauncher) addSpecial("__omanome-launcher__", "view-grid", root.service.tr("apps", "Apps"))
    if (root.dockConfig.showSettings) addSpecial("__omanome-settings__", "preferences-system", root.service.tr("settings", "Settings"))
    for (var i = 0; i < result.length; i++) {
      result[i].active = result[i].windows.some(function(window) { return Boolean((root.firstForeign(window) || {}).activated || window.activated) })
      result[i].urgent = result[i].windows.some(function(window) { return Boolean((root.firstForeign(window) || {}).urgent || window.urgent) })
    }
    return result
  }

  function activate(item) {
    if (!item) return
    root.service.recordInput("touch")
    if (item.special === "__omanome-launcher__") { root.service.open("launcher"); return }
    if (item.special === "__omanome-settings__") { root.service.open("settings"); return }
    var clickAction = String(root.service.cfg("dock.clickAction", "activate-or-launch"))
    if (item.window && clickAction !== "launch") {
      if (item.multiple) {
        var multipleAction = String(root.service.cfg("dock.multipleWindowAction", "cycle"))
        if (multipleAction === "overview") {
          root.service.open("overview")
          return
        }
        var next = 0
        for (var i = 0; i < item.windows.length; i++) if (root.firstForeign(item.windows[i]) && root.firstForeign(item.windows[i]).activated) { next = (i + 1) % item.windows.length; break }
        var nextWindow = root.firstForeign(item.windows[next])
        if (nextWindow && typeof nextWindow.activate === "function") nextWindow.activate()
      } else if (item.window.activated && clickAction === "activate-or-minimize") item.window.minimized = true
      else if (typeof item.window.activate === "function") item.window.activate()
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
    if (mode === "never" || mode === "always-visible") return false
    if (mode === "intelligent" || mode === "dodge-active-window" || mode === "dodge-any-window") return false
    if (mode === "autohide" || mode === "always") return true
    if (mode === "fullscreen" || mode === "fullscreen-only") return Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen === true
    return false
  }

  function windowOverlapsDock(window, screen) {
    var item = root.firstForeign(window) || window || {}
    var at = item.at || item.position || {}
    var size = item.size || item.geometry || {}
    var x = Number(at.x || at[0] || 0)
    var y = Number(at.y || at[1] || 0)
    var width = Number(size.width || size[0] || 0)
    var height = Number(size.height || size[1] || 0)
    var screenWidth = Number(screen && screen.width || 0)
    var screenHeight = Number(screen && screen.height || 0)
    if (!width || !height || !screenWidth || !screenHeight) return false
    var dockSize = tokens.space(root.effectiveIconSize + root.service.cfg("dock.padding", 10) * 2 + root.service.cfg("dock.margin", 18))
    if (root.position === "bottom") return y + height >= screenHeight - dockSize
    if (root.position === "top") return y <= dockSize
    if (root.position === "left") return x <= dockSize
    return x + width >= screenWidth - dockSize
  }

  function shouldDodge(screen) {
    var mode = String(root.service.cfg("dock.dodgeMode", "active-window"))
    if (mode === "none" || mode === "never") return false
    var rows = Array.isArray(root.hyprWindows) ? root.hyprWindows : []
    for (var i = 0; i < rows.length; i++) {
      var item = root.firstForeign(rows[i]) || rows[i]
      if (mode === "active-window" && !(item.activated || rows[i].activated)) continue
      if (root.windowOverlapsDock(rows[i], screen)) return true
    }
    return false
  }

  function hiddenForScreen(screen) {
    if (!root.dockConfig.autohide || root.revealed) return false
    if (root.shouldDodge(screen)) return true
    return root.shouldHide()
  }

  function monitorMatches(screen) {
    var monitor = String(root.service ? root.service.cfg("dock.monitor", "active") : "active")
    if (monitor === "all" || monitor === "active") return true
    return String(screen && screen.name || "") === monitor
  }

  function contextWindows() {
    return root.contextId ? root.windowsFor(root.contextId) : []
  }

  function snapContext(side) {
    var rows = root.contextWindows()
    if (rows.length === 0 || !root.service) return false
    var target = root.firstForeign(rows[0])
    var zone = root.service.multitaskingHalfZone(target, side)
    var result = root.service.snapWindowToZone(target, zone, "touch", {})
    root.contextId = ""
    return result
  }

  function splitContextWindows() {
    var rows = root.contextWindows()
    if (rows.length < 2 || !root.service) return false
    var result = root.service.splitWindows([root.firstForeign(rows[0]), root.firstForeign(rows[1])], {})
    root.contextId = ""
    return result
  }

  Connections { target: ToplevelManager.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: ToplevelManager; function onActiveToplevelChanged() { root.refresh() } }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland; function onFocusedWorkspaceChanged() { root.refresh() } }
  Connections { target: root.service; function onGestureActionRequested(action) { if (String(action || "") === "dock") root.reveal() } }

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
          anchors.leftMargin: root.position === "left" ? tokens.space(root.service.cfg("dock.margin", 18)) : 0
          anchors.rightMargin: root.position === "right" ? tokens.space(root.service.cfg("dock.margin", 18)) : 0
          surfaceRadius: root.mode === "panel" ? 0 : tokens.radius(root.service.cfg("dock.radius", 22))
          surfaceColor: Color.menu.background
          surfaceOpacity: root.service.surfaceOpacity("dock", root.service.cfg("dock.backgroundOpacity", 0.82))
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
            anchors.leftMargin: tokens.space(root.service.cfg("dock.padding", 10))
            anchors.rightMargin: tokens.space(root.service.cfg("dock.padding", 10))
            anchors.topMargin: tokens.space(root.service.cfg("dock.padding", 10))
            anchors.bottomMargin: tokens.space(root.service.cfg("dock.padding", 10))
            columns: root.position === "left" || root.position === "right" ? 1 : Math.max(1, root.items().length)
            rows: root.position === "left" || root.position === "right" ? Math.max(1, root.items().length) : 1
            columnSpacing: tokens.space(root.service.cfg("dock.spacing", 8))
            rowSpacing: tokens.space(root.service.cfg("dock.spacing", 8))

            Repeater {
              model: root.revision >= 0 ? root.items() : []
              delegate: Item {
                id: tile
                required property var modelData
                required property int index
                property string dockId: modelData.id
                property bool isFavorite: root.service.isFavoriteApp(dockId)
                property var captureSource: modelData.window
                property string previewKey: "dock:" + dockId
                property bool previewWanted: root.service && root.service.previewBudgetAllows("dock", index) && captureSource && typeof captureSource.activate === "function"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: root.position === "left" || root.position === "right" ? Style.space(60) : Style.space(root.dockConfig.minIconSize)
                Layout.minimumHeight: root.position === "bottom" || root.position === "top" ? Style.space(root.dockConfig.minIconSize) : Style.space(60)
                implicitWidth: tokens.space(root.effectiveIconSize)
                implicitHeight: tokens.space(root.effectiveIconSize)
                Drag.active: handleDrag.active || slotDrag.active
                Drag.source: tile
                Drag.keys: ["omanome-dock", "omanome-app-slot"]

                Surface {
                  anchors.fill: parent
                  surfaceRadius: Style.space(16)
                  surfaceColor: tile.modelData.urgent ? Color.accent : (tile.modelData.active ? Color.accent : Color.foreground)
                  surfaceOpacity: tile.modelData.urgent ? 0.34 : (tile.modelData.active ? 0.22 : 0.06)
                  border.width: tile.modelData.multiple ? 2 : 0
                  border.color: tile.modelData.urgent ? Color.foreground : Color.accent

                  ScreencopyView {
                    id: previewView
                    anchors.fill: parent
                    captureSource: tile.previewWanted ? tile.captureSource : null
                    live: tile.previewWanted
                    paintCursor: false
                    constraintSize: Qt.size(width, height)
                    visible: hasContent
                    opacity: 0.82
                    onHasContentChanged: if (root.service) root.service.reportLivePreview(tile.previewKey, hasContent)
                    onStopped: if (root.service) root.service.reportLivePreview(tile.previewKey, false)
                  }

                  Image {
                    anchors.centerIn: parent
                    visible: !previewView.hasContent
                    width: tokens.space(root.effectiveIconSize - 10)
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
                    text: root.service.cfg("dock.indicatorStyle", "dot") === "line" ? (tile.modelData.running ? "━" : "") : (tile.modelData.multiple ? "••" : (tile.modelData.running ? "•" : ""))
                    color: Color.accent
                    font.pixelSize: Style.font.caption
                  }

                  Component.onDestruction: if (root.service) root.service.reportLivePreview(tile.previewKey, false)
                }

                ActionButton {
                  anchors.fill: parent
                  compact: true
                  usable: true
                  opacity: 0
                  onClicked: root.activate(tile.modelData)
                  onPressAndHold: { root.contextId = tile.dockId; root.reveal() }
                }
                DragHandler {
                  id: slotDrag
                  target: tile
                  acceptedButtons: Qt.LeftButton
                  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen | PointerDevice.Stylus
                  onActiveChanged: {
                    if (active) root.beginAppSlotDrag(tile.modelData)
                    else {
                      tile.x = 0
                      tile.y = 0
                      if (root.draggedApp === tile.modelData) {
                        root.draggedApp = null
                        root.appDragActive = false
                      }
                    }
                  }
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
              ActionButton { width: parent.width; compact: true; text: root.service.tr("snapStart", "Snap start"); usable: root.contextWindows().length > 0; onClicked: root.snapContext("start") }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("snapEnd", "Snap end"); usable: root.contextWindows().length > 0; onClicked: root.snapContext("end") }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("splitWindows", "Split first two windows"); usable: root.contextWindows().length > 1; onClicked: root.splitContextWindows() }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("minimize", "Minimize"); usable: root.contextWindows().length > 0; onClicked: { var rows = root.contextWindows(); if (rows.length > 0 && root.firstForeign(rows[0])) root.firstForeign(rows[0]).minimized = true; root.contextId = "" } }
              ActionButton { width: parent.width; compact: true; text: root.service.tr("close", "Close"); usable: root.contextWindows().length > 0; onClicked: { var rows = root.contextWindows(); if (rows.length > 0 && root.firstForeign(rows[0]) && typeof root.firstForeign(rows[0]).close === "function") root.firstForeign(rows[0]).close(); root.contextId = "" } }
            }
          }
        }
        Rectangle {
          id: appSnapDropOverlay
          anchors.fill: parent
          z: 40
          visible: root.appDragActive && root.draggedApp !== null
          color: Util.alpha(Color.menu.scrim, 0.42)

          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(32), Style.space(680))
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: root.service.tr("appSnapDropTitle", "Launch app into a layout")
              color: Color.foreground
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.service ? root.service.snapZonesForTarget(root.draggedApp && root.draggedApp.window, root.dragInputKind(), {}) : []
                delegate: Item {
                  required property var modelData
                  width: Math.min(Style.space(150), Math.max(Style.space(104), (parent ? parent.width : Style.space(104)) / 4 - Style.space(6)))
                  height: Style.space(48)

                  DropArea {
                    anchors.fill: parent
                    keys: ["omanome-dock", "omanome-app-slot"]
                    onDropped: root.commitAppSlot(modelData.id)
                  }
                  ActionButton {
                    anchors.fill: parent
                    compact: true
                    minimumHeight: Style.space(48)
                    text: String(modelData.id || "snap")
                    accessibleName: root.service.tr(String(modelData.labelKey || "snap.custom"), String(modelData.id || "Snap zone"))
                    onClicked: root.commitAppSlot(modelData.id)
                  }
                }
              }
            }

            ActionButton {
              anchors.horizontalCenter: parent.horizontalCenter
              compact: true
              text: root.service.tr("cancel", "Cancel")
              onClicked: { root.draggedApp = null; root.appDragActive = false }
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
            onPressed: { root.reveal(); root.service.recordInput("touch") }
          }
        }
      }
    }
  }
}
