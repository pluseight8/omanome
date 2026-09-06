import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Commons
import "../components"

// A touch-friendly window switcher surface.  It uses foreign-toplevel
// objects directly; no screenshot or fake preview is produced.  A future
// compositor preview protocol can replace the card body without changing the
// selection and activation model.
Item {
  id: root

  property var service: null
  property var panel: null
  property var windows: []
  property int selectedIndex: 0

  function refresh() {
    try { root.windows = ToplevelManager.toplevels.values || [] } catch (error) { root.windows = [] }
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))
  }

  function activate(index) {
    var target = root.windows[index]
    if (target && typeof target.activate === "function") target.activate()
    if (root.panel) root.panel.close()
  }

  function move(delta) {
    if (root.windows.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.windows.length) % root.windows.length
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refresh() }
  }
  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.refresh() }
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
      title: root.service.tr("altTab", "Alt-Tab")
      subtitle: "Touch switcher · " + root.service.cfg("altTab.style", "coverflow") + " · native toplevels"
    }

    RowLayout {
      Layout.fillWidth: true
      ActionButton { compact: true; text: "‹"; onClicked: root.move(-1) }
      Text { Layout.fillWidth: true; text: root.windows.length > 0 ? (root.selectedIndex + 1) + " / " + root.windows.length : root.service.tr("noWindows", "No windows found"); color: Color.muted; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.body }
      ActionButton { compact: true; text: "›"; onClicked: root.move(1) }
    }

    ListView {
      id: cards
      Layout.fillWidth: true
      Layout.fillHeight: true
      orientation: ListView.Horizontal
      spacing: Style.space(12)
      clip: true
      model: root.windows
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (root.selectedIndex !== currentIndex) root.selectedIndex = currentIndex

      delegate: Surface {
        required property var modelData
        required property int index
        width: Math.min(cards.width * 0.62, Style.space(420))
        height: Math.min(cards.height - Style.space(24), Style.space(300))
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        surfaceRadius: Style.space(20)
        surfaceColor: index === root.selectedIndex ? Color.accent : Color.menu.background
        surfaceOpacity: index === root.selectedIndex ? 0.24 : 0.88
        scale: index === root.selectedIndex ? 1.0 : 0.92
        rotation: root.windows.length > 1 ? Math.max(-8, Math.min(8, (index - root.selectedIndex) * 4)) : 0

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(10)
          Text { text: modelData ? (modelData.appId || "Window") : "Window"; color: Color.accent; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
          Text { text: modelData ? (modelData.title || modelData.appId || "") : ""; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; wrapMode: Text.WordWrap; maximumLineCount: 3; width: parent.width }
          Item { height: Style.space(12); width: 1 }
          Text { text: "Foreign-toplevel surface"; color: Color.muted; font.pixelSize: Style.font.caption }
          Item { Layout.fillHeight: true }
          ActionButton { width: parent.width; text: root.service.tr("open", "Open"); checked: index === root.selectedIndex; onClicked: root.activate(index) }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          onClicked: { root.selectedIndex = index; root.activate(index) }
          onPressed: root.service.recordInput("touch")
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
      text: "Live previews require a compositor preview protocol; activation remains native and screenshot-free."
      color: Color.muted
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
