import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../models/Notifications.js" as NotificationsModel

Item {
  id: root
  property var service: null
  property var panel: null
  property var backend: null
  property var rows: []
  property int revision: 0

  function refresh() {
    root.backend = root.service ? root.service.notificationService : null
    root.rows = NotificationsModel.rows(root.backend, root.service ? root.service.cfg("notifications", {}) : {}, Date.now())
    root.revision++
  }

  function dismissGroup(row) {
    if (!root.backend || typeof root.backend.dismissPopup !== "function") return
    var indices = NotificationsModel.sortDescending(row.indices)
    for (var i = 0; i < indices.length; i++) root.backend.dismissPopup(indices[i])
    root.refresh()
  }

  function invokeGroup(row) {
    if (root.backend && typeof root.backend.invokePopupDefault === "function") root.backend.invokePopupDefault(row.latestIndex)
    root.refresh()
  }

  function muteGroup(row) {
    if (root.service) root.service.toggleNotificationMute(row.app)
    root.refresh()
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: root.service
    function onStateUpdated() { root.refresh() }
  }

  Connections {
    target: root.backend ? root.backend.popupModel : null
    function onCountChanged() { root.refresh() }
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.visible
    onTriggered: root.refresh()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(12)

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
        usable: !!root.backend
        onClicked: if (root.backend) root.service.setDoNotDisturb(!root.backend.doNotDisturb)
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("showHistory", "Show history")
        usable: !!root.backend && typeof root.backend.showRecentHistory === "function"
        onClicked: { if (root.backend) root.backend.showRecentHistory(); root.refresh() }
      }
      ActionButton {
        Layout.fillWidth: true
        text: root.service.tr("dismissAll", "Dismiss all")
        usable: !!root.backend && typeof root.backend.clearPopups === "function"
        onClicked: { if (root.backend) root.backend.clearPopups(); root.refresh() }
      }
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(8)
      model: root.rows

      delegate: Surface {
        id: card
        required property var modelData
        width: list.width
        height: Math.max(Style.space(96), content.implicitHeight + Style.space(28))
        surfaceColor: Color.menu.background
        surfaceOpacity: 0.88

        DragHandler {
          id: swipe
          target: null
          onActiveChanged: {
            if (!active && Math.abs(translation.x) >= Style.space(64)) root.dismissGroup(card.modelData)
          }
        }

        ColumnLayout {
          id: content
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(5)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: card.modelData.app + (card.modelData.count > 1 ? " · " + card.modelData.count : "")
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              visible: card.modelData.time !== ""
              text: card.modelData.time
              color: Color.muted
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            Layout.fillWidth: true
            text: card.modelData.summary
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            visible: card.modelData.body !== ""
            text: card.modelData.body
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)
            ActionButton {
              compact: true
              text: "Open"
              usable: card.modelData.hasActions && root.backend && typeof root.backend.invokePopupDefault === "function"
              onClicked: root.invokeGroup(card.modelData)
            }
            ActionButton {
              compact: true
              text: "Mute app"
              onClicked: root.muteGroup(card.modelData)
            }
            ActionButton {
              compact: true
              text: card.modelData.count > 1 ? "Clear group" : "Dismiss"
              usable: !!root.backend && typeof root.backend.dismissPopup === "function"
              onClicked: root.dismissGroup(card.modelData)
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        text: root.service.tr("noNotifications", "No recent notifications")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }
}
