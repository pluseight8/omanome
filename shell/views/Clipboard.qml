import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"
import "../models/Clipboard.js" as ClipboardModel

Item {
  id: root
  property var service: null
  property var panel: null
  property var rows: []

  function refresh() {
    root.rows = ClipboardModel.filtered(root.service.clipboardHistory, search.text)
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: root.service
    function onStateUpdated() { root.refresh() }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(22)
    spacing: Style.space(14)

    RowLayout {
      Layout.fillWidth: true
      Text {
        text: root.service.tr("clipboard", "Clipboard")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Item { Layout.fillWidth: true }
      Text {
        text: root.service.cfg("clipboard.privateMode", false) || root.service.cfg("privacy.clipboardPrivate", false) ? root.service.tr("privateMode", "Private mode") : root.rows.length + " / " + root.service.cfg("clipboard.historyLimit", 100)
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      ActionButton { compact: true; text: root.service.tr("delete", "Clear"); onClicked: root.service.clearClipboard() }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(48)
      radius: Style.space(12)
      color: Util.alpha(Color.foreground, 0.07)
      TextInput {
        id: search
        anchors.fill: parent
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        verticalAlignment: TextInput.AlignVCenter
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        onTextChanged: root.refresh()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape && root.panel) { root.panel.close(); event.accepted = true }
        }
      }
      Text { anchors.left: parent.left; anchors.leftMargin: Style.space(14); anchors.verticalCenter: parent.verticalCenter; visible: search.text === ""; text: "⌕  " + root.service.tr("search", "Search"); color: Color.muted; font.pixelSize: Style.font.body }
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(8)
      model: root.rows

      delegate: Surface {
        required property var modelData
        width: list.width
        height: Style.space(86)
        surfaceColor: Color.menu.background
        surfaceOpacity: 0.82

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)

          Image {
            Layout.preferredWidth: Style.space(62)
            Layout.preferredHeight: Style.space(62)
            visible: modelData.item.type === "image"
            source: visible ? Util.fileUrl(modelData.item.path) : ""
            fillMode: Image.PreserveAspectFit
          }
          Text {
            Layout.fillWidth: true
            text: modelData.item.type === "image" ? modelData.item.mime : modelData.item.text
            color: Color.foreground
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 3
            wrapMode: Text.Wrap
          }
          ActionButton { compact: true; minimumWidth: Style.space(62); text: root.service.tr("copy", "Copy"); onClicked: root.service.copyClipboard(modelData.index) }
          ActionButton { compact: true; minimumWidth: Style.space(62); text: root.service.tr("paste", "Paste"); usable: modelData.item.type === "text"; onClicked: root.service.pasteClipboard(modelData.index) }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        text: root.service.tr("noClipboard", "Clipboard history is empty")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }
}
