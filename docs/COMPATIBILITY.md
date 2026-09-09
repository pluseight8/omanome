# Compatibility snapshot (1.4.0)

The repository was validated in the provided desktop environment on 2026-09-09 with:

| Component | Observed version | Validation |
| --- | --- | --- |
| Omarchy | `4.0.1-1` | `omarchy plugin validate .` passed |
| Quickshell | `0.3.1` | QML imports and plugin contract inspected |
| Hyprland | `0.56.2` | `hyprctl devices/monitors/clients -j` and IPC paths inspected |
| Qt `qmllint` | Qt `6.11.2` | all project QML files linted with exit status 0 |

The machine exposed the expected `touch`, `tablets`, and `switches` keys in `hyprctl devices -j`; no physical touchscreen or stylus was attached during the static validation run, so pressure, tilt, eraser, rotation, and palm-rejection behavior are not marked as hardware-tested.

The 1.4 release retains the 1.1 layer-rule blur, native foreign-toplevel
Coverflow, fail-closed companion boundaries, owner-only lifecycle policy, and
tablet multitasking. It retains the adaptive Control Center, master/suspend
boundaries, Auto/Desktop/Tablet/Hybrid profiles, capability-based keyboard
rules, reversible attach/detach choreography, and Docked mode for external
monitor plus keyboard combinations. Runtime transitions and profile previews
remain separate from durable configuration. Shared panel tokens, semantic focus
states, reduced motion/transparency, bounded preview teardown, and transient
state reset now harden the same surfaces without a second shell. The transactional updater now
proves that a 1.1-style configuration migrates atomically and that rollback
restores the exact pre-migration bytes without adaptive state. Status and
support diagnostics keep device paths, Bluetooth addresses, serials, typed text,
clipboard values, and window titles out of output; private export applies an
additional local redaction pass. The native helper still exposes
capability-driven Wayland virtual keyboard and tablet-v2 paths, xkbcommon EN/RU
keymaps, bounded stylus state, suspend/resume lifecycle, output remap and
rollback diagnostics. Optional backends remain capability-gated and the main
plugin remains loadable when any optional capability is absent.

The release environment did not include a physical touchscreen or stylus, so
pressure, tilt, eraser, palm rejection, sensor rotation, suspend/resume,
multi-monitor, and loaded-companion behavior remain untested rather than
certified.

## 1.3 device intelligence

The 1.3 release adds a generic Device Graph, Device Profiles 2.0, guided touch
and stylus calibration, display/input mapping, Hardware Setup Profiles, dock
continuity, event-driven UPower source summaries, and a diagnostics-only quirks
layer. Public graph, status, and support boundaries use opaque IDs and omit
serials, MAC addresses, raw syspaths, UPower object paths, event nodes, typed
text, and window titles. Calibration keeps one persistent last-known-good
mapping and fails closed on timeout, disconnect, invalid output, or ambiguous
identification.

Portable CI and fixtures prove these contracts but do not certify physical
touchscreens, styluses, displays, docks, batteries, sensors, or keyboard
relationships. Hardware evidence remains explicitly classified as Protocol
Supported, Fixture Tested, Runtime Probed, User Tested, or Certified; the
current checkout has no User Tested or Certified report. This is Not Hardware
Tested; the committed models and integration fixture are Fixture Tested.
