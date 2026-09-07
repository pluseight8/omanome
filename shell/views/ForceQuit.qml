import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/ForceQuit.js" as ForceQuit

// Force Quit operates on a selected native Hyprland foreign-toplevel. It
// never searches by application name and offers Cancel at every interactive
// stage, including Escape and right click.
Item {
  id: root

  property var service: null
  property var panel: null
  property var windows: []
  property int revision: 0

  function refresh() {
    try { root.windows = Hyprland.toplevels.values || [] } catch (error) { root.windows = [] }
    root.revision++
  }

  function cancel() {
    if (root.service) root.service.forceQuitCancel()
    if (root.panel) root.panel.activeView = "overview"
  }

  function selectWindow(window) {
    if (root.service && root.service.forceQuitSelect(window)) return
  }

  function currentState() { return root.service ? root.service.forceQuitState : ({ phase: "idle", message: "" }) }

  Connections { target: Hyprland.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland; function onActiveToplevelChanged() { root.refresh() } }
  Component.onCompleted: {
    root.refresh()
    if (root.service && !root.service.forceQuitState.active) root.service.forceQuitBegin()
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.cancel() }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(12)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("forceQuit", "Force Quit")
      subtitle: "Select a native window · Escape/right click cancels"
    }

    Surface {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(68)
      surfaceColor: root.currentState().phase === "error" ? Color.urgent : Color.accent
      surfaceOpacity: 0.16
      Text {
        anchors.fill: parent
        anchors.margins: Style.space(14)
        text: root.currentState().message || "Select a window to close"
        color: root.currentState().phase === "error" ? Color.urgent : Color.foreground
        font.pixelSize: Style.font.body
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
      }
    }

    ListView {
      id: candidates
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(8)
      model: root.revision >= 0 ? root.windows : []

      delegate: Surface {
        required property var modelData
        required property int index
        property var info: ForceQuit.target(modelData)
        width: candidates.width
        height: Style.space(82)
        surfaceColor: info.protectedByApp ? Color.urgent : Color.menu.background
        surfaceOpacity: info.protectedByApp ? 0.12 : 0.88

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(10)
          ColumnLayout {
            Layout.fillWidth: true
            Text { text: info.appId; color: info.protectedByApp ? Color.urgent : Color.accent; font.pixelSize: Style.font.caption; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: info.title; color: Color.foreground; font.pixelSize: Style.font.body; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: info.protectedByApp ? "Protected session process" : (info.pid > 0 ? "PID " + info.pid + " · workspace " + info.workspace : "PID unavailable · graceful close only"); color: Color.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight; Layout.fillWidth: true }
          }
          ActionButton {
            compact: true
            text: info.protectedByApp ? "Protected" : "Select"
            usable: info.selectable && root.currentState().phase === "selecting"
            onClicked: root.selectWindow(modelData)
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.windows.length === 0
        text: "No selectable windows"
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      ActionButton { Layout.fillWidth: true; text: "Cancel"; onClicked: root.cancel() }
      ActionButton {
        Layout.fillWidth: true
        visible: root.currentState().phase === "confirm"
        text: "Confirm Force Quit"
        accent: Color.urgent
        onClicked: root.service.forceQuitConfirm()
      }
      ActionButton {
        Layout.fillWidth: true
        visible: root.currentState().phase === "error" || root.currentState().phase === "done"
        text: "Back"
        onClicked: { if (root.panel) root.panel.activeView = "overview"; root.service.forceQuitCancel() }
      }
    }
  }
}
