import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

Item {
  id: root

  property var service: null
  property var panel: null
  property var backend: null
  property int revision: 0

  function refresh() {
    root.backend = root.service ? root.service.notificationService : null
    root.revision++
  }

  Component.onCompleted: root.refresh()

  Timer {
    interval: 2500
    repeat: true
    running: root.visible
    onTriggered: root.refresh()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(14)

    SectionHeader {
      Layout.fillWidth: true
      title: root.service.tr("notificationCenter", "Notification center")
      subtitle: root.service.tr("standardNotificationService", "Using Omarchy's native notification service")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("doNotDisturb", "Do not disturb")
        icon: "◌"
        checked: root.backend ? root.backend.doNotDisturb : false
        onClicked: if (root.backend && typeof root.backend.setDoNotDisturb === "function") root.backend.setDoNotDisturb(!root.backend.doNotDisturb)
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("showHistory", "Show history")
        onClicked: if (root.backend && typeof root.backend.showRecentHistory === "function") root.backend.showRecentHistory()
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("dismissAll", "Dismiss all")
        onClicked: if (root.backend && typeof root.backend.clearPopups === "function") root.backend.clearPopups()
      }
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(8)
      model: root.backend ? root.backend.popupModel : null

      delegate: Surface {
        required property int index
        required property string app
        required property string summary
        required property string body
        width: ListView.view.width
        height: Math.max(Style.space(76), content.implicitHeight + Style.space(24))
        surfaceColor: Color.menu.background
        surfaceOpacity: 0.88

        Column {
          id: content
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(4)
          Text { text: app + (app !== "" ? " · " : "") + summary; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; width: parent.width }
          Text { text: body; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; width: parent.width; maximumLineCount: 3; elide: Text.ElideRight }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton && root.backend && typeof root.backend.dismissPopup === "function") root.backend.dismissPopup(index)
            else if (root.backend && typeof root.backend.invokePopupDefault === "function") root.backend.invokePopupDefault(index)
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: !root.backend || root.backend.popupModel.count === 0
        text: root.service.tr("noNotifications", "No recent notifications")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }
}
