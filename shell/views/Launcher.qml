import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "../components"
import "../models/Apps.js" as Apps
import "../models/Dock.js" as DockModel

Item {
  id: root

  property var service: null
  property var panel: null
  property var entries: []
  property var allApplications: []
  property var categoryList: ["All"]
  property string category: "All"
  property string contextId: ""
  property string contextFolderId: ""
  property string folderNameDraft: ""
  property int selectedIndex: 0
  property var draggedApp: null
  property bool appDragActive: false
  property var pairEntries: []

  function dragInputKind() {
    var kind = String(root.service ? root.service.lastInput : "mouse")
    return ["touch", "stylus"].indexOf(kind) >= 0 ? kind : "mouse"
  }

  function commitAppDrop(zoneId) {
    if (!root.draggedApp || !root.service) return false
    var app = root.draggedApp
    root.draggedApp = null
    root.appDragActive = false
    var result = root.service.launchAppToZone(app.id, zoneId, root.dragInputKind(), {})
    if (result && (result.ok === true || result.pending === true) && root.panel) root.panel.close()
    return result
  }

  function refreshPairs() {
    try {
      var groups = root.service && typeof root.service.windowGroupSummaries === "function" ? root.service.windowGroupSummaries() : []
      root.pairEntries = groups.filter(function(item) { return item && item.type === "app-pair" && item.persistent !== false }).slice(0, 12)
    } catch (error) {
      root.pairEntries = []
    }
  }

  function pairIcon(group, index) {
    try {
      var apps = group && Array.isArray(group.apps) ? group.apps : []
      var entry = apps[index] ? Apps.normalize(DesktopEntries.byId(apps[index])) : null
      return root.service.iconPath(entry ? entry.icon : "application-x-executable")
    } catch (error) {
      return root.service.iconPath("application-x-executable")
    }
  }

  function pairLabel(group) {
    var apps = group && Array.isArray(group.apps) ? group.apps : []
    return String(group && group.name || apps.join(" + ") || root.service.tr("appPair", "App Pair"))
  }

  function launchPair(group) {
    if (!group || !root.service || typeof root.service.launchAppPair !== "function") return false
    var result = root.service.launchAppPair(group.id, {})
    if (result && (result.ok === true || result.pending === true) && root.panel) root.panel.close()
    return result
  }
  readonly property var folders: Apps.normalizeFolders(root.service ? root.service.cfg("launcher.folders", []) : [])

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  function favoriteIds() {
    var values = root.service ? root.service.cfg("launcher.favorites", []) : []
    return Array.isArray(values) ? values : []
  }

  function recentIds() {
    var values = root.service ? root.service.cfg("launcher.recentApplications", []) : []
    return Array.isArray(values) ? values : []
  }

  function folderById(id) {
    for (var i = 0; i < root.folders.length; i++) if (root.folders[i].id === String(id)) return root.folders[i]
    return null
  }

  function inCurrentFilter(item) {
    if (root.category === "Favorites") return item.favorite === true
    if (root.category.indexOf("folder:") === 0) return Apps.folderContains(root.folderById(root.category.substring(7)), item.id)
    return Apps.inCategory(item, root.category)
  }

  function refresh() {
    try {
      root.allApplications = DesktopEntries.applications.values || []
      root.categoryList = ["All", "Favorites"].concat(Apps.categories(root.allApplications))
      var sorted = Apps.sorted(root.allApplications, search.text, 300, root.favoriteIds(), root.recentIds())
      root.entries = sorted.filter(root.inCurrentFilter)
      root.refreshPairs()
    } catch (error) {
      root.allApplications = []
      root.entries = []
      root.pairEntries = []
    }
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, Math.max(0, root.entries.length - 1)))
  }

  function adaptiveColumns() {
    var configured = Math.max(1, Number(root.service.cfg("launcher.gridColumns", 6)))
    var minimum = tokens.touchLike ? tokens.space(148) : tokens.space(124)
    var available = Math.max(1, Math.floor(appGrid.width / Math.max(1, minimum)))
    return Math.max(1, Math.min(10, configured, available))
  }

  function setFavorite(id, enabled) {
    root.service.setListMembership("launcher.favorites", id, enabled)
    root.contextId = ""
    root.refresh()
  }

  function toggleFavorite(id) { root.setFavorite(id, !root.service.isFavoriteApp(id)) }

  function reorderFavorite(id, index) {
    if (!root.service.isFavoriteApp(id)) return
    root.service.setConfig("launcher.favorites", DockModel.reorder(root.favoriteIds(), id, index))
    root.refresh()
  }

  function createFolder() {
    var name = String(root.folderNameDraft || "").trim()
    if (!name) return
    var id = "folder-" + Date.now()
    var next = root.folders.slice()
    next.push({ id: id, name: name, apps: root.contextId ? [root.contextId] : [] })
    root.service.setConfig("launcher.folders", next)
    root.contextFolderId = id
    root.contextId = ""
    root.folderNameDraft = ""
    root.category = "folder:" + id
    root.refresh()
  }

  function addToFolder(folderId, appId) {
    if (!folderId || !appId) return
    root.service.setConfig("launcher.folders", Apps.addToFolder(root.folders, folderId, appId))
    root.contextId = ""
    root.refresh()
  }

  function removeFromFolder(folderId, appId) {
    root.service.setConfig("launcher.folders", Apps.removeFromFolder(root.folders, folderId, appId))
    root.refresh()
  }

  function renameFolder() {
    var folder = root.folderById(root.contextFolderId || root.category.substring(7))
    var name = String(root.folderNameDraft || "").trim()
    if (!folder || !name) return
    root.service.setConfig("launcher.folders", Apps.renameFolder(root.folders, folder.id, name))
    root.folderNameDraft = ""
    root.refresh()
  }

  function deleteFolder() {
    var folder = root.folderById(root.contextFolderId || root.category.substring(7))
    if (!folder) return
    root.service.setConfig("launcher.folders", Apps.deleteFolder(root.folders, folder.id))
    root.contextFolderId = ""
    root.category = "All"
    root.refresh()
  }

  function launch(entry) {
    if (!entry) return
    root.service.launchApp(entry.id)
    if (root.panel) root.panel.close()
  }

  function openContext(id) {
    root.contextId = String(id || "")
    root.contextFolderId = ""
    root.folderNameDraft = ""
    root.service.recordInput("touch")
  }

  function openFolderContext(id) {
    root.contextFolderId = String(id || "")
    root.contextId = ""
    root.folderNameDraft = ""
  }

  function currentEntry() { return root.entries.length > 0 ? root.entries[root.selectedIndex] : null }

  Component.onCompleted: root.refresh()

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refresh() }
  }

  Connections {
    target: root.service
    function onConfigUpdated(path) { if (String(path || "").indexOf("multitasking.") === 0) root.refreshPairs() }
  }

  Timer {
    id: searchDebounce
    interval: 120
    repeat: false
    onTriggered: root.refresh()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(22)
    spacing: tokens.space(12)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("launcher", "Apps")
      subtitle: root.service.tr("launcherHint", "Adaptive app grid · favorites are shared with Dock · drag to reorder or folder")
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(48)
      radius: tokens.radius(14)
      color: Util.alpha(Color.foreground, tokens.highContrast ? 0.14 : 0.08)
      border.width: search.activeFocus ? 1 : 0
      border.color: Color.accent

      Text {
        anchors.left: parent.left
        anchors.leftMargin: tokens.space(16)
        anchors.verticalCenter: parent.verticalCenter
        text: "⌕"
        color: Color.muted
        font.pixelSize: Style.font.title
      }
      TextInput {
        id: search
        anchors.left: parent.left
        anchors.leftMargin: tokens.space(48)
        anchors.right: parent.right
        anchors.rightMargin: tokens.space(16)
        anchors.verticalCenter: parent.verticalCenter
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        clip: true
        focus: true
        placeholderText: root.service.tr("searchApps", "Search applications")
        onTextChanged: { root.selectedIndex = 0; searchDebounce.restart() }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.currentEntry())
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectedIndex = Math.min(root.entries.length - 1, root.selectedIndex + 1)
            appGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
            appGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape && root.panel) {
            root.panel.close()
            event.accepted = true
          }
        }
      }
    }

    Flickable {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(42)
      contentWidth: folderRow.width
      clip: true
      Row {
        id: folderRow
        spacing: tokens.space(6)
        Repeater {
          model: root.folders
          delegate: ActionButton {
            required property var modelData
            compact: true
            text: "▰ " + modelData.name
            checked: root.category === "folder:" + modelData.id
            onClicked: root.category = "folder:" + modelData.id
            onPressAndHold: root.openFolderContext(modelData.id)
          }
        }
        ActionButton {
          compact: true
          text: root.service.tr("newFolder", "New folder")
          icon: "+"
          onClicked: { root.contextId = root.currentEntry() ? root.currentEntry().id : ""; root.contextFolderId = ""; root.folderNameDraft = "" }
        }
      }
    }

    Flickable {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(38)
      contentWidth: categoryRow.width
      clip: true
      Row {
        id: categoryRow
        spacing: tokens.space(6)
        Repeater {
          model: root.categoryList
          delegate: ActionButton {
            required property string modelData
            compact: true
            text: modelData === "Favorites" ? "★ " + root.service.tr("favorites", "Favorites") : modelData
            checked: root.category === modelData
            onClicked: { root.category = modelData; root.selectedIndex = 0; root.refresh() }
          }
        }
      }
    }

    Flickable {
      Layout.fillWidth: true
      Layout.preferredHeight: root.pairEntries.length > 0 ? tokens.space(108) : 0
      visible: root.pairEntries.length > 0
      contentWidth: pairColumn.width
      clip: true

      Column {
        id: pairColumn
        spacing: tokens.space(6)

        Text {
          text: root.service.tr("appPairs", "App Pairs")
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Row {
          spacing: tokens.space(8)

          Repeater {
            model: root.pairEntries
            delegate: Item {
              required property var modelData
              width: tokens.space(220)
              height: tokens.target(76)

              Accessible.name: root.pairLabel(modelData)
              Accessible.description: root.service.tr("appPairHint", "Launch both applications and restore their split layout")
              Accessible.role: Accessible.Button

              Surface {
                anchors.fill: parent
                surfaceRadius: tokens.radius(14)
                surfaceColor: Color.menu.background
                surfaceOpacity: tokens.reduceTransparency ? 0.98 : 0.86

                Row {
                  anchors.fill: parent
                  anchors.margins: tokens.space(10)
                  spacing: tokens.space(8)

                  Row {
                    width: tokens.space(52)
                    height: tokens.space(42)
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                      width: tokens.space(34)
                      height: width
                      source: root.pairIcon(modelData, 0)
                      sourceSize.width: width * 2
                      sourceSize.height: height * 2
                      asynchronous: true
                      fillMode: Image.PreserveAspectFit
                    }
                    Image {
                      width: tokens.space(34)
                      height: width
                      x: tokens.space(18)
                      y: tokens.space(8)
                      source: root.pairIcon(modelData, 1)
                      sourceSize.width: width * 2
                      sourceSize.height: height * 2
                      asynchronous: true
                      fillMode: Image.PreserveAspectFit
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - tokens.space(60)
                    spacing: 2

                    Text {
                      width: parent.width
                      text: root.pairLabel(modelData)
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: String(modelData.layout && modelData.layout.ratio || "50/50") + " · " + root.service.tr("appPairHintShort", "restore split")
                      color: Color.muted
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  onPressed: root.service.recordInput("touch")
                  onClicked: root.launchPair(modelData)
                }
              }
            }
          }
        }
      }
    }

    GridView {
      id: appGrid
      Layout.fillWidth: true
      Layout.fillHeight: true
      cellWidth: Math.max(tokens.target(112), Math.floor(width / root.adaptiveColumns()))
      cellHeight: tokens.space(tokens.touchLike ? 164 : 150)
      clip: true
      model: root.entries
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (root.selectedIndex !== currentIndex) root.selectedIndex = currentIndex

      delegate: Item {
        id: appCard
        required property var modelData
        required property int index
        property bool isFavorite: root.service.isFavoriteApp(modelData.id)
        width: appGrid.cellWidth - tokens.space(8)
        height: appGrid.cellHeight - tokens.space(8)
        Drag.active: appDrag.active
        Drag.source: appCard
        Drag.keys: ["omanome-app", "omanome-app-slot"]

        Surface {
          anchors.fill: parent
          surfaceRadius: tokens.radius(16)
          surfaceColor: index === root.selectedIndex ? Color.accent : Color.menu.background
          surfaceOpacity: index === root.selectedIndex ? 0.20 : (tokens.reduceTransparency ? 0.98 : 0.82)

          Column {
            anchors.fill: parent
            anchors.margins: tokens.space(12)
            spacing: tokens.space(7)
            Image {
              width: Math.min(tokens.space(tokens.touchLike ? 64 : 54), parent.width * 0.52)
              height: width
              anchors.horizontalCenter: parent.horizontalCenter
              source: root.service.iconPath(modelData.icon)
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              asynchronous: true
              fillMode: Image.PreserveAspectFit
            }
            Text {
              width: parent.width
              text: modelData.name
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: appCard.isFavorite ? "★  " + root.service.tr("favorite", "Favorite") : modelData.comment
              color: appCard.isFavorite ? Color.accent : Color.muted
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              visible: text !== ""
            }
          }

          MouseArea {
            id: appDrag
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            drag.target: appCard
            drag.threshold: tokens.space(8)
            onPressed: { root.selectedIndex = index; root.service.recordInput("mouse") }
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) root.openContext(modelData.id)
              else if (!root.appDragActive) root.launch(modelData)
            }
            onPositionChanged: if (drag.active) { root.draggedApp = modelData; root.appDragActive = true }
            onPressAndHold: { root.draggedApp = modelData; root.appDragActive = true }
            onReleased: { appCard.x = 0; appCard.y = 0; if (root.draggedApp === modelData) { root.draggedApp = null; root.appDragActive = false } }
          }

          DropArea {
            anchors.fill: parent
            keys: ["omanome-app"]
            onDropped: {
              if (!drop.source || !drop.source.modelData) return
              if (root.service.isFavoriteApp(drop.source.modelData.id) && appCard.isFavorite)
                root.reorderFavorite(drop.source.modelData.id, index)
              if (root.category.indexOf("folder:") === 0)
                root.addToFolder(root.category.substring(7), drop.source.modelData.id)
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.entries.length === 0
        text: root.service.tr("noApps", "No applications found")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }

  Rectangle {
    visible: root.contextId !== "" || root.contextFolderId !== ""
    anchors.centerIn: parent
    z: 30
    width: Math.min(parent.width - tokens.space(32), tokens.space(360))
    height: contextColumn.implicitHeight + tokens.space(24)
    radius: tokens.radius(16)
    color: Color.menu.background
    border.width: 1
    border.color: Color.menu.border

    Column {
      id: contextColumn
      anchors.fill: parent
      anchors.margins: tokens.space(12)
      spacing: tokens.space(6)
      Text { width: parent.width; text: root.contextId || (root.folderById(root.contextFolderId) || {}).name || root.service.tr("folder", "Folder"); color: Color.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
      ActionButton { width: parent.width; text: root.contextId && root.service.isFavoriteApp(root.contextId) ? root.service.tr("removeFavorite", "Remove from favorites") : root.service.tr("addFavorite", "Add to favorites"); visible: root.contextId !== ""; onClicked: root.toggleFavorite(root.contextId) }
      ActionButton { width: parent.width; text: root.service.tr("open", "Open"); visible: root.contextId !== ""; onClicked: { var app = Apps.normalize(DesktopEntries.byId(root.contextId)); root.launch(app) } }
      ActionButton { width: parent.width; text: root.service.tr("newWindow", "New window"); visible: root.contextId !== ""; onClicked: { root.service.launchApp(root.contextId); root.contextId = "" } }
      ActionButton { width: parent.width; text: root.service.tr("splitWithActive", "Split with active window"); visible: root.contextId !== ""; usable: root.service.hasWindowsForApp(root.contextId); onClicked: { root.service.splitAppWithActiveWindow(root.contextId); root.contextId = "" } }
      ActionButton { width: parent.width; text: root.service.tr("closeAllWindows", "Close all windows"); visible: root.contextId !== ""; usable: root.service.hasWindowsForApp(root.contextId); onClicked: { root.service.closeWindowsForApp(root.contextId); root.contextId = "" } }
      Text { visible: root.contextId !== ""; text: root.service.tr("addToFolder", "Add to folder"); color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: root.folders
        delegate: ActionButton {
          required property var modelData
          width: parent.width
          compact: true
          text: Apps.folderContains(modelData, root.contextId) ? "✓ " + modelData.name : "+ " + modelData.name
          visible: root.contextId !== ""
          onClicked: Apps.folderContains(modelData, root.contextId) ? root.removeFromFolder(modelData.id, root.contextId) : root.addToFolder(modelData.id, root.contextId)
        }
      }
      TextInput {
        width: parent.width
        height: tokens.target(40)
        visible: root.contextId !== "" || root.contextFolderId !== ""
        text: root.folderNameDraft
        color: Color.foreground
        font.pixelSize: Style.font.body
        clip: true
        onTextChanged: root.folderNameDraft = text
        Rectangle { anchors.fill: parent; z: -1; radius: tokens.radius(8); color: Util.alpha(Color.foreground, 0.07) }
      }
      ActionButton { width: parent.width; text: root.contextFolderId !== "" ? root.service.tr("renameFolder", "Rename folder") : root.service.tr("createFolder", "Create folder"); visible: root.contextId !== "" || root.contextFolderId !== ""; onClicked: root.contextFolderId !== "" ? root.renameFolder() : root.createFolder() }
      ActionButton { width: parent.width; text: root.service.tr("deleteFolder", "Delete folder"); visible: root.contextFolderId !== ""; onClicked: root.deleteFolder() }
      ActionButton { width: parent.width; text: root.service.tr("close", "Close"); onClicked: { root.contextId = ""; root.contextFolderId = "" } }
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
      width: Math.min(parent.width - tokens.space(32), tokens.space(680))
      spacing: tokens.space(10)

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
        spacing: tokens.space(6)
        Repeater {
          model: root.service ? root.service.snapZonesForTarget(null, root.dragInputKind(), {}) : []
          delegate: Item {
            required property var modelData
            width: Math.min(tokens.space(150), Math.max(tokens.space(104), (parent ? parent.width : tokens.space(104)) / 4 - tokens.space(6)))
            height: tokens.target(48)

            DropArea {
              anchors.fill: parent
              keys: ["omanome-app", "omanome-app-slot"]
              onDropped: root.commitAppDrop(modelData.id)
            }
            ActionButton {
              anchors.fill: parent
              compact: true
              minimumHeight: tokens.target(48)
              text: String(modelData.id || "snap")
              accessibleName: root.service.tr(String(modelData.labelKey || "snap.custom"), String(modelData.id || "Snap zone"))
              onClicked: root.commitAppDrop(modelData.id)
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
