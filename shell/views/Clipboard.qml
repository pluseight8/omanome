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
    if (!root.service) return
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
    spacing: Style.space(12)

    RowLayout {
      Layout.fillWidth: true
      Text {
        text: root.service.tr("clipboard", "Clipboard")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        Layout.leftMargin: Style.space(8)
        text: root.service.clipboardHistory.length + " / " + root.service.cfg("clipboard.historyLimit", 100)
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      Item { Layout.fillWidth: true }
      ActionButton {
        compact: true
        text: "Clear unpinned"
        usable: root.service.clipboardHistory.length > 0
        onClicked: root.service.clearClipboardUnpinned()
      }
      ActionButton {
        compact: true
        text: root.service.tr("delete", "Clear")
        usable: root.service.clipboardHistory.length > 0
        onClicked: root.service.clearClipboard()
      }
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
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        visible: search.text === ""
        text: "⌕  " + root.service.tr("search", "Search")
        color: Color.muted
        font.pixelSize: Style.font.body
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
        property bool editing: false
        property bool editingTags: false
        width: list.width
        height: modelData.item.type === "image" ? Style.space(118) : Style.space(146)
        surfaceColor: Color.menu.background
        surfaceOpacity: 0.82

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)

          Image {
            Layout.preferredWidth: Style.space(72)
            Layout.preferredHeight: Style.space(72)
            visible: card.modelData.item.type === "image"
            source: visible ? Util.fileUrl(card.modelData.item.path) : ""
            fillMode: Image.PreserveAspectFit
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Text {
              Layout.fillWidth: true
              visible: !card.editing
              text: ClipboardModel.preview(card.modelData.item, 220)
              color: Color.foreground
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              maximumLineCount: 3
              wrapMode: Text.Wrap
            }
            TextInput {
              id: editor
              Layout.fillWidth: true
              visible: card.editing && card.modelData.item.type === "text"
              text: visible ? card.modelData.item.text : ""
              color: Color.foreground
              font.pixelSize: Style.font.caption
              clip: true
              onAccepted: { root.service.editClipboardText(card.modelData.index, text); card.editing = false }
            }
            Text {
              Layout.fillWidth: true
              visible: !card.editingTags
              text: card.modelData.item.tags.length > 0 ? "#" + card.modelData.item.tags.join("  #") : ""
              color: Color.accent
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            TextInput {
              id: tagsEditor
              Layout.fillWidth: true
              visible: card.editingTags
              text: visible ? card.modelData.item.tags.join(", ") : ""
              placeholderText: "tags, comma separated"
              color: Color.accent
              font.pixelSize: Style.font.caption
              onAccepted: { root.service.setClipboardTags(card.modelData.index, text); card.editingTags = false }
            }
            Text {
              Layout.fillWidth: true
              text: (card.modelData.item.sourceApp ? card.modelData.item.sourceApp + " · " : "") + (card.modelData.item.pinned ? "Pinned" : "")
              color: Color.muted
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          ColumnLayout {
            spacing: Style.space(5)
            ActionButton {
              compact: true
              minimumWidth: Style.space(62)
              text: card.modelData.item.pinned ? "★" : "☆"
              usable: root.service.cfg("clipboard.pinning", true)
              onClicked: root.service.toggleClipboardPin(card.modelData.index)
            }
            ActionButton {
              compact: true
              minimumWidth: Style.space(62)
              text: card.editing ? "Save" : "Edit"
              usable: card.modelData.item.type === "text"
              onClicked: {
                if (card.editing) { root.service.editClipboardText(card.modelData.index, editor.text); card.editing = false }
                else { card.editing = true; editor.forceActiveFocus() }
              }
            }
            ActionButton {
              compact: true
              minimumWidth: Style.space(62)
              text: card.editingTags ? "Save tags" : "Tags"
              usable: root.service.cfg("clipboard.tags", true)
              onClicked: {
                if (card.editingTags) { root.service.setClipboardTags(card.modelData.index, tagsEditor.text); card.editingTags = false }
                else { card.editingTags = true; tagsEditor.forceActiveFocus() }
              }
            }
            ActionButton {
              compact: true
              minimumWidth: Style.space(62)
              text: "×"
              onClicked: root.service.removeClipboard(card.modelData.index)
            }
          }

          ColumnLayout {
            spacing: Style.space(5)
            ActionButton {
              compact: true
              minimumWidth: Style.space(62)
              text: root.service.tr("copy", "Copy")
              usable: card.modelData.item.type === "text"
              onClicked: root.service.copyClipboard(card.modelData.index)
            }
            ActionButton {
              compact: true
              minimumWidth: Style.space(62)
              text: root.service.tr("paste", "Paste")
              usable: card.modelData.item.type === "text"
              onClicked: root.service.pasteClipboard(card.modelData.index)
            }
          }
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
