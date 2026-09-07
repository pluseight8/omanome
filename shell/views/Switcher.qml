import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/AltTab.js" as AltTab

// A native foreign-toplevel switcher. The coverflow geometry is local UI
// state; previews use Quickshell's compositor-owned ScreencopyView stream
// when hyprland-toplevel-export-v1 produces content.
Item {
  id: root

  property var service: null
  property var panel: null
  property var windows: []
  property var previewState: ({ requested: false, available: false, enabled: false, reason: "not probed" })
  property int selectedIndex: 0
  property int revision: 0

  function altTabConfig() { return root.service ? root.service.cfg("altTab", {}) : {} }

  function refresh() {
    var raw = []
    var hasHyprland = false
    try { raw = Hyprland.toplevels.values || []; hasHyprland = true } catch (error) { raw = [] }
    if (raw.length === 0) {
      try { raw = ToplevelManager.toplevels.values || [] } catch (error2) { raw = [] }
    }
    var workspaceId
    var monitorName
    if (hasHyprland && Hyprland.focusedWorkspace) workspaceId = Number(Hyprland.focusedWorkspace.id)
    if (hasHyprland && Hyprland.focusedMonitor) monitorName = String(Hyprland.focusedMonitor.name || "")
    root.windows = AltTab.selectable(raw, root.altTabConfig(), { workspaceId: workspaceId, monitorName: monitorName })
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))
    root.previewState = AltTab.previewState(root.altTabConfig(), root.windows.map(function(entry) { return AltTab.windowOf(entry) }), root.service ? root.service.livePreviewState : {})
    root.revision++
  }

  function activate(index) {
    var entry = root.windows[index]
    var target = AltTab.windowOf(entry)
    var item = AltTab.foreign(target)
    if (item && typeof item.activate === "function") item.activate()
    else if (target && typeof target.activate === "function") target.activate()
    if (root.panel) root.panel.close()
  }

  function move(delta) {
    root.selectedIndex = AltTab.moveIndex(root.selectedIndex, delta, root.windows.length)
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: root.service
    function onStateUpdated() {
      root.previewState = AltTab.previewState(root.altTabConfig(), root.windows.map(function(entry) { return AltTab.windowOf(entry) }), root.service ? root.service.livePreviewState : {})
      root.revision++
    }
  }
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.refresh() }
  }
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.refresh() }
    function onFocusedWorkspaceChanged() { root.refresh() }
    function onFocusedMonitorChanged() { root.refresh() }
  }

  Component.onCompleted: root.refresh()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left) { root.move(-1); event.accepted = true }
    else if (event.key === Qt.Key_Right) { root.move(1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.activate(root.selectedIndex); event.accepted = true }
    else if (event.key === Qt.Key_Escape && root.panel) { root.panel.close(); event.accepted = true }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(14)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("altTab", "Alt-Tab")
      subtitle: "" + root.altTabConfig().style + " · " + root.altTabConfig().scope + " · native toplevels"
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      ActionButton { compact: true; text: "‹"; onClicked: root.move(-1) }
      Text {
        Layout.fillWidth: true
        text: root.windows.length > 0 ? (root.selectedIndex + 1) + " / " + root.windows.length : root.service.tr("noWindows", "No windows found")
        color: Color.muted
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Style.font.body
      }
      ActionButton { compact: true; text: "›"; onClicked: root.move(1) }
    }

    ListView {
      id: cards
      Layout.fillWidth: true
      Layout.fillHeight: true
      orientation: ListView.Horizontal
      spacing: Style.space(12)
      clip: true
      model: root.revision >= 0 ? root.windows : []
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (root.selectedIndex !== currentIndex) root.selectedIndex = currentIndex

      delegate: Surface {
        id: card
        required property var modelData
        required property int index
        property var geometry: AltTab.visual(index, root.selectedIndex, root.windows.length, root.altTabConfig())
        property var targetWindow: AltTab.windowOf(modelData)
        property var captureSource: AltTab.captureSource(targetWindow)
        property string previewKey: "altTab:" + AltTab.windowKey(targetWindow)
        property bool previewWanted: root.service && root.service.previewBudgetAllows("altTab", Math.abs(Number(geometry.distance))) && captureSource !== null
        width: Math.min(cards.width * 0.62, Style.space(420))
        height: Math.min(cards.height - Style.space(24), Style.space(300))
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        surfaceRadius: Style.space(20)
        surfaceColor: geometry.selected ? Color.accent : Color.menu.background
        surfaceOpacity: geometry.selected ? 0.24 : 0.88
        scale: geometry.scale
        opacity: geometry.opacity
        rotation: geometry.rotation
        z: geometry.z

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(10)

          Text {
            text: modelData ? modelData.appId : "Window"
            color: Color.accent
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: modelData ? modelData.title : ""
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            width: parent.width
          }

          Item {
            id: previewArea
            width: parent.width
            height: Style.space(120)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(10)
              color: Util.alpha(Color.foreground, 0.06)
              border.width: 1
              border.color: Util.alpha(Color.menu.border, 0.45)
            }

            ScreencopyView {
              id: previewView
              anchors.fill: parent
              anchors.margins: Style.space(1)
              captureSource: card.previewWanted ? card.captureSource : null
              live: card.previewWanted
              paintCursor: false
              constraintSize: Qt.size(width, height)
              visible: hasContent
              onHasContentChanged: if (root.service) root.service.reportLivePreview(card.previewKey, hasContent)
              onStopped: if (root.service) root.service.reportLivePreview(card.previewKey, false)
            }

            Text {
              anchors.centerIn: parent
              visible: !previewView.hasContent
              text: card.previewWanted ? "Waiting for live compositor stream…" : "Live preview"
              color: Color.muted
              font.pixelSize: Style.font.caption
            }

            Component.onDestruction: if (root.service) root.service.reportLivePreview(card.previewKey, false)
          }

          Text {
            text: modelData && modelData.count > 1 ? modelData.count + " windows · native foreign-toplevel" : "Native foreign-toplevel"
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
          Item { height: Style.space(12); width: 1 }
          ActionButton { width: parent.width; text: root.service.tr("open", "Open"); checked: geometry.selected; onClicked: root.activate(index) }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          acceptedButtons: Qt.LeftButton
          onClicked: { root.selectedIndex = index; root.activate(index) }
          onPressed: root.service.recordInput("mouse")
          onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0) root.move(-1)
            else if (wheel.angleDelta.y < 0) root.move(1)
          }
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

    Text {
      Layout.fillWidth: true
      text: root.previewState.enabled ? "Live preview: compositor stream · " + root.previewState.reason : (root.previewState.requested ? "Live preview: " + root.previewState.reason : "Live previews disabled")
      color: root.previewState.enabled ? Color.accent : Color.muted
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
