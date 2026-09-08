import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../components"

// Compact Omanome-only controls. It is loaded by the plugin's existing panel
// entry point, so it never creates a replacement bar or a second shell.
Item {
  id: root

  property var service: null
  property var panel: null
  property bool moreOpen: false
  property int observedRevision: service ? service.stateRevision : 0
  readonly property bool contextMenu: root.panel && root.panel.contextMenu === true

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  function text(key, fallback) { return root.service ? root.service.tr(key, fallback) : fallback }
  function feature(id) { return root.service && typeof root.service.featureState === "function" ? root.service.featureState(id) : null }
  function canToggle(row) { return row && row.available === true && root.service && root.service.masterEnabled === true && root.service.suspended !== true && root.service.safeMode !== true }
  function moduleRows() {
    var revision = root.service ? root.service.stateRevision : 0
    root.observedRevision = revision
    var rows = root.service && Array.isArray(root.service.featureStates) ? root.service.featureStates : []
    var order = root.service ? root.service.cfg("controlCenter.moduleOrder", []) : []
    var visible = root.service ? root.service.cfg("controlCenter.visibleModules", []) : []
    var result = []
    var ids = Array.isArray(order) && order.length ? order : rows.map(function(row) { return row.id })
    for (var i = 0; i < ids.length; i++) {
      if (Array.isArray(visible) && visible.length && visible.indexOf(ids[i]) < 0) continue
      var row = feature(ids[i])
      if (row) result.push(row)
    }
    return result
  }
  function profileLabel() {
    var name = root.service ? String(root.service.adaptiveProfile || "auto") : "auto"
    return name.charAt(0).toUpperCase() + name.slice(1)
  }
  function stateSubtitle() {
    if (!root.service) return "Service unavailable"
    if (root.service.safeMode) return "Safe Mode · diagnostic entry remains available"
    if (root.service.suspended) return "Enhancements suspended · core input is unchanged"
    if (!root.service.masterEnabled) return "Enhancements off · Omarchy, bar and native input remain active"
    var summary = root.service.featureStateSummary || {}
    return summary.partial ? String(summary.active || 0) + " of " + String(summary.available || 0) + " enhancements active" : "Enhancements active"
  }
  function toggleRow(row) {
    if (!canToggle(row)) return
    root.service.toggleFeature(row.id)
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(16)
    spacing: tokens.space(10)

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(42)
      Text {
        text: "⌘"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Text { text: root.contextMenu ? root.text("omanomeActions", "Omanome actions") : root.text("controlCenter", "Omanome Control Center"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
        Text { text: root.contextMenu ? root.text("contextActionsHint", "Quick actions and recovery access") : root.stateSubtitle(); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight; Layout.fillWidth: true }
      }
      ActionButton {
        compact: true
        minimumWidth: tokens.target(72)
        text: root.text("close", "Close")
        onClicked: if (root.panel) root.panel.close()
      }
    }

    ColumnLayout {
      visible: root.contextMenu
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: tokens.space(8)

      ActionButton {
        Layout.fillWidth: true
        minimumHeight: tokens.target(54)
        text: root.service && root.service.masterEnabled ? root.text("disableOmanome", "Disable Omanome") : root.text("enableOmanome", "Enable Omanome")
        icon: root.service && root.service.masterEnabled ? "×" : "✓"
        checked: root.service && root.service.masterEnabled === true
        usable: !!root.service
        subtitle: root.service && root.service.masterEnabled ? root.text("enhancementsOn", "Enhancements are on") : root.text("coreInputSafe", "Core Omarchy and native input stay available")
        onClicked: if (root.service) root.service.setMasterEnabled(!root.service.masterEnabled)
      }
      ActionButton {
        Layout.fillWidth: true
        minimumHeight: tokens.target(54)
        text: root.service && root.service.suspended ? root.text("resume", "Resume Omanome") : root.text("suspend", "Suspend Omanome")
        icon: root.service && root.service.suspended ? "▶" : "Ⅱ"
        checked: root.service && root.service.suspended === true
        usable: !!root.service
        subtitle: root.service && root.service.suspended ? root.text("suspendedHint", "Enhancements are paused") : root.text("suspendHint", "Pause enhancements without uninstalling")
        onClicked: if (root.service) root.service.setSuspended(!root.service.suspended)
      }
      ActionButton {
        Layout.fillWidth: true
        minimumHeight: tokens.target(54)
        text: root.text("settings", "Settings")
        icon: "⚙"
        subtitle: root.text("adaptiveSettingsHint", "Open Adaptive Mode and recovery controls")
        onClicked: {
          if (!root.panel) return
          root.panel.contextMenu = false
          root.panel.transientOverlay = false
          root.panel.activeView = "settings"
          root.panel.payloadView = "settings://general"
        }
      }
      Item { Layout.fillHeight: true }
      ActionButton {
        Layout.fillWidth: true
        compact: true
        text: root.text("backToControlCenter", "Back to Control Center")
        icon: "⌃"
        onClicked: if (root.panel) root.panel.contextMenu = false
      }
    }

    ActionButton {
      visible: !root.contextMenu
      Layout.fillWidth: true
      minimumHeight: tokens.target(54)
      text: "Omanome"
      icon: root.service && root.service.masterEnabled ? "✓" : "×"
      checked: root.service && root.service.masterEnabled === true
      subtitle: root.service && root.service.masterEnabled ? root.text("enabled", "ON") : root.text("disabled", "OFF")
      usable: !!root.service && !root.service.safeMode
      onClicked: if (root.service) root.service.setMasterEnabled(!root.service.masterEnabled)
    }

    RowLayout {
      visible: !root.contextMenu
      Layout.fillWidth: true
      spacing: tokens.space(8)
      ActionButton {
        Layout.fillWidth: true
        minimumHeight: tokens.target(50)
        text: root.text("mode", "Mode")
        icon: "◈"
        subtitle: root.profileLabel() + " · " + (root.service ? root.service.detectedMode : "desktop")
        checked: root.service && root.service.adaptiveProfile !== "auto"
        onClicked: root.moreOpen = true
      }
      ActionButton {
        Layout.fillWidth: true
        minimumHeight: tokens.target(50)
        text: root.text("suspend", "Suspend")
        icon: root.service && root.service.suspended ? "Ⅱ" : "▶"
        subtitle: root.service && root.service.suspended ? root.text("suspended", "Suspended") : root.text("active", "Active")
        checked: root.service && root.service.suspended === true
        usable: !!root.service
        onClicked: if (root.service) root.service.setSuspended(!root.service.suspended)
      }
    }

    Flow {
      visible: !root.contextMenu
      Layout.fillWidth: true
      spacing: tokens.space(8)
      Repeater {
        model: ["gestures", "osk", "rotation"]
        delegate: ActionButton {
          required property string modelData
          width: (parent.width - tokens.space(16)) / 3
          minimumWidth: tokens.target(96)
          minimumHeight: tokens.target(52)
          compact: true
          property var row: root.feature(modelData)
          text: row ? row.label : modelData
          icon: row && row.effectiveEnabled ? "✓" : "·"
          checked: row && row.effectiveEnabled === true
          usable: root.canToggle(row)
          subtitle: row && !row.available ? root.text("unavailable", "Unavailable") : row && row.disabledReason ? row.disabledReason : ""
          accessibleDescription: row && row.disabledReason ? row.disabledReason : root.text("toggleFeature", "Toggle feature")
          onClicked: root.toggleRow(row)
        }
      }
    }

    ActionButton {
      visible: !root.contextMenu
      Layout.fillWidth: true
      minimumHeight: tokens.target(46)
      compact: true
      text: root.moreOpen ? root.text("showLess", "Show less") : root.text("more", "More")
      icon: root.moreOpen ? "⌃" : "⌄"
      onClicked: root.moreOpen = !root.moreOpen
    }

    Flickable {
      visible: !root.contextMenu && root.moreOpen
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: width
      contentHeight: allFeatures.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: allFeatures
        width: parent.width
        spacing: tokens.space(7)
        Repeater {
          model: root.moduleRows()
          delegate: ActionButton {
            required property var modelData
            Layout.fillWidth: true
            minimumHeight: tokens.target(48)
            text: modelData.label
            icon: modelData.effectiveEnabled ? "✓" : "·"
            checked: modelData.effectiveEnabled === true
            usable: root.canToggle(modelData)
            subtitle: !modelData.available ? modelData.disabledReason : modelData.disabledReason || (modelData.profileOverride ? modelData.profileOverride.reason : "")
            accessibleDescription: modelData.disabledReason || root.text("toggleFeature", "Toggle feature")
            onClicked: root.toggleRow(modelData)
          }
        }
      }
    }

    RowLayout {
      visible: !root.contextMenu
      Layout.fillWidth: true
      spacing: tokens.space(8)
      ActionButton {
        Layout.fillWidth: true
        compact: true
        text: root.text("settings", "Settings")
        icon: "⚙"
        onClicked: {
          if (!root.panel) return
          root.panel.transientOverlay = false
          root.panel.activeView = "settings"
          root.panel.payloadView = "settings://general"
        }
      }
      Text {
        Layout.fillWidth: true
        text: root.service && root.service.safeMode ? root.text("safeMode", "Safe Mode") : (root.service ? root.service.detectedMode : "desktop")
        color: root.service && root.service.safeMode ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
