import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Optional extension of the existing Omarchy bar. This is intentionally a
// bar-widget, never a replacement bar. The host owns layout, theme, spacing,
// and all other widgets.
BarWidget {
  id: root
  moduleName: "io.omanome.shell"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open(view) {
    var payload = JSON.stringify({ view: String(view || "overview") })
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function") {
      root.bar.shell.toggle(root.moduleName, payload)
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.moduleName, payload])
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "◉" : (root.setting("label", "Omanome"))
    labelVisible: true
    horizontalMargin: root.vertical ? 6 : 8
    verticalPadding: 7
    tooltipText: "Omanome"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.open("quicksettings")
      else if (mouseButton === Qt.MiddleButton) root.open("keyboard")
      else root.open("overview")
    }
  }
}
