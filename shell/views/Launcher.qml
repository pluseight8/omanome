import QtQuick
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

  function refresh() {
    try { root.entries = Apps.sorted(DesktopEntries.applications.values || [], search.text, 200) }
    catch (error) { root.entries = [] }
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refresh() }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(16)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("launcher", "Apps")
      subtitle: root.service.tr("search", "Search") + " · Enter to launch · touch or stylus to open"
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
        onTextChanged: root.refresh()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.entries.length > 0) root.launch(root.entries[0])
            event.accepted = true
          } else if (event.key === Qt.Key_Escape && root.panel) {
            root.panel.close()
            event.accepted = true
          }
        }
      }
    }

    GridView {
      id: appGrid
      Layout.fillWidth: true
      Layout.fillHeight: true
      cellWidth: Math.max(Style.space(124), Math.floor(width / Math.max(1, Number(root.service.cfg("launcher.gridColumns", 6)))))
      cellHeight: Style.space(142)
      clip: true
      model: root.entries

      delegate: Item {
        required property var modelData
        width: appGrid.cellWidth - Style.space(8)
        height: appGrid.cellHeight - Style.space(8)

        Surface {
          anchors.fill: parent
          surfaceRadius: Style.space(16)
          surfaceColor: mouse.containsMouse ? Color.accent : Color.menu.background
          surfaceOpacity: mouse.containsMouse ? 0.16 : 0.82

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(8)

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
              text: modelData.comment
              color: Color.muted
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              visible: text !== ""
            }
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.service.recordInput("touch")
            onClicked: root.launch(modelData)
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

  function launch(entry) {
    if (!entry) return
    root.service.launchApp(entry.id)
    if (root.panel) root.panel.close()
  }
}
