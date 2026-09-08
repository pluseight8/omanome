import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/AltTab.js" as AltTab
import "../models/TabletSwitcher.js" as TabletSwitcher

// A native foreign-toplevel switcher. The coverflow geometry is local UI
// state; previews use Quickshell's compositor-owned ScreencopyView stream
// when hyprland-toplevel-export-v1 produces content.
Item {
  id: root

  property var service: null
  property var panel: null
  property var windows: []
  property var rawWindows: []
  property var previewState: ({ requested: false, available: false, enabled: false, reason: "not probed" })
  property var tabletSwipeState: TabletSwitcher.emptyState()
  property bool tabletMode: false
  property int selectedIndex: 0
  property int revision: 0

  function altTabConfig() { return root.service ? root.service.cfg("altTab", {}) : {} }

  function tabletConfig() {
    return root.service && typeof root.service.tabletSwitcherOptions === "function" ? root.service.tabletSwitcherOptions() : {}
  }

  function tabletModeAvailable() {
    return root.service && typeof root.service.tabletSwitcherMode === "function" && root.service.tabletSwitcherMode() === true
  }

  function switcherContext() {
    var workspaceId
    var monitorName
    var activeIdentity = ""
    try {
      if (Hyprland.focusedWorkspace) workspaceId = Number(Hyprland.focusedWorkspace.id)
      if (Hyprland.focusedMonitor) monitorName = String(Hyprland.focusedMonitor.name || "")
    } catch (error) {}
    try {
      var active = ToplevelManager.activeToplevel
      if (active) activeIdentity = TabletSwitcher.identity(active)
    } catch (error2) {}
    return { workspaceId: workspaceId, monitorName: monitorName, activeIdentity: activeIdentity }
  }

  function targetOf(entry) { return root.tabletMode ? TabletSwitcher.windowOf(entry) : AltTab.windowOf(entry) }

  function appIdOf(entry) {
    return root.tabletMode ? TabletSwitcher.appId(entry) : (entry ? String(entry.appId || "unknown") : "unknown")
  }

  function titleOf(entry) {
    return root.tabletMode ? String(entry && entry.caption || appIdOf(entry)) : String(entry && entry.title || appIdOf(entry))
  }

  function metadataOf(entry) {
    if (root.tabletMode) {
      var workspace = String(entry && entry.workspaceId || "")
      var monitor = String(entry && entry.monitorName || "")
      return [workspace ? root.service.tr("workspace", "Workspace") + " " + workspace : "", monitor].filter(function(value) { return value !== "" }).join(" · ") || root.service.tr("nativeToplevel", "Native foreign-toplevel")
    }
    return entry && entry.count > 1 ? entry.count + " " + root.service.tr("windows", "windows") + " · " + root.service.tr("nativeToplevel", "native foreign-toplevel") : root.service.tr("nativeToplevel", "Native foreign-toplevel")
  }

  function closeTarget(target) {
    if (root.service && typeof root.service.closeSwitcherWindow === "function") return root.service.closeSwitcherWindow(target)
    var item = AltTab.foreign(target)
    if (item && typeof item.close === "function") {
      item.close()
      return true
    }
    return false
  }

  function commitTabletSwipe(index, dx, dy, velocity) {
    var decision = TabletSwitcher.decideSwipe(dx, dy, velocity, root.tabletConfig())
    if (decision.action === "select" && decision.ok) {
      root.selectedIndex = TabletSwitcher.moveIndex(root.selectedIndex, decision.delta, root.windows.length)
      cards.positionViewAtIndex(root.selectedIndex, ListView.Center)
    } else if (decision.action === "close" && decision.ok && root.tabletConfig().closeOnSwipe === true) {
      root.closeTarget(root.targetOf(root.windows[index]))
      root.refresh()
    }
    return decision
  }

  function refresh() {
    var raw = []
    var hasHyprland = false
    try { raw = Hyprland.toplevels.values || []; hasHyprland = true } catch (error) { raw = [] }
    if (raw.length === 0) {
      try { raw = ToplevelManager.toplevels.values || [] } catch (error2) { raw = [] }
    }
    root.rawWindows = raw
    var context = root.switcherContext()
    root.tabletMode = root.tabletModeAvailable()
    if (root.tabletMode) {
      root.windows = root.service && typeof root.service.tabletSwitcherCards === "function" ? root.service.tabletSwitcherCards(raw, context) : TabletSwitcher.selectable(raw, root.tabletConfig(), context)
      root.tabletSwipeState = Object.assign(TabletSwitcher.emptyState(), { phase: "ready", cardCount: root.windows.length, reason: "cards-refreshed" })
    } else {
      root.windows = AltTab.selectable(raw, root.altTabConfig(), context)
      root.tabletSwipeState = TabletSwitcher.emptyState()
    }
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))
    root.previewState = AltTab.previewState(root.altTabConfig(), root.windows.map(function(entry) { return root.targetOf(entry) }), root.service ? root.service.livePreviewState : {})
    root.revision++
  }

  function activate(index) {
    var entry = root.windows[index]
    var target = root.targetOf(entry)
    var item = AltTab.foreign(target)
    if (item && typeof item.activate === "function") item.activate()
    else if (target && typeof target.activate === "function") target.activate()
    if (root.panel) root.panel.close()
  }

  function move(delta) {
    root.selectedIndex = root.tabletMode ? TabletSwitcher.moveIndex(root.selectedIndex, delta, root.windows.length) : AltTab.moveIndex(root.selectedIndex, delta, root.windows.length)
    cards.positionViewAtIndex(root.selectedIndex, ListView.Center)
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: root.service
    function onStateUpdated() {
      if (root.tabletModeAvailable() !== root.tabletMode) root.refresh()
      else {
        root.previewState = AltTab.previewState(root.altTabConfig(), root.windows.map(function(entry) { return root.targetOf(entry) }), root.service ? root.service.livePreviewState : {})
        root.revision++
      }
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
      title: root.tabletMode ? root.service.tr("largeCards", "Large Cards") : root.service.tr("altTab", "Alt-Tab")
      subtitle: root.tabletMode ? root.service.tr("tabletSwitcherHint", "Touch-first window switcher") + " · " + root.tabletConfig().scope : "" + root.altTabConfig().style + " · " + root.altTabConfig().scope + " · native toplevels"
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
        property var geometry: root.tabletMode ? TabletSwitcher.visual(index, root.selectedIndex, root.windows.length, root.tabletConfig()) : AltTab.visual(index, root.selectedIndex, root.windows.length, root.altTabConfig())
        property var targetWindow: root.targetOf(modelData)
        property var captureSource: AltTab.captureSource(targetWindow)
        property string previewKey: root.tabletMode ? "tablet:" + String(modelData && modelData.key || index) : "altTab:" + AltTab.windowKey(targetWindow)
        property bool previewWanted: root.service && root.service.previewBudgetAllows("altTab", Math.abs(Number(geometry.distance))) && captureSource !== null
        width: root.tabletMode ? Math.min(cards.width * 0.78, Style.space(520)) : Math.min(cards.width * 0.62, Style.space(420))
        height: root.tabletMode ? Math.min(cards.height - Style.space(16), Style.space(360)) : Math.min(cards.height - Style.space(24), Style.space(300))
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        surfaceRadius: Style.space(20)
        surfaceColor: geometry.selected ? Color.accent : Color.menu.background
        surfaceOpacity: geometry.selected ? 0.24 : 0.88
        scale: geometry.scale
        opacity: geometry.opacity
        rotation: geometry.rotation
        z: geometry.z

        DragHandler {
          id: tabletSwipe
          target: null
          enabled: root.tabletMode
          acceptedButtons: Qt.LeftButton
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen | PointerDevice.Stylus
          onActiveChanged: {
            if (active) {
              if (root.service) root.service.recordInput("touch")
              if (root.service && typeof root.service.beginTabletSwitcherSwipe === "function") root.service.beginTabletSwitcherSwipe(index, { x: 0, y: 0 })
              else root.tabletSwipeState = TabletSwitcher.begin(root.tabletSwipeState, index, { x: 0, y: 0 }, root.tabletConfig(), Date.now())
            } else {
              var velocity = 0
              var result = root.service && typeof root.service.endTabletSwitcherSwipe === "function" ? root.service.endTabletSwitcherSwipe({ x: translation.x, y: translation.y }, velocity, index, card.targetWindow) : { decision: root.commitTabletSwipe(index, translation.x, translation.y, velocity) }
              root.tabletSwipeState = TabletSwitcher.emptyState()
              if (result && result.decision && result.decision.action === "close" && result.closed !== true && root.tabletConfig().closeOnSwipe === true) root.closeTarget(card.targetWindow)
            }
          }
          onTranslationChanged: {
            if (!active) return
            if (root.service && typeof root.service.updateTabletSwitcherSwipe === "function") root.service.updateTabletSwitcherSwipe({ x: translation.x, y: translation.y })
            else root.tabletSwipeState = TabletSwitcher.update(root.tabletSwipeState, { x: translation.x, y: translation.y }, root.tabletConfig(), Date.now())
          }
        }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(10)

          Text {
            text: modelData ? root.appIdOf(modelData) : "Window"
            color: Color.accent
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: modelData ? root.titleOf(modelData) : ""
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
            text: root.metadataOf(modelData)
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
      visible: root.tabletMode
      text: root.service.tr("tabletSwitcherGestureHint", "Swipe horizontally to switch · swipe up to close when enabled")
      color: Color.muted
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: root.previewState.enabled ? root.service.tr("livePreview", "Live preview") + ": compositor stream · " + root.previewState.reason : (root.previewState.requested ? root.service.tr("livePreview", "Live preview") + ": " + root.previewState.reason : root.service.tr("metadataFallback", "Metadata fallback"))
      color: root.previewState.enabled ? Color.accent : Color.muted
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
