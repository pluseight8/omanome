import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"

// Device Center is a view over Service-owned models. It intentionally has no
// compositor or shell process calls: every write goes through a validated
// Service callback, while unavailable hardware remains visible as such.
Item {
  id: root

  property var service: null
  property var panel: null
  property string section: "displays"
  property bool advanced: false
  property string pendingForgetId: ""
  property int observedRevision: service ? service.stateRevision : 0
  property var sections: [
    { key: "displays", label: "Displays", icon: "▣" },
    { key: "touch", label: "Touch", icon: "⌁" },
    { key: "stylus", label: "Stylus", icon: "✎" },
    { key: "keyboards", label: "Keyboards", icon: "⌨" },
    { key: "setups", label: "Hardware setups", icon: "◇" },
    { key: "calibration", label: "Calibration", icon: "⊙" },
    { key: "diagnostics", label: "Diagnostics", icon: "✓" }
  ]

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
    transitionComponent: "settings"
  }

  Connections {
    target: root.service
    function onStateUpdated() { root.observedRevision = root.service ? root.service.stateRevision : root.observedRevision + 1 }
  }

  function text(key, fallback) { return root.service ? root.service.tr(key, fallback) : fallback }

  function openDeepLink(link) {
    var value = String(link || "").replace(/^devices?:\/\//, "").replace(/^\//, "")
    for (var i = 0; i < root.sections.length; i++) {
      if (root.sections[i].key === value) { root.section = value; return true }
    }
    return false
  }

  function selectSection(value) {
    root.section = String(value || "displays")
    root.pendingForgetId = ""
  }

  function graph() {
    var revision = root.observedRevision
    return root.service && root.service.deviceGraph ? root.service.deviceGraph : { nodes: [], outputs: [], relationships: [], health: {}, confidence: {} }
  }

  function graphSummary() {
    var source = root.graph()
    var nodes = Array.isArray(source.nodes) ? source.nodes : []
    var outputs = Array.isArray(source.outputs) ? source.outputs : []
    var connected = nodes.filter(function(row) { return row && row.connected === true }).length
    return { nodes: nodes.length, connected: connected, outputs: outputs.length, relationships: Array.isArray(source.relationships) ? source.relationships.length : 0, backend: String(source.health && source.health.backend || "unavailable"), available: source.health && source.health.available === true, confidence: source.confidence || {} }
  }

  function displayRows() {
    var revision = root.observedRevision
    var state = root.service && root.service.hardwarePolicyState ? root.service.hardwarePolicyState : {}
    var displays = state.displays || {}
    return Array.isArray(displays.rows) ? displays.rows : []
  }

  function deviceRows(categories) {
    var revision = root.observedRevision
    var rows = root.service && typeof root.service.deviceSettingsRows === "function" ? root.service.deviceSettingsRows() : []
    var wanted = Array.isArray(categories) ? categories : []
    return rows.filter(function(row) { return wanted.indexOf(String(row.category || "")) >= 0 })
  }

  function calibrationRows() {
    var revision = root.observedRevision
    return root.service && typeof root.service.deviceCalibrationRows === "function" ? root.service.deviceCalibrationRows() : []
  }

  function calibrationState() {
    var revision = root.observedRevision
    return root.service && root.service.calibrationWizardState ? root.service.calibrationWizardState : { phase: "idle", inputs: [], outputs: [], error: "" }
  }

  function calibrationTransaction() {
    var revision = root.observedRevision
    return root.service && root.service.calibrationTransactionState ? root.service.calibrationTransactionState : { phase: "idle", kind: "", targetId: "", remainingMs: 0, error: "" }
  }

  function nodeLabel(id) {
    var wanted = String(id || "")
    if (!wanted) return root.text("unresolved", "Unresolved")
    var source = root.graph()
    var nodes = Array.isArray(source.nodes) ? source.nodes : []
    for (var i = 0; i < nodes.length; i++) if (nodes[i] && String(nodes[i].id || "") === wanted) return String(nodes[i].label || nodes[i].category || root.text("device", "Device"))
    var outputs = Array.isArray(source.outputs) ? source.outputs : []
    for (var j = 0; j < outputs.length; j++) if (outputs[j] && String(outputs[j].id || "") === wanted) return String(outputs[j].name || root.text("display", "Display"))
    return root.text("unresolved", "Unresolved")
  }

  function outputLabel(id) {
    var wanted = String(id || "")
    if (!wanted || wanted === "auto") return root.text("automatic", "Automatic")
    return nodeLabel(wanted)
  }

  function roleText(row) { return String(row && row.role || "unknown") }

  function nextRole(row) {
    var choices = ["auto", "internal", "external", "presentation"]
    var current = roleText(row)
    var index = choices.indexOf(current)
    return choices[(index + 1 + choices.length) % choices.length]
  }

  function statusText(connected) { return connected === true ? root.text("connected", "Connected") : root.text("disconnected", "Disconnected") }

  function confidenceText(value) {
    var name = String(value || "unknown")
    return name === "confirmed" ? root.text("confirmed", "Confirmed") : name === "probable" ? root.text("probable", "Probable") : root.text("unknown", "Unknown")
  }

  function phaseText(value) {
    var name = String(value || "idle")
    var labels = { idle: "Idle", collecting: "Collecting real samples", analyzed: "Analysis ready", unavailable: "Unavailable", cancelled: "Cancelled", confirm: "Confirmation required", complete: "Ready to apply", ambiguous: "Choice required", prepared: "Preparing safe change", "awaiting-confirmation": "Keep these settings?", committed: "Saved", "rolled-back": "Reverted", rejected: "Rejected" }
    return labels[name] || name
  }

  function calibrationUsable(row) {
    if (!row || row.connected !== true) return false
    if (row.category === "touchscreen") return String(row.mappedOutput || "") !== ""
    return row.category === "stylus"
  }

  function selectedMappingCategory() {
    var state = root.calibrationState()
    var inputs = Array.isArray(state.inputs) ? state.inputs : []
    for (var i = 0; i < inputs.length; i++) if (inputs[i].id === state.selectedInputId) return String(inputs[i].category || "")
    return ""
  }

  function mappingCanApply() {
    var state = root.calibrationState()
    return state.phase === "complete" && ["touchscreen", "stylus"].indexOf(root.selectedMappingCategory()) >= 0 && root.calibrationTransaction().phase !== "awaiting-confirmation"
  }

  function requestForget(id) {
    var wanted = String(id || "")
    if (!wanted) return
    if (root.pendingForgetId === wanted) {
      if (root.service && typeof root.service.forgetDeviceProfile === "function") root.service.forgetDeviceProfile(wanted)
      root.pendingForgetId = ""
    } else root.pendingForgetId = wanted
  }

  function startCalibration(row) {
    if (!root.service || !row) return
    if (row.category === "touchscreen") root.service.beginTouchCalibration(row.id, row.mappedOutput)
    else if (row.category === "stylus") root.service.beginStylusCalibration(row.id)
  }

  function resetCalibration() {
    if (root.service && typeof root.service.cancelCalibration === "function") root.service.cancelCalibration("", "calibration-cancelled-from-center")
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(16)
    spacing: tokens.space(10)

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: tokens.target(46)
      spacing: tokens.space(10)

      Text { text: "⌁"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Text { text: root.text("deviceCenter", "Device Center"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
        Text { text: root.text("deviceCenterSubtitle", "Universal hardware inventory, profiles and calibration"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight; Layout.fillWidth: true }
      }
      ActionButton { compact: true; text: root.advanced ? root.text("basic", "Basic") : root.text("advanced", "Advanced"); icon: root.advanced ? "−" : "+"; onClicked: root.advanced = !root.advanced }
      ActionButton { compact: true; text: root.text("refresh", "Refresh"); icon: "↻"; usable: !!root.service; onClicked: if (root.service) root.service.refreshDevices() }
      ActionButton { compact: true; minimumWidth: tokens.target(72); text: root.text("close", "Close"); onClicked: if (root.panel) root.panel.close() }
    }

    Flow {
      Layout.fillWidth: true
      spacing: tokens.space(6)
      Repeater {
        model: root.sections
        delegate: ActionButton {
          required property var modelData
          compact: true
          text: modelData.label
          icon: modelData.icon
          checked: root.section === modelData.key
          onClicked: root.selectSection(modelData.key)
        }
      }
    }

    Flickable {
      id: content
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: width
      contentHeight: body.implicitHeight + tokens.space(24)
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: body
        width: content.width
        spacing: tokens.space(12)

        Column {
          width: parent.width
          visible: root.section === "displays"
          height: visible ? implicitHeight : 0
          spacing: tokens.space(8)

          SectionHeader { width: parent.width; title: root.text("displays", "Displays"); subtitle: root.text("displayCenterHint", "Roles are evidence-based. A display name never establishes identity by itself.") }
          Text { width: parent.width; text: root.displayRows().length + " display(s) · " + root.graphSummary().backend + " · " + (root.graphSummary().available ? root.text("available", "available") : root.text("unavailable", "unavailable")); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

          Repeater {
            model: root.displayRows()
            delegate: Rectangle {
              id: displayCardItem
              required property var modelData
              width: body.width
              implicitHeight: displayBody.implicitHeight + tokens.space(20)
              radius: tokens.radius(12)
              color: Util.alpha(Color.foreground, 0.05)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.12)

              ColumnLayout {
                id: displayBody
                anchors.fill: parent
                anchors.margins: tokens.space(10)
                spacing: tokens.space(6)
                RowLayout {
                  Layout.fillWidth: true
                  Text { text: String(displayCardItem.modelData.name || root.text("display", "Display")); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                  Text { text: root.statusText(displayCardItem.modelData.connected); color: displayCardItem.modelData.connected ? Color.accent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                }
                Text { Layout.fillWidth: true; text: "Role: " + root.roleText(displayCardItem.modelData) + " · " + root.confidenceText(displayCardItem.modelData.confidence) + " · " + String(displayCardItem.modelData.roleSource || "unknown"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; text: "Geometry: " + String(displayCardItem.modelData.geometry && displayCardItem.modelData.geometry.width || "?") + "×" + String(displayCardItem.modelData.geometry && displayCardItem.modelData.geometry.height || "?") + " · scale " + String(displayCardItem.modelData.scale || 1) + " · orientation " + String(displayCardItem.modelData.orientation || "auto"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
                Flow {
                  Layout.fillWidth: true
                  spacing: tokens.space(6)
                  ActionButton { compact: true; text: "Role: " + root.roleText(displayCardItem.modelData); checked: displayCardItem.modelData.roleSource === "user"; onClicked: if (root.service) root.service.setHardwareDisplayRole(displayCardItem.modelData.id, root.nextRole(displayCardItem.modelData)) }
                  ActionButton { compact: true; text: root.text("makePrimary", "Make primary"); checked: displayCardItem.modelData.role === "primary"; onClicked: if (root.service) root.service.setHardwarePrimaryDisplay(displayCardItem.modelData.id) }
                }
                Text { visible: root.advanced; Layout.fillWidth: true; text: "Opaque ID: " + String(displayCardItem.modelData.id || ""); color: Color.muted; font.family: "monospace"; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
              }
            }
          }

          Text { visible: root.displayRows().length === 0; width: parent.width; text: root.text("noDisplayInventory", "No verified display inventory is available yet."); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          visible: root.section === "touch" || root.section === "stylus" || root.section === "keyboards"
          height: visible ? implicitHeight : 0
          spacing: tokens.space(8)

          SectionHeader { width: parent.width; title: root.section === "touch" ? root.text("touch", "Touch") : root.section === "stylus" ? root.text("stylus", "Stylus") : root.text("keyboards", "Keyboards"); subtitle: root.text("deviceCardHint", "Friendly names are local to Omanome. System pairing and kernel device names are never changed.") }
          Repeater {
            model: root.deviceRows(root.section === "touch" ? ["touchscreen"] : root.section === "stylus" ? ["stylus"] : ["keyboard"])
            delegate: Loader {
              required property var modelData
              width: body.width
              height: item ? item.implicitHeight : 0
              sourceComponent: deviceCard
              onLoaded: item.row = modelData
            }
          }
          Text { visible: root.deviceRows(root.section === "touch" ? ["touchscreen"] : root.section === "stylus" ? ["stylus"] : ["keyboard"]).length === 0; width: parent.width; text: root.text("noDeviceInventory", "No device in this category is currently available."); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          visible: root.section === "setups"
          height: visible ? implicitHeight : 0
          spacing: tokens.space(8)

          SectionHeader { width: parent.width; title: root.text("hardwareSetups", "Hardware setups"); subtitle: root.text("hardwareSetupsHint", "A setup is an explicit policy overlay for topology, OSK target, power and docking behavior.") }
          Text { width: parent.width; text: "Requested: " + String(root.service && root.service.hardwareSetupStore ? root.service.hardwareSetupStore.selected : "auto") + " · Effective: " + String(root.service && root.service.hardwarePolicyState ? root.service.hardwarePolicyState.selected : "auto"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Flow {
            width: parent.width
            spacing: tokens.space(6)
            Repeater {
              model: root.service && typeof root.service.hardwareSetupChoices === "function" ? root.service.hardwareSetupChoices() : []
              delegate: ActionButton {
                required property var modelData
                compact: true
                text: modelData.label
                checked: root.service && root.service.hardwareSetupStore && root.service.hardwareSetupStore.selected === modelData.id
                usable: !!root.service
                onClicked: if (root.service) root.service.setHardwareSetupProfile(modelData.id)
              }
            }
          }
          SectionHeader { width: parent.width; title: root.text("oskTarget", "On-screen keyboard target"); subtitle: root.text("oskTargetHint", "No display is guessed when the requested target cannot be verified.") }
          Flow {
            width: parent.width
            spacing: tokens.space(6)
            Repeater {
              model: ["focused-display", "primary-touch", "ask", "disabled"]
              delegate: ActionButton {
                required property string modelData
                compact: true
                text: modelData
                checked: root.service && root.service.hardwareSetupStore && root.service.hardwareSetupStore.displayPolicy && root.service.hardwareSetupStore.displayPolicy.oskTarget === modelData
                usable: !!root.service
                onClicked: if (root.service) root.service.setHardwareOskTarget(modelData)
              }
            }
          }
          Text { width: parent.width; text: "OSK: " + String(root.service && root.service.hardwarePolicyState && root.service.hardwarePolicyState.osk ? root.service.hardwarePolicyState.osk.status : "unavailable") + " · Power: " + String(root.service && root.service.hardwarePolicyState && root.service.hardwarePolicyState.power ? root.service.hardwarePolicyState.power.reason : "unknown"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        }

        Column {
          width: parent.width
          visible: root.section === "calibration"
          height: visible ? implicitHeight : 0
          spacing: tokens.space(8)

          SectionHeader { width: parent.width; title: root.text("calibration", "Calibration Center"); subtitle: root.text("calibrationHint", "Touch calibration uses five real targets. Stylus analysis uses real pressure, tilt, proximity and eraser events only.") }
          Rectangle {
            width: parent.width
            implicitHeight: mappingBody.implicitHeight + tokens.space(20)
            radius: tokens.radius(12)
            color: Util.alpha(Color.accent, 0.08)
            border.width: 1
            border.color: Util.alpha(Color.accent, 0.24)
            ColumnLayout {
              id: mappingBody
              anchors.fill: parent
              anchors.margins: tokens.space(10)
              spacing: tokens.space(7)
              RowLayout {
                Layout.fillWidth: true
                Text { text: root.text("mappingWizard", "Display mapping wizard"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; Layout.fillWidth: true }
                Text { text: root.phaseText(root.calibrationState().phase); color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              }
              Text { Layout.fillWidth: true; text: root.calibrationState().error ? String(root.calibrationState().error) : root.text("mappingWizardHint", "Select an input, select a numbered display, identify it, then confirm before applying."); color: root.calibrationState().error ? Color.urgent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { Layout.fillWidth: true; text: root.text("startMapping", "Start mapping"); subtitle: root.text("startMappingHint", "Only confirmed touchscreen or stylus mappings can be saved"); usable: !!root.service; visible: ["idle", "cancelled", "complete", "unavailable"].indexOf(root.calibrationState().phase) >= 0; onClicked: if (root.service) root.service.beginDeviceMapping() }
              Flow {
                Layout.fillWidth: true
                spacing: tokens.space(6)
                visible: ["select-input", "select-output", "identify-output", "confirm", "ambiguous"].indexOf(root.calibrationState().phase) >= 0
                Repeater {
                  model: root.calibrationState().inputs || []
                  delegate: ActionButton {
                    required property var modelData
                    compact: true
                    text: modelData.label + " · " + modelData.category
                    checked: root.calibrationState().selectedInputId === modelData.id
                    usable: modelData.connected === true && !!root.service
                    onClicked: if (root.service) root.service.selectDeviceMappingInput(modelData.id)
                  }
                }
              }
              Flow {
                Layout.fillWidth: true
                spacing: tokens.space(6)
                visible: ["select-output", "identify-output", "confirm", "ambiguous"].indexOf(root.calibrationState().phase) >= 0
                Repeater {
                  model: root.calibrationState().outputs || []
                  delegate: ActionButton {
                    required property var modelData
                    compact: true
                    text: modelData.label + " · " + modelData.name
                    checked: root.calibrationState().selectedOutputId === modelData.id
                    usable: modelData.connected === true && !!root.service
                    onClicked: if (root.service) root.service.selectDeviceMappingOutput(modelData.id)
                  }
                }
              }
              ActionButton { Layout.fillWidth: true; text: root.text("cancel", "Cancel"); visible: ["select-input", "select-output", "identify-output", "ambiguous"].indexOf(root.calibrationState().phase) >= 0; onClicked: if (root.service) root.service.cancelDeviceMapping("mapping-cancelled-by-user") }
              RowLayout {
                Layout.fillWidth: true
                visible: root.calibrationState().phase === "identify-output"
                ActionButton { Layout.fillWidth: true; text: root.text("identifyDisplay", "Identify selected display"); subtitle: root.text("identifyDisplayHint", "The number is an explicit user choice; no name heuristic is used"); usable: !!root.service && String(root.calibrationState().selectedOutputId || "") !== ""; onClicked: if (root.service) root.service.identifyDeviceMapping(root.calibrationState().selectedOutputId, "number") }
              }
              RowLayout {
                Layout.fillWidth: true
                visible: root.calibrationState().phase === "confirm" || root.calibrationState().phase === "complete"
                ActionButton { Layout.fillWidth: true; text: root.text("confirmMapping", "Confirm mapping"); usable: !!root.service && root.calibrationState().phase === "confirm"; onClicked: if (root.service) root.service.confirmDeviceMapping() }
                ActionButton { Layout.fillWidth: true; text: root.text("apply", "Apply"); subtitle: root.text("applyHint", "Save Omanome device profile"); usable: !!root.service && root.mappingCanApply(); visible: root.calibrationState().phase === "complete"; onClicked: if (root.service) root.service.applyDeviceMapping() }
                ActionButton { Layout.fillWidth: true; text: root.text("cancel", "Cancel"); onClicked: if (root.service) root.service.cancelDeviceMapping("mapping-cancelled-by-user") }
              }
            }
          }

          Repeater {
            model: root.calibrationRows()
            delegate: Rectangle {
              id: calibrationCardItem
              required property var modelData
              width: body.width
              implicitHeight: calibrationBody.implicitHeight + tokens.space(20)
              radius: tokens.radius(12)
              color: Util.alpha(Color.foreground, 0.05)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.12)
              ColumnLayout {
                id: calibrationBody
                anchors.fill: parent
                anchors.margins: tokens.space(10)
                spacing: tokens.space(6)
                RowLayout {
                  Layout.fillWidth: true
                  Text { text: String(calibrationCardItem.modelData.label || calibrationCardItem.modelData.category); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; Layout.fillWidth: true }
                  Text { text: root.statusText(calibrationCardItem.modelData.connected); color: calibrationCardItem.modelData.connected ? Color.accent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                }
                Text { Layout.fillWidth: true; text: calibrationCardItem.modelData.category + " · mapped display: " + root.outputLabel(calibrationCardItem.modelData.mappedOutput) + " · confidence: " + root.confidenceText(calibrationCardItem.modelData.confidence); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
                Flow {
                  Layout.fillWidth: true
                  spacing: tokens.space(6)
                  ActionButton { compact: true; text: calibrationCardItem.modelData.category === "touchscreen" ? root.text("calibrateTouch", "Calibrate touch") : root.text("calibrateStylus", "Calibrate stylus"); subtitle: calibrationCardItem.modelData.category === "touchscreen" && !calibrationCardItem.modelData.mappedOutput ? root.text("mapDisplayFirst", "Map a display first") : root.text("realSamplesOnly", "Real samples only"); usable: root.calibrationUsable(calibrationCardItem.modelData) && !!root.service; onClicked: root.startCalibration(calibrationCardItem.modelData) }
                  ActionButton { compact: true; text: root.text("mapDisplay", "Map display"); visible: calibrationCardItem.modelData.category === "touchscreen" || calibrationCardItem.modelData.category === "stylus"; onClicked: { root.section = "calibration"; if (root.service) root.service.beginDeviceMapping() } }
                }
              }
            }
          }
          Text { visible: root.calibrationRows().length === 0; width: parent.width; text: root.text("noCalibrationDevices", "No touchscreen or stylus with a verified graph identity is available."); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }

          Rectangle {
            visible: root.service && (root.service.activeCalibrationKind === "touchscreen" || root.service.activeCalibrationKind === "stylus")
            width: parent.width
            implicitHeight: activeBody.implicitHeight + tokens.space(20)
            radius: tokens.radius(12)
            color: Util.alpha(Color.urgent, 0.08)
            border.width: 1
            border.color: Util.alpha(Color.urgent, 0.24)
            ColumnLayout {
              id: activeBody
              anchors.fill: parent
              anchors.margins: tokens.space(10)
              spacing: tokens.space(6)
              Text { text: root.text("activeCalibration", "Calibration session active"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
              Text { Layout.fillWidth: true; text: root.service && root.service.activeCalibrationKind === "touchscreen" ? "Touch: " + root.phaseText(root.service.touchCalibrationState.phase) + " · " + String(root.service.touchCalibrationState.samples.length || 0) + "/5 targets" : "Stylus: " + root.phaseText(root.service.stylusCalibrationState.phase) + " · " + String(root.service.stylusCalibrationState.samples.length || 0) + " real samples"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Text { visible: root.service && root.service.activeCalibrationKind === "touchscreen" && root.service.touchCalibrationState.phase === "analyzed"; Layout.fillWidth: true; text: root.service && root.service.touchCalibrationState.result ? "Touch result: " + (root.service.touchCalibrationState.result.safe ? "safe candidate" : String(root.service.touchCalibrationState.result.suggestion || "needs attention")) + " · RMS " + String(root.service.touchCalibrationState.result.rmsError || "?") : ""; color: root.service && root.service.touchCalibrationState.result && root.service.touchCalibrationState.result.safe ? Color.accent : Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Text { visible: root.service && root.service.activeCalibrationKind === "stylus" && root.service.stylusCalibrationState.analysis; Layout.fillWidth: true; text: root.service && root.service.stylusCalibrationState.analysis ? "Stylus capabilities observed from real samples: " + JSON.stringify(root.service.stylusCalibrationState.observed || {}) : ""; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Text { Layout.fillWidth: true; text: root.text("calibrationApplyBoundary", "Applying is withheld until the result is safe and explicitly confirmed. Cancel always leaves the previous profile untouched."); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              ActionButton { Layout.fillWidth: true; text: root.text("applyCalibration", "Preview calibration"); subtitle: root.text("applyCalibrationHint", "Save only after the confirmation countdown"); visible: root.service && root.service.activeCalibrationKind === "touchscreen" && root.service.touchCalibrationState.phase === "analyzed"; usable: !!root.service && root.service.touchCalibrationState.result && root.service.touchCalibrationState.result.safe === true; onClicked: if (root.service) root.service.applyTouchCalibration() }
              ActionButton { Layout.fillWidth: true; text: root.text("applyCalibration", "Preview calibration"); subtitle: root.text("applyCalibrationHint", "Save only after the confirmation countdown"); visible: root.service && root.service.activeCalibrationKind === "stylus" && root.service.stylusCalibrationState.analysis; usable: !!root.service; onClicked: if (root.service) root.service.applyStylusCalibration() }
              ActionButton { Layout.fillWidth: true; text: root.text("cancelCalibration", "Cancel calibration"); onClicked: root.resetCalibration() }
            }
          }

          Rectangle {
            visible: ["prepared", "awaiting-confirmation", "committed", "rolled-back", "rejected"].indexOf(root.calibrationTransaction().phase) >= 0 && root.calibrationTransaction().phase !== "idle"
            width: parent.width
            implicitHeight: transactionBody.implicitHeight + tokens.space(20)
            radius: tokens.radius(12)
            color: root.calibrationTransaction().phase === "awaiting-confirmation" ? Util.alpha(Color.accent, 0.10) : Util.alpha(Color.foreground, 0.05)
            border.width: 1
            border.color: root.calibrationTransaction().phase === "awaiting-confirmation" ? Util.alpha(Color.accent, 0.30) : Util.alpha(Color.foreground, 0.12)
            ColumnLayout {
              id: transactionBody
              anchors.fill: parent
              anchors.margins: tokens.space(10)
              spacing: tokens.space(6)
              Text { text: root.text("calibrationTransaction", "Calibration change"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
              Text { Layout.fillWidth: true; text: root.phaseText(root.calibrationTransaction().phase) + " · " + String(root.calibrationTransaction().kind || "device") + " · " + (Number(root.calibrationTransaction().remainingMs || 0) > 0 ? Math.ceil(Number(root.calibrationTransaction().remainingMs) / 1000) + "s" : String(root.calibrationTransaction().error || "")); color: root.calibrationTransaction().phase === "awaiting-confirmation" ? Color.accent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              Text { visible: root.calibrationTransaction().phase === "awaiting-confirmation"; Layout.fillWidth: true; text: root.text("calibrationKeepHint", "Keep applies the validated Omanome metadata. Revert restores the previous mapping."); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
              RowLayout {
                Layout.fillWidth: true
                visible: root.calibrationTransaction().phase === "awaiting-confirmation"
                ActionButton { Layout.fillWidth: true; text: root.text("keep", "Keep"); usable: !!root.service; onClicked: if (root.service) root.service.confirmCalibrationTransaction(true) }
                ActionButton { Layout.fillWidth: true; text: root.text("revert", "Revert"); usable: !!root.service; onClicked: if (root.service) root.service.rollbackCalibrationTransaction("calibration-reverted-by-user") }
              }
            }
          }
        }

        Column {
          width: parent.width
          visible: root.section === "diagnostics"
          height: visible ? implicitHeight : 0
          spacing: tokens.space(8)

          SectionHeader { width: parent.width; title: root.text("diagnostics", "Device diagnostics"); subtitle: root.text("deviceDiagnosticsHint", "Sanitized topology and capability state. Raw paths, serials, addresses and event nodes are excluded.") }
          Text { width: parent.width; text: "Graph: " + root.graphSummary().nodes + " node(s), " + root.graphSummary().connected + " connected, " + root.graphSummary().outputs + " output(s), " + root.graphSummary().relationships + " relation(s) · backend " + root.graphSummary().backend; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "Confidence: confirmed " + String(root.graphSummary().confidence.confirmed || 0) + " · probable " + String(root.graphSummary().confidence.probable || 0) + " · unknown " + String(root.graphSummary().confidence.unknown || 0); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "Topology: " + String(root.service && root.service.deviceTopologyState ? root.service.deviceTopologyState.phase : "idle") + " · " + (root.service && root.service.deviceTopologyState && root.service.deviceTopologyState.pendingRefresh ? "refresh pending" : "stable") + " · events " + String(root.service && root.service.deviceTopologyState ? root.service.deviceTopologyState.eventCount || 0 : 0); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "Docking: " + String(root.service && root.service.dockingContinuityState ? root.service.dockingContinuityState.phase : "undocked") + " · restore " + (root.service && root.service.dockingContinuityState && root.service.dockingContinuityState.restore && root.service.dockingContinuityState.restore.pending ? "choice required" : "not pending"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

          SectionHeader { width: parent.width; title: root.text("relationships", "Relationships"); subtitle: root.text("relationshipsHint", "Only explicit or evidence-backed edges are shown.") }
          Repeater {
            model: root.graph().relationships || []
            delegate: Text {
              required property var modelData
              width: body.width
              text: root.nodeLabel(modelData.from) + " → " + root.nodeLabel(modelData.to) + " · " + String(modelData.type || "relation") + " · " + root.confidenceText(modelData.confidence)
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }
          Text { visible: (root.graph().relationships || []).length === 0; width: parent.width; text: root.text("noRelationships", "No verified relationships are present."); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
          ActionButton { width: parent.width; text: root.text("refresh", "Refresh device inventory"); subtitle: root.text("refreshDeviceInventoryHint", "Event-driven sources are coalesced before the next snapshot"); usable: !!root.service; onClicked: if (root.service) root.service.refreshDevices() }
        }
      }
    }
  }

  Component {
    id: deviceCard
    Rectangle {
      id: deviceCardItem
      property var row: ({})
      implicitHeight: deviceBody.implicitHeight + tokens.space(20)
      radius: tokens.radius(12)
      color: Util.alpha(Color.foreground, 0.05)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.12)

      ColumnLayout {
        id: deviceBody
        anchors.fill: parent
        anchors.margins: tokens.space(10)
        spacing: tokens.space(6)
        RowLayout {
          Layout.fillWidth: true
          Text { text: String(deviceCardItem.row.label || deviceCardItem.row.category || root.text("device", "Device")); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
          Text { text: root.statusText(deviceCardItem.row.connected); color: deviceCardItem.row.connected ? Color.accent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
        Text { Layout.fillWidth: true; text: String(deviceCardItem.row.category || "device") + " · " + String(deviceCardItem.row.transport || "unknown") + " · confidence " + root.confidenceText(deviceCardItem.row.confidence); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        Text { Layout.fillWidth: true; text: "Mapped display: " + root.outputLabel(deviceCardItem.row.mappedOutput) + " · profile: " + (deviceCardItem.row.configured ? String(deviceCardItem.row.source || "device") : root.text("automatic", "Automatic")); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        TextField { visible: root.advanced; Layout.fillWidth: true; placeholderText: root.text("localFriendlyName", "Local friendly name"); text: deviceCardItem.row.profile && deviceCardItem.row.profile.name ? deviceCardItem.row.profile.name : ""; onAccepted: if (root.service && text.trim() !== "") root.service.renameDeviceProfile(deviceCardItem.row.id, text.trim()) }
        Text { visible: root.advanced; Layout.fillWidth: true; text: "Opaque ID: " + String(deviceCardItem.row.id || ""); color: Color.muted; font.family: "monospace"; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
        Flow {
          Layout.fillWidth: true
          spacing: tokens.space(6)
          ActionButton { compact: true; visible: deviceCardItem.row.category === "touchscreen" || deviceCardItem.row.category === "stylus"; text: root.text("mapDisplay", "Map display"); onClicked: { root.section = "calibration"; if (root.service) root.service.beginDeviceMapping() } }
          ActionButton { compact: true; visible: deviceCardItem.row.category === "touchscreen" || deviceCardItem.row.category === "stylus"; text: deviceCardItem.row.category === "touchscreen" ? root.text("calibrateTouch", "Calibrate touch") : root.text("calibrateStylus", "Calibrate stylus"); usable: root.calibrationUsable(deviceCardItem.row) && !!root.service; onClicked: root.startCalibration(deviceCardItem.row) }
          ActionButton { compact: true; visible: deviceCardItem.row.configured === true; text: root.pendingForgetId === deviceCardItem.row.id ? root.text("confirmForget", "Confirm forget") : root.text("forgetDevice", "Forget profile"); checked: root.pendingForgetId === deviceCardItem.row.id; onClicked: root.requestForget(deviceCardItem.row.id) }
          ActionButton { compact: true; visible: deviceCardItem.row.configured === true; text: root.text("resetDevice", "Reset device"); onClicked: if (root.service) root.service.resetDeviceProfile(deviceCardItem.row.id) }
          ActionButton { compact: true; visible: deviceCardItem.row.calibration && deviceCardItem.row.calibration.hasLastKnownGood === true; text: root.text("restoreCalibration", "Restore calibration"); onClicked: if (root.service) root.service.rollbackDeviceProfile(deviceCardItem.row.id) }
        }
      }
    }
  }
}
