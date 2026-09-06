import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"

Item {
  id: root
  property var service: null
  property var panel: null
  property var windows: []
  property var workspaces: []

  function refresh() {
    try { root.windows = ToplevelManager.toplevels.values || [] } catch (error) { root.windows = [] }
    try { root.workspaces = Hyprland.workspaces.values || [] } catch (error2) { root.workspaces = [] }
  }

  function activateWindow(window) {
    if (window && typeof window.activate === "function") window.activate()
    if (root.panel) root.panel.close()
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    for (var i = 0; i < root.workspaces.length; i++) {
      var id = Number(root.workspaces[i].id)
      if (isFinite(id) && id > 0 && ids.indexOf(id) < 0) ids.push(id)
    }
    ids.sort(function(a, b) { return a - b })
    return ids
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
    target: Hyprland.workspaces
    function onValuesChanged() { root.refresh() }
  }

  Component.onCompleted: root.refresh()

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(16)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("currentWindows", "Current windows")
      subtitle: root.service.tr("overviewHint", "A GNOME-like overview that keeps Hyprland and Omarchy intact.")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text { text: root.service.tr("workspaces", "Workspaces"); color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: root.workspaceIds()
        delegate: ActionButton {
          required property int modelData
          compact: true
          minimumWidth: Style.space(40)
          text: String(modelData)
          checked: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData
          onClicked: root.service.dispatch("workspace " + modelData)
        }
      }
      Item { Layout.fillWidth: true }
      ActionButton {
        compact: true
        text: root.service.tr("forceQuit", "Force quit")
        icon: "×"
        onClicked: root.service.quickAction("forceQuit")
      }
    }

    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      cellWidth: Math.max(Style.space(220), Math.floor(width / Math.max(1, width > Style.space(760) ? 3 : 1)))
      cellHeight: Style.space(130)
      clip: true
      model: root.windows
      delegate: Surface {
        required property var modelData
        width: grid.cellWidth - Style.space(12)
        height: grid.cellHeight - Style.space(12)
        surfaceRadius: Style.space(16)
        surfaceColor: modelData && modelData.activated ? Color.accent : Color.menu.background
        surfaceOpacity: modelData && modelData.activated ? 0.18 : 0.9

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: Style.space(8)

          Text {
            text: modelData ? (modelData.appId || "Window") : "Window"
            color: Color.accent
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: modelData ? (modelData.title || modelData.appId || "") : ""
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: "Foreign-toplevel surface"
            color: Color.muted
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(6)
            ActionButton { compact: true; minimumWidth: Style.space(42); text: "↗"; onClicked: root.activateWindow(modelData) }
            ActionButton { compact: true; minimumWidth: Style.space(42); text: "—"; onClicked: if (modelData) modelData.minimized = true }
            ActionButton { compact: true; minimumWidth: Style.space(42); text: "□"; onClicked: if (modelData) modelData.maximized = !modelData.maximized }
            ActionButton { compact: true; minimumWidth: Style.space(42); text: "×"; onClicked: if (modelData) modelData.close() }
          }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          onClicked: root.activateWindow(modelData)
          onPressed: root.service.recordInput("touch")
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.windows.length === 0
        text: root.service.tr("noWindows", "No windows found")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }
}
