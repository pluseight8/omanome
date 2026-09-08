# Omanome hardware certification

Omanome separates capability discovery from hardware certification. A static
fixture can prove that the parser understands a capability; it cannot prove
that a physical touchscreen, pen, keyboard, sensor, display, or compositor
works on a user's machine.

## Result vocabulary

Every probe entry has both available (what the backend exposed) and result
(the test state):

| Result | Meaning |
| --- | --- |
| Pass | An operator explicitly tested the capability on real hardware. |
| Fail | An operator explicitly tested it and observed a failure. |
| Unavailable | The backend or hardware is not exposed in this session. |
| Skipped | The operator intentionally did not run this case. |
| Untested | The capability was detected or described, but no manual test was recorded. |

status: available is retained for compatibility with older reports. It is not
a certification result.

## Portable fixture checks

Fixture checks are safe for CI and never set realHardwareValidated:

    python3 scripts/hardware_test.py \
      --fixture tests/fixtures/suspend-resume.json \
      --json

The report says evidence: fixture; this is expected and must not be presented
as a device certification.

The 1.1 multitasking gate has the same boundary:

    python3 scripts/multitasking_check.py \
      --fixture tests/fixtures/hardware-multitasking.json --json

Its `portableSafety.result` can be `Pass` when the model and source contracts
are safe, while every interactive scenario remains `Untested` with
`realHardwareValidated: false`.

## Real hardware session

Run the probe from the active Wayland session. Store the session and report
outside the checkout, for example:

    state_home="$XDG_STATE_HOME"
    [ -n "$state_home" ] || state_home="$HOME/.local/state"
    session="$state_home/omanome/hardware-session.json"
    report="$state_home/omanome/hardware-report.json"

    python3 scripts/hardware_test.py \
      --session "$session" \
      --record display=Pass \
      --record keyboard=Pass \
      --record touchscreen=Skipped \
      --confirm-hardware \
      --report "$report" \
      --json

--confirm-hardware is deliberately explicit. The tool can preserve the
operator's result and the probe evidence, but it cannot independently
determine whether a human is physically touching the device. Pass and Fail
records are therefore rejected without that confirmation.

For the tablet multitasking matrix, use the user-assisted checklist from an
interactive terminal. It performs no pointer injection and does not move
windows automatically; the operator performs each action and records the
observed result:

    python3 scripts/hardware_test.py \
      --guided \
      --session "$session" \
      --confirm-hardware \
      --report "$report" \
      --json

The checklist is resumable. A non-interactive shell, a fixture, or a session
without explicit hardware confirmation cannot produce Pass/Fail evidence.

After a suspend, reboot, compositor restart, or an interrupted test, resume
the same session rather than creating a new one:

    python3 scripts/hardware_test.py \
      --session "$session" \
      --resume \
      --record suspendResume=Pass \
      --confirm-hardware \
      --report "$report" \
      --json

Session and report files are written atomically with mode 0600. They contain
result names and timestamps only; Omanome does not upload them automatically,
and they do not contain typed text, clipboard contents, window titles, device
serials, or raw event streams.

Supported recording targets include:

display, touchscreen, touch, multitouch, keyboard, detachableKeyboard,
stylus, pressure, tilt, distance, rotation, eraser, stylusButtons,
stylusFeatures.pressure, certification.suspendResume, lifecycle.hotplug,
lifecycle.waylandReconnect, lifecycle.outputRemap, lifecycle.rollback,
orientation, osk, multiMonitor, handwriting.ink, and
handwriting.recognition. Multitasking targets are
`multitasking.touch-drag-window`, `multitasking.touch-snap`,
`multitasking.divider-drag`, `multitasking.dock-to-split`,
`multitasking.overview-to-split`, `multitasking.portrait-split`,
`multitasking.rotation`, and `multitasking.stylus-drag`.

## Certification matrix

The following are the required operator scenarios. The JSON report is the
source of truth for each device; this document is the workflow and boundary,
not a claim that every row has passed.

| Area | Required scenario |
| --- | --- |
| Platform/runtime | Wayland session, supported Hyprland version, clean boot, reload, and compositor reconnect |
| Display | Internal display, external display, unplug/replug, portrait, fractional scale, and small-screen layout |
| Touch | Single touch, multitouch, drag/scroll, edge gestures, touch-to-mouse policy, and no duplicate activation |
| Multitasking | Touch drag, touch snap, divider resize, Dock/Overview split, portrait split, rotation, and stylus drag |
| Stylus | Proximity, tip, pressure curve, tilt, distance, barrel buttons, eraser, mapping, rotation, and palm rejection |
| Keyboard | Built-in, USB, Bluetooth/detachable transitions, modifiers, layout switching, and focus changes |
| OSK | GTK3/GTK4, Qt5/Qt6, Electron/Chromium, Firefox, terminal, Steam, native Wayland, and XWayland |
| Lifecycle | Suspend/resume, hotplug, shell restart, input-helper restart, stale protocol, and repeated reload |
| Privacy | Password fields, clipboard exclusion, no typed text in logs, no serials in reports, and offline behavior |
| Recovery | Configuration corruption, interrupted update, rollback, uninstall, and post-uninstall absence |

## Tested, community, and untested evidence

- **Automated CI:** portable fixture and contract checks only; CI is not a
  physical hardware lab.
- **Maintainer certification:** must be attached as a sanitized report from a
  named device and environment. No maintainer report is implied by this
  repository file.
- **Community reports:** may be linked separately after review, with personal
  data and serial numbers removed.
- **Untested/Unavailable:** remain honest outcomes. They are not converted to
  Pass by fallback code.

When filing a hardware issue, include the sanitized report, Omanome version,
compositor/runtime versions, and the exact result target. Do not attach raw
input traces, clipboard dumps, private window titles, or hardware serials.
