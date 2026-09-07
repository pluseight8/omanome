import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/Workspaces.js" as Workspaces

Item {
  id: root
  property var service: null
  property var panel: null
  property var windows: []
  property var workspaces: []
  property int revision: 0
  property int selectedWorkspace: 0
  property var draggedWindow: null

  function refresh() {
    try { root.windows = Hyprland.toplevels.values || [] } catch (error) { root.windows = [] }
    try { root.workspaces = Hyprland.workspaces.values || [] } catch (error2) { root.workspaces = [] }
    if (root.selectedWorkspace <= 0 && Hyprland.focusedWorkspace) root.selectedWorkspace = Number(Hyprland.focusedWorkspace.id)
    root.revision++
  }

  function mode() { return String(root.service.cfg("overview.workspaceMode", "dynamic")) }
  function workspaceIds() { return Workspaces.ids(root.workspaces, root.mode(), root.service.cfg("overview.fixedWorkspaceCount", 5)) }
  function foreign(window) { return window && (window.wayland || window) }
  function appId(window) {
    var item = root.foreign(window)
    return String((item && item.appId) || (window && window.appId) || "Window")
  }
  function title(window) {
    var item = root.foreign(window)
    return String((item && item.title) || (window && window.title) || root.appId(window))
  }
  function workspaceId(window) { return window && window.workspace ? Number(window.workspace.id || 0) : 0 }
  function windowRows(workspaceId) {
    var query = String(search.text || "").trim().toLowerCase()
    var all = root.service.cfg("overview.showAllWorkspaces", true)
    var result = []
    for (var i = 0; i < root.windows.length; i++) {
      var item = root.windows[i]
      if (!all && root.workspaceId(item) !== Number(workspaceId)) continue
      if (query && (root.title(item) + " " + root.appId(item)).toLowerCase().indexOf(query) < 0) continue
      result.push(item)
    }
    return result
  }

  function activateWindow(window) {
    var item = root.foreign(window)
    if (item && typeof item.activate === "function") item.activate()
    if (root.panel) root.panel.close()
  }

  function closeWindow(window) { var item = root.foreign(window); if (item && typeof item.close === "function") item.close() }
  function minimizeWindow(window) { var item = root.foreign(window); if (item) item.minimized = true }
  function maximizeWindow(window) { var item = root.foreign(window); if (item) item.maximized = !item.maximized }
  function fullscreenWindow(window) { var item = root.foreign(window); if (item) item.fullscreen = !item.fullscreen }
  function moveWindow(window, id) { root.service.moveWindowToWorkspace(window, id); root.draggedWindow = null }

  function dockApps() {
    var favorites = root.service.cfg("launcher.favorites", [])
    return Array.isArray(favorites) ? favorites : []
  }

  Connections { target: Hyprland.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland.workspaces; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland; function onFocusedWorkspaceChanged() { root.selectedWorkspace = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : root.selectedWorkspace; root.refresh() } }
  Component.onCompleted: root.refresh()

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(12)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("overview", "Overview")
      subtitle: root.service.tr("overviewHint", "Real Hyprland windows and workspaces; no fake thumbnails")
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(48)
      radius: Style.space(14)
      color: Util.alpha(Color.foreground, 0.08)
      TextInput {
        id: search
        anchors.fill: parent
        anchors.leftMargin: Style.space(16)
        anchors.rightMargin: Style.space(16)
        verticalAlignment: Text.AlignVCenter
        color: Color.foreground
        font.pixelSize: Style.font.body
        placeholderText: root.service.tr("search", "Search windows")
        onTextChanged: root.revision++
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(7)
      Text { text: root.service.tr("workspaces", "Workspaces"); color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: root.workspaceIds()
        delegate: Item {
          required property int modelData
          width: workspaceButton.implicitWidth
          height: workspaceButton.implicitHeight
          ActionButton {
            id: workspaceButton
            compact: true
            minimumWidth: Style.space(42)
            text: String(modelData)
            checked: root.selectedWorkspace === modelData
            onClicked: { root.selectedWorkspace = modelData; root.service.dispatch(Workspaces.focusCommand(modelData)) }
          }
          DropArea {
            anchors.fill: parent
            keys: ["omanome-window"]
            onDropped: if (root.draggedWindow) root.moveWindow(root.draggedWindow, modelData)
          }
        }
      }
      Item { Layout.fillWidth: true }
      ActionButton { compact: true; text: root.service.tr("launcher", "Apps"); icon: "⌘"; onClicked: if (root.panel) root.panel.activeView = "launcher" }
      ActionButton { visible: root.service.cubeState().available; compact: true; text: root.service.tr("cube", "Cube"); icon: "◇"; onClicked: root.service.cubeToggle() }
      ActionButton { compact: true; text: root.service.tr("forceQuit", "Force quit"); icon: "×"; onClicked: { root.service.forceQuitBegin(); if (root.panel) root.panel.activeView = "forcequit" } }
    }

    RowLayout {
      visible: root.service.cfg("overview.showDock", true)
      Layout.fillWidth: true
      spacing: Style.space(6)
      Text { text: root.service.tr("dock", "Dock"); color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: root.dockApps()
        delegate: ActionButton {
          required property string modelData
          compact: true
          minimumWidth: Style.space(46)
          icon: "●"
          text: modelData
          onClicked: root.service.launchApp(modelData)
        }
      }
    }

    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      cellWidth: Math.max(Style.space(250), Math.floor(width / Math.max(1, width > Style.space(760) ? 3 : 1)))
      cellHeight: Style.space(158)
      clip: true
      model: root.revision >= 0 ? root.windowRows(root.selectedWorkspace) : []

      delegate: Item {
        id: windowCard
        required property var modelData
        required property int index
        width: grid.cellWidth - Style.space(12)
        height: grid.cellHeight - Style.space(12)
        property var captureSource: root.foreign(modelData)
        property string previewKey: "overview:" + String(modelData && (modelData.address || modelData.title) || index)
        property bool previewWanted: root.service && root.service.previewBudgetAllows("overview", index) && captureSource && typeof captureSource.activate === "function"
        Drag.active: cardDrag.active
        Drag.source: windowCard
        Drag.keys: ["omanome-window"]

        Surface {
          anchors.fill: parent
          surfaceRadius: Style.space(16)
          surfaceColor: modelData && modelData.activated ? Color.accent : Color.menu.background
          surfaceOpacity: modelData && modelData.activated ? 0.18 : 0.9

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(14)
            spacing: Style.space(7)
            Text { text: root.appId(modelData); color: Color.accent; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
            Text { text: root.title(modelData); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; width: parent.width }

            Item {
              width: parent.width
              height: Style.space(48)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(8)
                color: Util.alpha(Color.foreground, 0.05)
              }

              ScreencopyView {
                id: previewView
                anchors.fill: parent
                captureSource: windowCard.previewWanted ? windowCard.captureSource : null
                live: windowCard.previewWanted
                paintCursor: false
                constraintSize: Qt.size(width, height)
                visible: hasContent
                onHasContentChanged: if (root.service) root.service.reportLivePreview(windowCard.previewKey, hasContent)
                onStopped: if (root.service) root.service.reportLivePreview(windowCard.previewKey, false)
              }

              Text {
                anchors.centerIn: parent
                visible: !previewView.hasContent
                text: windowCard.previewWanted ? "Waiting for live stream…" : "Live preview"
                color: Color.muted
                font.pixelSize: Style.font.caption
              }

              Component.onDestruction: if (root.service) root.service.reportLivePreview(windowCard.previewKey, false)
            }

            Text { text: "Hyprland foreign-toplevel · workspace " + root.workspaceId(modelData); color: Color.muted; font.pixelSize: Style.font.caption }
            Row {
              spacing: Style.space(5)
              ActionButton { compact: true; minimumWidth: Style.space(42); text: "↗"; onClicked: root.activateWindow(modelData) }
              ActionButton { compact: true; minimumWidth: Style.space(42); text: "—"; onClicked: root.minimizeWindow(modelData) }
              ActionButton { compact: true; minimumWidth: Style.space(42); text: "□"; onClicked: root.maximizeWindow(modelData) }
              ActionButton { compact: true; minimumWidth: Style.space(42); text: "×"; onClicked: root.closeWindow(modelData) }
              ActionButton { compact: true; minimumWidth: Style.space(42); text: "⛶"; onClicked: root.fullscreenWindow(modelData) }
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              if (mouse.button === Qt.LeftButton) root.activateWindow(modelData)
              else root.moveWindow(modelData, Workspaces.adjacent(root.workspaceId(modelData), "right", root.workspaceIds()))
            }
            onPressAndHold: root.draggedWindow = modelData
          }
        }
        MouseArea {
          id: cardDrag
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          drag.target: windowCard
          onClicked: root.activateWindow(modelData)
          onPressAndHold: root.draggedWindow = modelData
          onReleased: { windowCard.x = 0; windowCard.y = 0 }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.windowRows(root.selectedWorkspace).length === 0
        text: root.service.tr("noWindows", "No windows found")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }
}
