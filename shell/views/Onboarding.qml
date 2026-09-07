import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../components"

// A short, reversible first-run flow. It only writes Omanome's own config and
// never changes compositor state while showing the tutorial.
Item {
  id: root

  property var service: null
  property var panel: null
  property int step: 0
  property string selectedMode: "automatic"
  property string selectedDock: "bottom"

  DesignTokens {
    id: tokens
    service: root.service
    viewportWidth: root.width
    viewportHeight: root.height
  }

  function steps() {
    var result = [
      { key: "welcome", title: root.service.tr("onboardingWelcome", "Welcome to Omanome"), description: root.service.tr("onboardingWelcomeHint", "A tablet-first desktop experience inside the existing Omarchy shell.") },
      { key: "input", title: root.service.tr("onboardingInput", "Choose your input mode"), description: root.service.tr("onboardingInputHint", "Auto combines device, orientation and recent input signals. You can change this later in Settings.") },
      { key: "dock", title: root.service.tr("onboardingDock", "Place the Dock"), description: root.service.tr("onboardingDockHint", "Pick a comfortable edge. Adaptive follows portrait orientation when Tablet Mode is active.") },
      { key: "overview", title: root.service.tr("onboardingOverview", "Learn the Overview"), description: root.service.tr("onboardingOverviewHint", "Overview keeps real Hyprland windows, workspaces and search in one surface. This tutorial does not move windows.") },
      { key: "keyboard", title: root.service.tr("onboardingKeyboard", "On-screen keyboard"), description: root.service.tr("onboardingKeyboardHint", "Omanome can show the native-friendly keyboard surface when an editable field needs it.") }
    ]
    if (root.service.hasStylus) result.push({ key: "stylus", title: root.service.tr("onboardingStylus", "Stylus detected"), description: root.service.tr("onboardingStylusHint", "Pressure, tilt and button capabilities remain native Wayland input. Configure mappings later if needed.") })
    if (root.service.systemState.rotationAvailable) result.push({ key: "rotation", title: root.service.tr("onboardingRotation", "Rotation is available"), description: root.service.tr("onboardingRotationHint", "Automatic rotation is opt-in and uses the detected session backend.") })
    result.push({ key: "privacy", title: root.service.tr("onboardingPrivacy", "Privacy choices"), description: root.service.tr("onboardingPrivacyHint", "Diagnostics contain capability metadata only. Clipboard capture remains configurable and local.") })
    result.push({ key: "finish", title: root.service.tr("onboardingFinish", "You are ready"), description: root.service.tr("onboardingFinishHint", "Open Settings at any time to refine Tablet Mode, Dock, Overview and accessibility.") })
    return result
  }

  function current() { var list = root.steps(); return list[Math.max(0, Math.min(root.step, list.length - 1))] }
  function setMode(value) {
    root.selectedMode = String(value)
    root.service.setConfig("general.mode", root.selectedMode)
  }
  function setDock(value) {
    root.selectedDock = String(value)
    root.service.setConfig("dock.position", root.selectedDock)
    root.service.setConfig("tabletMode.dockPreference", root.selectedDock === "adaptive" ? "adaptive" : root.selectedDock === "left" ? "side" : "bottom")
  }
  function next() {
    if (root.step < root.steps().length - 1) root.step++
    else root.finish()
  }
  function back() { if (root.step > 0) root.step-- }
  function skip() {
    root.service.setConfig("onboarding.skipped", true)
    root.service.setConfig("onboarding.completed", false)
    root.service.setConfig("onboarding.version", 1)
    if (root.panel) root.panel.activeView = "overview"
  }
  function finish() {
    root.service.setConfig("onboarding.completed", true)
    root.service.setConfig("onboarding.skipped", false)
    root.service.setConfig("onboarding.version", 1)
    if (root.panel) root.panel.activeView = "overview"
  }

  Component.onCompleted: {
    root.selectedMode = String(root.service.cfg("general.mode", "automatic"))
    root.selectedDock = String(root.service.cfg("dock.position", "bottom"))
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: tokens.space(22)
    spacing: tokens.space(14)

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: root.service.tr("onboarding", "Setup")
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        text: (root.step + 1) + " / " + root.steps().length
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    ProgressBar {
      Layout.fillWidth: true
      from: 0
      to: Math.max(1, root.steps().length - 1)
      value: root.step
    }

    Surface {
      Layout.fillWidth: true
      Layout.fillHeight: true
      surfaceRadius: tokens.radius(20)
      surfaceOpacity: root.service.surfaceOpacity("settings", root.service.cfg("appearance.opacity", 0.96))

      Flickable {
        anchors.fill: parent
        anchors.margins: tokens.space(22)
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true

        ColumnLayout {
          id: body
          width: parent.width
          spacing: tokens.space(14)

          Text {
            Layout.fillWidth: true
            text: root.current().title
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
          }
          Text {
            Layout.fillWidth: true
            text: root.current().description
            color: Color.muted
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "welcome"
            spacing: tokens.space(8)
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingWelcomeBody", "Omanome adds tablet-first surfaces without replacing the Omarchy bar, compositor or other plugins."); color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingWelcomeSafety", "Optional effects stay capability-gated and unavailable backends are shown honestly."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "input"
            spacing: tokens.space(8)
            Flow {
              Layout.fillWidth: true
              spacing: tokens.space(8)
              Repeater {
                model: [
                  { key: "automatic", label: root.service.tr("automatic", "Auto") },
                  { key: "desktop", label: root.service.tr("desktop", "Desktop") },
                  { key: "tablet", label: root.service.tr("tablet", "Tablet") },
                  { key: "hybrid", label: root.service.tr("hybrid", "Hybrid") }
                ]
                delegate: ActionButton {
                  required property var modelData
                  compact: true
                  text: modelData.label
                  checked: root.selectedMode === modelData.key
                  onClicked: root.setMode(modelData.key)
                }
              }
            }
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingDetected", "Detected") + ": " + root.service.detectedMode + " · " + root.service.lastInput + " · " + (root.service.hasTouchscreen ? root.service.tr("touchscreen", "touchscreen") : root.service.tr("desktop", "desktop")); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "dock"
            spacing: tokens.space(8)
            Flow {
              Layout.fillWidth: true
              spacing: tokens.space(8)
              Repeater {
                model: [
                  { key: "bottom", label: root.service.tr("bottom", "Bottom") },
                  { key: "left", label: root.service.tr("left", "Left") },
                  { key: "right", label: root.service.tr("right", "Right") },
                  { key: "adaptive", label: root.service.tr("adaptive", "Adaptive") }
                ]
                delegate: ActionButton {
                  required property var modelData
                  compact: true
                  text: modelData.label
                  checked: root.selectedDock === modelData.key
                  onClicked: root.setDock(modelData.key)
                }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "overview"
            spacing: tokens.space(8)
            ActionButton { Layout.fillWidth: true; text: root.service.tr("openOverview", "Open Overview now"); subtitle: root.service.tr("onboardingOverviewAction", "This only opens Omanome's preview surface."); onClicked: { if (root.panel) root.panel.activeView = "overview" } }
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingOverviewKeys", "Keyboard: F1 for Overview · Esc closes the panel · search accepts normal typing."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "keyboard"
            spacing: tokens.space(8)
            ActionButton { Layout.fillWidth: true; text: root.service.tr("autoShowKeyboard", "Auto-show on editable fields"); checked: root.service.cfg("keyboard.autoShow", true); onClicked: root.service.setConfig("keyboard.autoShow", !root.service.cfg("keyboard.autoShow", true)) }
            Text { Layout.fillWidth: true; text: root.service.inputBackendAvailable ? root.service.tr("inputBackendReady", "Optional input-method backend is available") : root.service.tr("onboardingKeyboardFallback", "Without an input-method backend, Omanome keeps the keyboard surface available for explicit use."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "stylus"
            spacing: tokens.space(8)
            ActionButton { Layout.fillWidth: true; text: root.service.tr("stylus", "Stylus"); subtitle: root.service.stylusDevices.length + " device(s) · " + root.service.tr("mappingShown", "generic mapping available"); checked: root.service.cfg("stylus.enabled", true); onClicked: root.service.setConfig("stylus.enabled", !root.service.cfg("stylus.enabled", true)) }
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingStylusSafety", "Omanome does not emulate a vendor driver or claim pressure support when the native device does not expose it."); color: Color.muted; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "rotation"
            spacing: tokens.space(8)
            ActionButton { Layout.fillWidth: true; text: root.service.tr("automaticRotation", "Automatic rotation"); checked: root.service.cfg("rotation.orientation", "auto") === "auto"; onClicked: root.service.setRotationOrientation(root.service.cfg("rotation.orientation", "auto") === "auto" ? "landscape" : "auto") }
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingRotationBackend", "Backend") + ": " + String(root.service.systemState.rotationSensorBackend || "manual"); color: Color.muted; font.pixelSize: Style.font.caption }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "privacy"
            spacing: tokens.space(8)
            ActionButton { Layout.fillWidth: true; text: root.service.tr("clipboardPrivacy", "Clipboard privacy"); subtitle: root.service.tr("neverLogs", "Typed text and clipboard contents are never logged"); checked: root.service.cfg("privacy.clipboardPrivate", false); onClicked: root.service.setConfig("privacy.clipboardPrivate", !root.service.cfg("privacy.clipboardPrivate", false)) }
            ActionButton { Layout.fillWidth: true; text: root.service.tr("onboardingAcknowledge", "I understand"); checked: root.service.cfg("onboarding.privacyAcknowledged", false); onClicked: root.service.setConfig("onboarding.privacyAcknowledged", !root.service.cfg("onboarding.privacyAcknowledged", false)) }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.current().key === "finish"
            spacing: tokens.space(8)
            Text { Layout.fillWidth: true; text: root.service.tr("onboardingFinishBody", "Your choices are saved in Omanome's versioned config. Nothing here replaced the standard Omarchy bar."); color: Color.foreground; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
            ActionButton { Layout.fillWidth: true; text: root.service.tr("openSettings", "Open Settings"); onClicked: { if (root.panel) root.panel.activeView = "settings" } }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: tokens.space(8)
      ActionButton { compact: true; text: root.service.tr("skip", "Skip"); onClicked: root.skip() }
      Item { Layout.fillWidth: true }
      ActionButton { compact: true; visible: root.step > 0; text: root.service.tr("back", "Back"); onClicked: root.back() }
      ActionButton { compact: true; text: root.step === root.steps().length - 1 ? root.service.tr("finish", "Finish") : root.service.tr("next", "Next"); onClicked: root.next() }
    }
  }
}
