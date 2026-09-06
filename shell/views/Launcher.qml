import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "../components"
import "../models/Apps.js" as Apps

Item {
  id: root
  property var service: null
  property var panel: null
  property var entries: []
  property var allApplications: []
  property var categoryList: ["All"]
  property string category: "All"
  property int selectedIndex: 0
  property string contextId: ""

  function favoriteIds() {
    var values = root.service ? root.service.cfg("launcher.favorites", []) : []
    return Array.isArray(values) ? values : []
  }

  function recentIds() {
    var values = root.service ? root.service.cfg("launcher.recentApplications", []) : []
    return Array.isArray(values) ? values : []
  }

  function refresh() {
    try {
      root.allApplications = DesktopEntries.applications.values || []
      root.categoryList = ["All"].concat(Apps.categories(root.allApplications))
      var sorted = Apps.sorted(root.allApplications, search.text, 300, root.favoriteIds(), root.recentIds())
      root.entries = sorted.filter(function(item) { return Apps.inCategory(item, root.category) })
    } catch (error) {
      root.allApplications = []
      root.entries = []
    }
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.entries.length - 1))
  }

  function setFavorite(id, enabled) {
    root.service.setListMembership("launcher.favorites", id, enabled)
    root.contextId = ""
    root.refresh()
  }

  function toggleFavorite(id) {
    root.setFavorite(id, !root.service.isFavoriteApp(id))
  }

  function launch(entry) {
    if (!entry) return
    root.service.launchApp(entry.id)
    if (root.panel) root.panel.close()
  }

  function openContext(id) {
    root.contextId = String(id || "")
    root.service.recordInput("touch")
  }

  function currentEntry() {
    return root.entries.length > 0 ? root.entries[root.selectedIndex] : null
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refresh() }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(12)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("launcher", "Apps")
      subtitle: root.service.tr("search", "Search") + " · Enter to launch · long press or right click for actions"
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(52)
      radius: Style.space(14)
      color: Util.alpha(Color.foreground, 0.08)
      border.width: search.activeFocus ? 1 : 0
      border.color: Color.accent

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        text: "⌕"
        color: Color.muted
        font.pixelSize: Style.font.title
      }
      TextInput {
        id: search
        anchors.left: parent.left
        anchors.leftMargin: Style.space(48)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        clip: true
        focus: true
        onTextChanged: { root.selectedIndex = 0; root.refresh() }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.currentEntry())
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectedIndex = Math.min(root.entries.length - 1, root.selectedIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
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
      Layout.preferredHeight: Style.space(38)
      contentWidth: categoryRow.width
      clip: true
      Row {
        id: categoryRow
        spacing: Style.space(6)
        Repeater {
          model: root.categoryList
          delegate: ActionButton {
            required property string modelData
            compact: true
            text: modelData
            checked: root.category === modelData
            onClicked: { root.category = modelData; root.selectedIndex = 0; root.refresh() }
          }
        }
      }
    }

    GridView {
      id: appGrid
      Layout.fillWidth: true
      Layout.fillHeight: true
      cellWidth: Math.max(Style.space(124), Math.floor(width / Math.max(1, Number(root.service.cfg("launcher.gridColumns", 6)))))
      cellHeight: Style.space(150)
      clip: true
      model: root.entries
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (root.selectedIndex !== currentIndex) root.selectedIndex = currentIndex

      delegate: Item {
        required property var modelData
        required property int index
        width: appGrid.cellWidth - Style.space(8)
        height: appGrid.cellHeight - Style.space(8)

        Surface {
          anchors.fill: parent
          surfaceRadius: Style.space(16)
          surfaceColor: index === root.selectedIndex ? Color.accent : Color.menu.background
          surfaceOpacity: index === root.selectedIndex ? 0.20 : 0.82

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(7)
            Image {
              width: Style.space(54)
              height: Style.space(54)
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
              text: root.service.isFavoriteApp(modelData.id) ? "★  " + root.service.tr("favorite", "Favorite") : modelData.comment
              color: root.service.isFavoriteApp(modelData.id) ? Color.accent : Color.muted
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              visible: text !== ""
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onPressed: { root.selectedIndex = index; root.service.recordInput("touch") }
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) root.openContext(modelData.id)
              else root.launch(modelData)
            }
            onPressAndHold: root.openContext(modelData.id)
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
    visible: root.contextId !== ""
    anchors.centerIn: parent
    z: 30
    width: Style.space(280)
    height: contextColumn.implicitHeight + Style.space(24)
    radius: Style.space(16)
    color: Color.menu.background
    border.width: 1
    border.color: Color.menu.border

    Column {
      id: contextColumn
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(6)
      Text { text: root.contextId; width: parent.width; color: Color.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
      ActionButton { width: parent.width; text: root.service.isFavoriteApp(root.contextId) ? root.service.tr("removeFavorite", "Remove from favorites") : root.service.tr("addFavorite", "Add to favorites"); onClicked: root.toggleFavorite(root.contextId) }
      ActionButton { width: parent.width; text: root.service.tr("pinToDock", "Pin to Dock"); onClicked: { root.setFavorite(root.contextId, true) } }
      ActionButton { width: parent.width; text: root.service.tr("open", "Open"); onClicked: { var app = DesktopEntries.byId(root.contextId); root.launch(Apps.normalize(app)) } }
      ActionButton { width: parent.width; text: root.service.tr("appDetailsUnavailable", "App details unavailable"); subtitle: "No portable backend exposed by Omarchy"; usable: false }
      ActionButton { width: parent.width; text: root.service.tr("close", "Close"); onClicked: root.contextId = "" }
    }
  }
}
