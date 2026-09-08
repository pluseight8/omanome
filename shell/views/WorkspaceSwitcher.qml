import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/WorkspaceSwitcher.js" as WorkspaceSwitcher

// Compact, transient workspace navigation.  The compositor remains the
// source of truth: this surface only dispatches an explicit workspace focus
// action and never animates a screenshot of the desktop.
Item {
  id: root

  property var service: null
  property var panel: null
  property var workspaces: []
  property var cards: []
  property int revision: 0
  property bool dragging: false

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  function activeId() {
    try { return Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : String(root.service.currentWorkspaceId()) } catch (error) {}
    return root.service && typeof root.service.currentWorkspaceId === "function" ? root.service.currentWorkspaceId() : "1"
  }

  function refresh() {
    try { root.workspaces = Hyprland.workspaces.values || [] } catch (error) { root.workspaces = [] }
    var context = { activeId: root.activeId(), livePreview: root.service && root.service.livePreviewState ? root.service.livePreviewState.available === true : false }
    root.cards = root.service && typeof root.service.workspaceSwitcherCards === "function" ? root.service.workspaceSwitcherCards(root.workspaces, context) : WorkspaceSwitcher.cards(root.workspaces, {}, context)
    root.focusedIndex = 0
    for (var i = 0; i < root.cards.length; i++) {
      if (root.cards[i].active === true) { root.focusedIndex = i; break }
    }
    root.revision++
  }

  function rawWorkspace(id) {
    for (var i = 0; i < root.workspaces.length; i++) {
      var item = root.workspaces[i]
      if (item && String(item.id) === String(id)) return item
    }
    return null
  }

  function rawWindows(workspace) {
    if (!workspace) return []
    if (workspace.toplevels && Array.isArray(workspace.toplevels.values)) return workspace.toplevels.values
    if (Array.isArray(workspace.windows)) return workspace.windows
    return []
  }

  function previewSource(id) {
    var rows = root.rawWindows(root.rawWorkspace(id))
    if (rows.length === 0) return null
    var source = rows[0]
    return source && source.wayland ? source.wayland : source
  }

  function closeOverlay() { if (root.panel) root.panel.close() }

  function focusCard(index) {
    var card = root.cards[index]
    if (!card || !root.service) return false
    var result = root.service.workspaceSwitcherFocus(card.id)
    root.closeOverlay()
    return result
  }

  function move(delta) {
    if (root.cards.length === 0) return
    var current = -1
    for (var i = 0; i < root.cards.length; i++) if (root.cards[i].active === true) { current = i; break }
    if (current < 0) current = 0
    var next = Math.max(0, Math.min(root.cards.length - 1, current + Number(delta || 0)))
    root.focusedIndex = next
  }

  property int focusedIndex: 0

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.refresh() }
  }
  Connections {
    target: root.service
    function onWorkspaceSwitcherRevisionChanged() { if (!root.dragging) root.refresh() }
    function onStateUpdated() { if (!root.dragging) root.refresh() }
  }

  Component.onCompleted: {
    root.refresh()
    dismissTimer.interval = root.service && root.service.workspaceSwitcherOptions ? (root.service.workspaceSwitcherOptions().reducedMotion ? 650 : 1300) : 1300
    dismissTimer.restart()
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left) { root.move(-1); event.accepted = true }
    else if (event.key === Qt.Key_Right) { root.move(1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.focusCard(root.focusedIndex); event.accepted = true }
    else if (event.key === Qt.Key_Escape) { root.closeOverlay(); event.accepted = true }
  }

  DragHandler {
    id: workspaceSwipe
    target: null
    acceptedButtons: Qt.LeftButton
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen | PointerDevice.Stylus
    onActiveChanged: {
      if (active) {
        root.dragging = true
        if (root.service) root.service.recordInput("touch")
        if (root.service && root.service.workspaceSwitcherState && root.service.workspaceSwitcherState.phase !== "tracking") root.service.beginWorkspaceSwitcherSwipe(translation.x < 0 ? "next" : "previous")
      } else {
        var velocity = 0
        var result = root.service ? root.service.endWorkspaceSwitcherSwipe(translation.x, velocity) : null
        root.dragging = false
        if (result && result.decision && result.decision.action === "workspace-focus") root.closeOverlay()
        else dismissTimer.restart()
      }
    }
    onTranslationChanged: {
      if (!active || !root.service) return
      if (!root.service.workspaceSwitcherState || root.service.workspaceSwitcherState.phase !== "tracking") root.service.beginWorkspaceSwitcherSwipe(translation.x < 0 ? "next" : "previous")
      root.service.updateWorkspaceSwitcherSwipe(translation.x, root.width)
    }
  }

  Timer {
    id: dismissTimer
    repeat: false
    onTriggered: root.closeOverlay()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(14)
    spacing: tokens.space(8)

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: root.service.tr("workspaceSwitcher", "Workspace switcher")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text { text: root.service.tr("touchOnlyOverlay", "Touch navigation"); color: Color.muted; font.pixelSize: Style.font.caption }
    }

    ListView {
      id: workspaceCards
      Layout.fillWidth: true
      Layout.fillHeight: true
      orientation: ListView.Horizontal
      spacing: tokens.space(8)
      clip: true
      model: root.revision >= 0 ? root.cards : []
      currentIndex: root.focusedIndex
      onCurrentIndexChanged: if (root.focusedIndex !== currentIndex) root.focusedIndex = currentIndex

      delegate: Surface {
        id: workspaceCard
        required property var modelData
        required property int index
        property var captureSource: root.previewSource(modelData.id)
        property bool previewWanted: root.service && modelData.previewAvailable === true && root.service.previewBudgetAllows("workspace-switcher", index) && captureSource && typeof captureSource.activate === "function"
        width: Math.max(tokens.space(150), Math.min(workspaceCards.width * 0.58, tokens.space(250)))
        height: Math.max(tokens.target(120), workspaceCards.height - tokens.space(4))
        surfaceRadius: tokens.radius(16)
        surfaceColor: modelData.active ? Color.accent : Color.menu.background
        surfaceOpacity: modelData.active ? 0.24 : 0.88
        border.width: root.focusedIndex === index ? 2 : 1
        border.color: root.focusedIndex === index ? Color.accent : Util.alpha(Color.menu.border, 0.45)

        Column {
          anchors.fill: parent
          anchors.margins: tokens.space(10)
          spacing: tokens.space(5)

          Text {
            width: parent.width
            text: modelData.label
            color: Color.foreground
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: modelData.active ? root.service.tr("current", "Current") : (modelData.occupied ? root.service.tr("occupied", "Occupied") : root.service.tr("available", "Available"))
            color: modelData.active ? Color.accent : Color.muted
            font.pixelSize: Style.font.caption
          }

          Item {
            width: parent.width
            height: Math.max(tokens.space(34), parent.height - tokens.space(66))
            clip: true
            Rectangle { anchors.fill: parent; radius: tokens.radius(8); color: Util.alpha(Color.foreground, tokens.highContrast ? 0.10 : 0.05) }
            ScreencopyView {
              id: previewView
              anchors.fill: parent
              captureSource: workspaceCard.previewWanted ? workspaceCard.captureSource : null
              live: workspaceCard.previewWanted
              paintCursor: false
              constraintSize: Qt.size(width, height)
              visible: hasContent
              onHasContentChanged: if (root.service) root.service.reportLivePreview("workspace-switcher:" + modelData.id, hasContent)
              onStopped: if (root.service) root.service.reportLivePreview("workspace-switcher:" + modelData.id, false)
            }
            Text {
              anchors.centerIn: parent
              visible: !previewView.hasContent
              text: workspaceCard.previewWanted ? root.service.tr("waitingForPreview", "Waiting for live preview") : root.service.tr("metadataFallback", "Metadata fallback")
              color: Color.muted
              font.pixelSize: Style.font.caption
            }
            Component.onDestruction: if (root.service) root.service.reportLivePreview("workspace-switcher:" + modelData.id, false)
          }

          Text {
            width: parent.width
            text: modelData.windowCount > 0 ? modelData.windowCount + " " + root.service.tr("windows", "windows") : root.service.tr("emptyWorkspace", "Empty workspace")
            color: Color.muted
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onPressed: root.service.recordInput("touch")
          onClicked: { root.focusedIndex = index; root.focusCard(index) }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.cards.length === 0
        text: root.service.tr("noWorkspaces", "No workspaces available")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }

    Text {
      Layout.fillWidth: true
      text: root.service.tr("workspaceSwitcherHint", "Tap a workspace or swipe horizontally · previews appear only when the compositor provides them")
      color: Color.muted
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
