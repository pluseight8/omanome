import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../components"
import "../models/Workspaces.js" as Workspaces
import "../models/WindowLayout.js" as WindowLayout
import "../models/Search.js" as Search
import "../models/Apps.js" as Apps

Item {
  id: root

  property var service: null
  property var panel: null
  property var windows: []
  property var workspaces: []
  property var applications: []
  property var searchResults: []
  property int revision: 0
  property int selectedWorkspace: 0
  property int selectedSearchIndex: 0
  property var draggedWindow: null
  property var splitSelection: []
  property bool windowDragActive: false
  property var groupEntries: []

  function dragInputKind() {
    var kind = String(root.service ? root.service.lastInput : "mouse")
    return ["touch", "stylus"].indexOf(kind) >= 0 ? kind : "mouse"
  }

  function commitWindowDrop(zoneId) {
    if (!root.draggedWindow || !root.service) return false
    var window = root.draggedWindow
    root.draggedWindow = null
    root.windowDragActive = false
    var result = root.service.snapWindowToZone(window, zoneId, root.dragInputKind(), {})
    if (result && (result.ok === true || result.pending === true) && root.panel) root.panel.close()
    return result
  }

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  function refresh() {
    try { root.windows = Hyprland.toplevels.values || [] } catch (error) { root.windows = [] }
    try { root.workspaces = Hyprland.workspaces.values || [] } catch (error2) { root.workspaces = [] }
    try { root.applications = DesktopEntries.applications.values || [] } catch (error3) { root.applications = [] }
    try { root.groupEntries = root.service && typeof root.service.windowGroupSummaries === "function" ? root.service.windowGroupSummaries() : [] } catch (error4) { root.groupEntries = [] }
    if (root.selectedWorkspace <= 0 && Hyprland.focusedWorkspace) root.selectedWorkspace = Number(Hyprland.focusedWorkspace.id)
    root.refreshSearch()
    root.revision++
  }

  function mode() { return String(root.service.cfg("overview.workspaceMode", "dynamic")) }
  function workspaceIds() { return Workspaces.ids(root.workspaces, root.mode(), root.service.cfg("overview.fixedWorkspaceCount", 5), root.selectedWorkspace) }
  function workspaceOccupied(id) {
    for (var i = 0; i < root.workspaces.length; i++) {
      var item = root.workspaces[i]
      if (Number(item && item.id) !== Number(id)) continue
      if (item.toplevels && Array.isArray(item.toplevels.values)) return item.toplevels.values.length > 0
      if (Array.isArray(item.windows)) return item.windows.length > 0
      return Number(item.windows || item.toplevelCount || 0) > 0
    }
    return false
  }

  function foreign(window) { return window && (window.wayland || window) }
  function appId(window) {
    var item = root.foreign(window)
    return String((item && item.appId) || (window && window.appId) || (window && window.class) || "Window")
  }
  function title(window) {
    var item = root.foreign(window)
    return String((item && item.title) || (window && window.title) || root.appId(window))
  }
  function workspaceId(window) { return window && window.workspace ? Number(window.workspace.id || 0) : 0 }
  function appEntry(window) {
    var key = root.appId(window).replace(/\.desktop$/, "")
    for (var i = 0; i < root.applications.length; i++) {
      var item = Apps.normalize(root.applications[i])
      if (item && item.id === key) return item
    }
    return null
  }

  function windowRows(workspaceId) {
    var all = root.service.cfg("overview.showAllWorkspaces", false) === true
    var result = []
    for (var i = 0; i < root.windows.length; i++) {
      var item = root.windows[i]
      if (!all && root.workspaceId(item) !== Number(workspaceId)) continue
      result.push(item)
    }
    return result
  }

  function settingsEntries() {
    return [
      { key: "general", title: "General", description: "Mode, language and profiles", aliases: ["общие", "режим", "язык"] },
      { key: "appearance", title: "Appearance", description: "Theme, density and surfaces", aliases: ["вид", "тема", "оформление"] },
      { key: "tabletMode", title: "Tablet Mode", description: "Desktop, tablet and hybrid behavior", aliases: ["планшет", "сенсорный режим"] },
      { key: "touch", title: "Touch & Gestures", description: "Swipe, targets and touch behavior", aliases: ["касание", "жесты"] },
      { key: "stylus", title: "Stylus", description: "Pen, pressure and palm rejection", aliases: ["перо", "стилус"] },
      { key: "keyboard", title: "Keyboard", description: "On-screen keyboard and shortcuts", aliases: ["клавиатура", "osk"] },
      { key: "dock", title: "Dock", description: "Favorites, running apps and reveal", aliases: ["док", "панель"] },
      { key: "overview", title: "Overview", description: "Workspaces, windows and search", aliases: ["обзор", "рабочие столы"] },
      { key: "launcher", title: "App Grid", description: "Applications, favorites and folders", aliases: ["приложения", "лаунчер", "сетка"] },
      { key: "accessibility", title: "Accessibility", description: "Targets, text, contrast and motion", aliases: ["доступность", "контраст"] },
      { key: "diagnostics", title: "Diagnostics", description: "Runtime health and capabilities", aliases: ["диагностика", "doctor"] }
    ]
  }

  function actionEntries() {
    return [
      { key: "wifi", title: "Wi-Fi", description: "Toggle Wi-Fi", aliases: ["wifi", "вайфай", "сеть"] },
      { key: "bluetooth", title: "Bluetooth", description: "Toggle Bluetooth", aliases: ["bluetooth", "блютуз"] },
      { key: "nightLight", title: "Night Light", description: "Toggle warm display color", aliases: ["ночной свет", "night"] },
      { key: "dnd", title: "Do Not Disturb", description: "Mute notifications", aliases: ["не беспокоить", "тихо"] },
      { key: "rotationLock", title: "Rotation Lock", description: "Lock display rotation", aliases: ["поворот", "вращение"] },
      { key: "keyboard", title: "On-screen Keyboard", description: "Open the keyboard", aliases: ["клавиатура", "osk"] },
      { key: "settings", title: "Settings", description: "Open Omanome settings", aliases: ["настройки", "параметры"] }
    ]
  }

  function refreshSearch() {
    var query = String(search.text || "").trim()
    if (!query) { root.searchResults = []; return }
    root.searchResults = Search.all(query, {
      apps: root.applications,
      windows: root.windows,
      settings: root.settingsEntries(),
      actions: root.actionEntries(),
      titleFor: root.title,
      appFor: root.appId
    })
    root.selectedSearchIndex = Math.max(0, Math.min(root.selectedSearchIndex, root.searchResults.length - 1))
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

  function splitWindow(window) {
    if (!root.service || !window) return
    var id = root.service.multitaskingWindowIdentity(window)
    if (!id) return
    if (root.splitSelection.length === 0) {
      root.splitSelection = [window]
      root.revision++
      return
    }
    var first = root.splitSelection[0]
    if (root.service.multitaskingWindowIdentity(first) === id) {
      root.splitSelection = []
      root.revision++
      return
    }
    root.service.splitWindows([first, window], {})
    root.splitSelection = []
    root.revision++
  }

  function activateSearch(item) {
    if (!item) return
    if (item.kind === "app") { root.service.launchApp(item.id); if (root.panel) root.panel.close(); return }
    if (item.kind === "window") { root.activateWindow(item.payload); return }
    if (item.kind === "action") {
      if (item.id === "settings") { if (root.panel) { root.panel.payloadView = "settings://general"; root.panel.activeView = "settings" } }
      else if (item.id === "keyboard") { if (root.panel) root.panel.activeView = "keyboard" }
      else root.service.quickAction(item.id)
      return
    }
    if (item.kind === "setting" && root.panel) {
      root.panel.payloadView = "settings://" + item.id
      root.panel.activeView = "settings"
    }
  }

  function dockApps() {
    var favorites = root.service.cfg("launcher.favorites", [])
    return Array.isArray(favorites) ? favorites : []
  }

  Connections { target: Hyprland.toplevels; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland.workspaces; function onValuesChanged() { root.refresh() } }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { root.refresh() } }
  Connections { target: Hyprland; function onFocusedWorkspaceChanged() { root.selectedWorkspace = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : root.selectedWorkspace; root.refresh() } }
  Connections { target: root.service; function onConfigUpdated(path) { if (String(path || "").indexOf("multitasking.") === 0) root.refresh() } }
  Component.onCompleted: root.refresh()

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(22)
    spacing: tokens.space(12)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("overview", "Overview")
      subtitle: root.splitSelection.length > 0 ? root.service.tr("splitSelectSecond", "Split View: select a second window") : root.service.tr("overviewHint", "Current workspace first · real windows · live preview only when available")
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(44)
      radius: tokens.radius(14)
      color: Util.alpha(Color.foreground, tokens.highContrast ? 0.14 : 0.08)
      border.width: search.activeFocus ? 1 : 0
      border.color: Color.accent

      Text {
        anchors.left: parent.left
        anchors.leftMargin: tokens.space(14)
        anchors.verticalCenter: parent.verticalCenter
        text: "⌕"
        color: Color.muted
        font.pixelSize: Style.font.title
      }
      TextInput {
        id: search
        anchors.left: parent.left
        anchors.leftMargin: tokens.space(44)
        anchors.right: parent.right
        anchors.rightMargin: tokens.space(14)
        anchors.verticalCenter: parent.verticalCenter
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        clip: true
        focus: true
        placeholderText: root.service.tr("searchEverything", "Search apps, windows, settings and actions")
        onTextChanged: { root.selectedSearchIndex = 0; searchDebounce.restart(); root.revision++ }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSearch(root.searchResults[root.selectedSearchIndex])
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectedSearchIndex = Math.min(root.searchResults.length - 1, root.selectedSearchIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectedSearchIndex = Math.max(0, root.selectedSearchIndex - 1)
            event.accepted = true
          }
        }
      }
    }

    Rectangle {
      visible: root.service && root.service.snapAssistState && root.service.snapAssistState.active
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(52)
      radius: tokens.radius(12)
      color: Util.alpha(Color.accent, 0.16)
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.46)
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: tokens.space(12)
        anchors.rightMargin: tokens.space(8)
        spacing: tokens.space(8)
        Text {
          Layout.fillWidth: true
          text: root.service.tr("snapPreview", "Snap preview") + " · " + String(root.service.snapAssistState.candidateId || root.service.snapAssistState.phase || "")
          color: Color.foreground
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        ActionButton { compact: true; text: root.service.tr("cancel", "Cancel"); onClicked: root.service.cancelSnapAssist("user-cancelled") }
        ActionButton { compact: true; text: root.service.tr("apply", "Apply"); usable: root.service.snapAssistState.phase === "ready"; onClicked: root.service.commitSnapAssist() }
      }
    }

    Rectangle {
      visible: root.service && root.service.splitViewState && root.service.splitViewState.phase === "dragging"
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(52)
      radius: tokens.radius(12)
      color: Util.alpha(Color.foreground, 0.06)
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: tokens.space(12)
        anchors.rightMargin: tokens.space(8)
        spacing: tokens.space(8)
        Text {
          Layout.fillWidth: true
          text: root.service.tr("splitPreview", "Split View") + " · " + String(root.service.splitViewState.ratioName || "50/50") + " · " + String(root.service.splitViewState.pair.axis || "")
          color: Color.foreground
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        ActionButton { compact: true; text: root.service.tr("rollback", "Rollback"); onClicked: root.service.rollbackSplitView("user-cancelled") }
        ActionButton { compact: true; text: root.service.tr("apply", "Apply"); onClicked: root.service.commitSplitView() }
      }
    }

    Flickable {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(52)
      clip: true
      contentWidth: workspaceFlow.flow === Flow.LeftToRight ? Math.max(width, workspaceFlow.implicitWidth) : width
      contentHeight: workspaceFlow.flow === Flow.TopToBottom ? Math.max(height, workspaceFlow.implicitHeight) : height

      Flow {
        id: workspaceFlow
        flow: root.service.cfg("overview.workspaceOrientation", "horizontal") === "vertical" ? Flow.TopToBottom : Flow.LeftToRight
        width: flow === Flow.TopToBottom ? parent.width : Math.max(parent.width, implicitWidth)
        height: flow === Flow.TopToBottom ? Math.max(parent.height, implicitHeight) : parent.height
        spacing: tokens.space(8)
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height

        Repeater {
          model: root.workspaceIds()
          delegate: Item {
            required property int modelData
            width: workspaceFlow.flow === Flow.TopToBottom ? workspaceFlow.width : Math.max(tokens.space(92), workspaceButton.implicitWidth)
            height: tokens.target(44)
            property bool occupied: root.workspaceOccupied(modelData)

            ActionButton {
              id: workspaceButton
              anchors.fill: parent
              compact: true
              minimumWidth: tokens.space(92)
              minimumHeight: tokens.target(44)
              text: root.service.tr("workspace", "Workspace") + " " + modelData
              subtitle: (occupied ? "● " : "○ ") + (root.selectedWorkspace === modelData ? root.service.tr("current", "Current") : root.service.tr("available", "Available"))
              checked: root.selectedWorkspace === modelData
              onClicked: { root.selectedWorkspace = modelData; root.service.dispatch(Workspaces.focusCommand(modelData)); root.service.recordInput("mouse") }
            }

            DropArea {
              anchors.fill: parent
              keys: ["omanome-window"]
              onDropped: if (root.draggedWindow) root.moveWindow(root.draggedWindow, modelData)
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: tokens.space(7)
      visible: String(search.text || "").trim() === ""
      Text { text: root.service.tr("dock", "Dock"); color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: root.groupEntries
        delegate: ActionButton {
          required property var modelData
          visible: modelData.persistent === true
          compact: true
          icon: modelData.type === "app-pair" ? "◇" : "⧉"
          text: modelData.name
          subtitle: String(modelData.layout && modelData.layout.ratio || "")
          accessibleName: modelData.name + " · " + root.service.tr("windowGroup", "Window group")
          onClicked: modelData.type === "app-pair" ? root.service.launchAppPair(modelData.id, {}) : root.service.recordInput("touch")
        }
      }
      Repeater {
        model: root.dockApps()
        delegate: ActionButton {
          required property string modelData
          compact: true
          minimumWidth: tokens.target(44)
          icon: "●"
          text: modelData
          onClicked: root.service.launchApp(modelData)
        }
      }
      Item { Layout.fillWidth: true }
      ActionButton { compact: true; text: root.service.tr("apps", "Apps"); icon: "⌘"; onClicked: if (root.panel) root.panel.activeView = "launcher" }
      ActionButton { compact: true; text: root.service.tr("forceQuit", "Force quit"); icon: "×"; onClicked: { root.service.forceQuitBegin(); if (root.panel) root.panel.activeView = "forcequit" } }
    }

    Flickable {
      id: resultScroller
      visible: String(search.text || "").trim() !== ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: width
      contentHeight: resultColumn.implicitHeight

      Column {
        id: resultColumn
        width: resultScroller.width
        spacing: tokens.space(8)
        Repeater {
          model: root.searchResults
          delegate: ActionButton {
            required property var modelData
            width: resultColumn.width
            minimumHeight: tokens.target(48)
            checked: index === root.selectedSearchIndex
            icon: modelData.kind === "app" ? "▣" : (modelData.kind === "window" ? "▤" : (modelData.kind === "action" ? "⚡" : "⚙"))
            text: modelData.title
            subtitle: modelData.kind.toUpperCase() + " · " + modelData.subtitle
            onClicked: root.activateSearch(modelData)
          }
        }
        Text {
          visible: root.searchResults.length === 0
          width: parent.width
          text: root.service.tr("noSearchResults", "No matching apps, windows, settings or actions")
          color: Color.muted
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }
      }
  }

  Timer {
    id: searchDebounce
    interval: 120
    repeat: false
    onTriggered: root.refreshSearch()
  }

  Item {
      id: windowArea
      visible: String(search.text || "").trim() === ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      Repeater {
        model: root.windowRows(root.selectedWorkspace)
        delegate: Item {
          id: windowCard
          required property var modelData
          required property int index
          property var layoutRect: (WindowLayout.rects(root.windowRows(root.selectedWorkspace), windowArea.width, windowArea.height, tokens.space(14))[index] || ({ x: 0, y: 0, width: windowArea.width, height: windowArea.height }))
          property var captureSource: root.foreign(modelData)
          property var application: root.appEntry(modelData)
          property string previewKey: "overview:" + String(modelData && (modelData.address || modelData.title) || index)
          property bool previewWanted: root.service && root.service.previewBudgetAllows("overview", index) && captureSource && typeof captureSource.activate === "function"
          property bool snapMenuOpen: false
          property var snapZones: root.service ? root.service.snapZonesForWindow(modelData, root.service.lastInput, {}) : []
          property bool splitSelected: root.splitSelection.length > 0 && root.service && root.service.multitaskingWindowIdentity(root.splitSelection[0]) === root.service.multitaskingWindowIdentity(modelData)
          x: layoutRect.x
          y: layoutRect.y
          width: layoutRect.width
          height: layoutRect.height
          Drag.active: cardDrag.active
          Drag.source: windowCard
          Drag.keys: ["omanome-window", "omanome-window-slot"]

          Surface {
            anchors.fill: parent
            surfaceRadius: tokens.radius(16)
            surfaceColor: modelData && modelData.activated ? Color.accent : Color.menu.background
            surfaceOpacity: modelData && modelData.activated ? 0.20 : (tokens.reduceTransparency ? 0.98 : 0.90)

            Column {
              anchors.fill: parent
              anchors.margins: tokens.space(12)
              spacing: tokens.space(7)

              Row {
                width: parent.width
                spacing: tokens.space(8)
                Image {
                  width: tokens.space(28)
                  height: width
                  source: windowCard.application ? root.service.iconPath(windowCard.application.icon) : root.service.iconPath("application-x-executable")
                  sourceSize.width: width * 2
                  sourceSize.height: height * 2
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                }
                Column {
                  width: parent.width - tokens.space(76)
                  Text { width: parent.width; text: root.appId(modelData); color: Color.accent; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  Text { width: parent.width; text: root.title(modelData); color: Color.foreground; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                }
                ActionButton {
                  compact: true
                  minimumWidth: tokens.target(44)
                  minimumHeight: tokens.target(44)
                  text: "×"
                  onClicked: root.closeWindow(modelData)
                }
              }

              Item {
                width: parent.width
                height: Math.max(tokens.space(48), parent.height - tokens.space(132))
                clip: true
                Rectangle { anchors.fill: parent; radius: tokens.radius(8); color: Util.alpha(Color.foreground, tokens.highContrast ? 0.10 : 0.05) }
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
                Image {
                  anchors.centerIn: parent
                  visible: !previewView.hasContent
                  width: Math.min(tokens.space(64), parent.width * 0.24)
                  height: width
                  source: windowCard.application ? root.service.iconPath(windowCard.application.icon) : root.service.iconPath("application-x-executable")
                  sourceSize.width: width * 2
                  sourceSize.height: height * 2
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                }
                Text {
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottomMargin: tokens.space(5)
                  text: previewView.hasContent ? root.service.tr("livePreview", "Live preview") : root.service.tr("metadataFallback", "Metadata fallback")
                  color: Color.muted
                  font.pixelSize: Style.font.caption
                }
                Component.onDestruction: if (root.service) root.service.reportLivePreview(windowCard.previewKey, false)
              }

              Text { text: root.service.tr("workspaceNumber", "Workspace") + " " + root.workspaceId(modelData); color: Color.muted; font.pixelSize: Style.font.caption }
              Row {
                spacing: tokens.space(5)
                ActionButton { compact: true; minimumWidth: tokens.target(42); text: "↗"; onClicked: root.activateWindow(modelData) }
                ActionButton { compact: true; minimumWidth: tokens.target(42); text: "—"; onClicked: root.minimizeWindow(modelData) }
                ActionButton { compact: true; minimumWidth: tokens.target(42); text: "□"; onClicked: root.maximizeWindow(modelData) }
                ActionButton { compact: true; minimumWidth: tokens.target(42); text: "⛶"; onClicked: root.fullscreenWindow(modelData) }
                ActionButton { compact: true; minimumWidth: tokens.target(42); text: "⌗"; checked: windowCard.snapMenuOpen; onClicked: windowCard.snapMenuOpen = !windowCard.snapMenuOpen }
                ActionButton { compact: true; minimumWidth: tokens.target(42); text: "⧉"; checked: windowCard.splitSelected; onClicked: root.splitWindow(modelData) }
              }

              Rectangle {
                visible: windowCard.snapMenuOpen
                width: parent.width
                height: Math.max(tokens.target(48), Math.ceil(windowCard.snapZones.length / 3) * tokens.target(42))
                radius: tokens.radius(10)
                color: Util.alpha(Color.foreground, tokens.highContrast ? 0.10 : 0.05)
                Flow {
                  anchors.fill: parent
                  anchors.margins: tokens.space(5)
                  spacing: tokens.space(4)
                  Repeater {
                    model: windowCard.snapZones
                    delegate: ActionButton {
                      required property var modelData
                      compact: true
                      minimumHeight: tokens.target(36)
                      text: String(modelData.id || "snap")
                      onClicked: { root.service.snapWindowToZone(windowCard.modelData, modelData.id, root.service.lastInput, {}); windowCard.snapMenuOpen = false }
                    }
                  }
                }
              }
            }

            MouseArea {
              id: cardDrag
              anchors.fill: parent
              z: -1
              acceptedButtons: Qt.LeftButton
              drag.target: windowCard
              drag.threshold: tokens.space(10)
              onPressed: { root.draggedWindow = modelData; root.service.recordInput("mouse") }
              onClicked: root.activateWindow(modelData)
              onPositionChanged: if (drag.active) root.windowDragActive = true
              onPressAndHold: { root.draggedWindow = modelData; root.windowDragActive = true }
              onReleased: {
                windowCard.x = windowCard.layoutRect.x
                windowCard.y = windowCard.layoutRect.y
                root.draggedWindow = null
                root.windowDragActive = false
              }
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.windowRows(root.selectedWorkspace).length === 0
        text: root.service.tr("noWindows", "No windows on this workspace")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }

  Rectangle {
    id: snapDropOverlay
    anchors.fill: parent
    z: 40
    visible: root.windowDragActive && root.draggedWindow !== null
    color: Util.alpha(Color.menu.scrim, 0.42)

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - tokens.space(32), tokens.space(680))
      spacing: tokens.space(10)

      Text {
        width: parent.width
        text: root.service.tr("snapDropTitle", "Drop window into a layout")
        color: Color.foreground
        font.pixelSize: Style.font.body
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      Flow {
        width: parent.width
        spacing: tokens.space(6)
        Repeater {
          model: root.service ? root.service.snapZonesForTarget(root.draggedWindow, root.dragInputKind(), {}) : []
          delegate: Item {
            required property var modelData
            width: Math.min(tokens.space(150), Math.max(tokens.space(104), (parent ? parent.width : tokens.space(104)) / 4 - tokens.space(6)))
            height: tokens.target(48)

            DropArea {
              anchors.fill: parent
              keys: ["omanome-window", "omanome-window-slot"]
              onDropped: root.commitWindowDrop(modelData.id)
            }
            ActionButton {
              anchors.fill: parent
              compact: true
              minimumHeight: tokens.target(48)
              text: String(modelData.id || "snap")
              accessibleName: root.service.tr(String(modelData.labelKey || "snap.custom"), String(modelData.id || "Snap zone"))
              onClicked: root.commitWindowDrop(modelData.id)
            }
          }
        }
      }

      ActionButton {
        anchors.horizontalCenter: parent.horizontalCenter
        compact: true
        text: root.service.tr("cancel", "Cancel")
        onClicked: { root.draggedWindow = null; root.windowDragActive = false }
      }
    }
  }
}
