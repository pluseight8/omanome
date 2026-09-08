# Omanome 1.1 feature truth matrix

This document separates implemented contracts from capabilities that require a
particular compositor, backend, or physical device. The status vocabulary is:

- **Stable** — implemented in the plugin and covered by deterministic tests or
  portable integration checks.
- **Experimental** — implemented behind an optional, capability-gated boundary
  and expected to vary with the host runtime.
- **Unavailable** — the current host does not expose the provider required to
  run the feature; the UI reports the reason and stays safe.
- **Untested** — a physical or host-specific acceptance step still requires the
  corresponding hardware or backend.

| Feature | Implementation/backend | Runtime or fixture evidence | Hardware/certification status | Fallback and limitation |
| --- | --- | --- | --- | --- |
| Standard bar and plugin coexistence | One Omarchy manifest with `service`, `bar-widget`, and `panel`; no replacement `bar` kind or second shell | `omarchy plugin validate .`, manifest tests, portable lifecycle E2E | Stable; physical certification not applicable | Existing bar, plugins, themes, and user Hyprland files remain outside Omanome ownership |
| Overview, workspaces, launcher, App Grid, Dock | Native Quickshell views, foreign-toplevel activation, desktop entries, persisted favorites/folders, responsive layout | Node model tests, QML lint, manifest/fixture gates | Stable contract; GUI interaction still requires manual host acceptance | Empty or unavailable providers produce empty states; shell remains usable |
| Snap Assist and layout engine | Event-driven `LayoutEngine` geometry for halves, thirds, quarters, portrait, gaps, reserved bar space, scale, and minimum size | `make multitasking-check`, Node geometry tests, portable fixture gate | Stable portable contract; physical drag acceptance remains untested | Preview is a bounded proposal; no continuous geometry forcing or fake screenshots |
| Split View and divider | `SplitView` ratio clamp, large divider handle, portrait conversion, second-window picker, apply/rollback transaction | Split/rotation model tests and multitasking CI job | Stable portable contract; live compositor resize needs host acceptance | Rejected dispatch rolls back the prior pair and reports the reason |
| Window Groups and App Pairs | Bounded `WindowGroups` metadata, deterministic app matching, lifecycle reconciliation, workspace/monitor movement | Group lifecycle, duplicate-window, timeout, persistence, and restore tests | Stable metadata contract; physical GUI behavior remains untested | Stores app identity and layout intent only; session restore defaults to `ask` |
| Floating, mini, and picture-in-picture | Explicit context actions with edge snap, keep-above, remembered position, and per-monitor policy | Floating model tests and service wiring checks | Stable policy contract; compositor-specific actions need host acceptance | Unsupported actions fail closed and do not rewrite unrelated Hyprland config |
| Workspace overlay and multitasking shortcuts | Transient `WorkspaceSwitcher`, event-driven overlay, user-owned bindings and conflict report | Overlay/shortcut tests and static polling audit | Stable portable contract; physical gesture acceptance remains untested | Existing bindings are reported, never silently replaced |
| Gesture navigation | Unified `GestureCoordinator` for touchscreen edges, workspace/Overview/Dock/QS/back, with touchpad opt-in | Threshold, velocity, cancellation, conflict, fullscreen, drawing-app, and OSK tests | Stable portable arbitration contract; physical latency is unmeasured | Touchscreen and touchpad policies remain separate; locks and accessibility reduce conflicts |
| Multi-monitor multitasking | Active-output geometry, orientation/scale conversion, group reconciliation, and hotplug recovery | Multi-monitor model/fixture checks and `make multitasking-check` | Stable portable recovery contract; external monitor hardware is untested | Windows are bounded back into a surviving output; no polling loop is used |
| Quick Settings and notifications | Omarchy-native notification service plus capability probes for Wi-Fi, Bluetooth, PipeWire, brightness, power, battery, DND, and actions | JSON capability probes, model tests, QML lint | Stable contract; backend/device behavior is host-dependent | Missing commands or services disable only the affected control |
| Clipboard and Force Quit | Privacy-filtered capture, local history, native close, selected-PID fallback, protected session processes | Python/Node safety tests and static dependency audit | Stable contract; GUI and application-specific behavior require manual acceptance | Sensitive MIME hints are dropped; no name-based kill or payload arguments |
| Native input and OSK | Rust `omanome-input`, bounded JSON IPC, xkbcommon EN/RU, `zwp_virtual_keyboard_v1` when exposed, Wayland `wtype` fallback | `make input-check`, protocol tests, `omanome input-info`, CI | Untested on physical keyboard/touchscreen; no hardware certification | Focus/virtual-keyboard paths are unavailable without compositor support; explicit OSK remains possible through `wtype` |
| Stylus, tablet, palm policy | Capability/type-based tablet inventory, tablet-v2 state, pressure/tilt/distance/rotation/eraser/buttons, bounded local ink, mapping and palm-policy configuration | Stylus/tablet fixtures, hardware-test JSON, Rust tests, `stylus-info` | Untested: no physical stylus or touchscreen was attached in the validation environment | Missing tablet backend reports unavailable; native client tablet events are never replaced by fake mouse events |
| Rotation, output mapping, hotplug, suspend/resume | Dynamic Hyprland transforms, sensor fallback chain, atomic remap/rollback, input/display hotplug and lifecycle state models | Rotation, sensor, hotplug, lifecycle fixtures and CLI diagnostics | Untested on physical multi-monitor, sensor, suspend, and hotplug matrix | Manual rotation works without sensors; rejected transform batches roll back |
| Live previews and Coverflow | Native foreign-toplevel selection with optional Quickshell `ScreencopyView`/compositor export stream | Alt-Tab model tests and capability probe | Unavailable in the validation host because no real texture stream is exposed | Preview stays disabled until a compositor-owned stream reports content; screenshots are never animated as fake previews |
| Wobbly and Desktop Cube | Optional exact-ABI `omanome-hypr` `IWindowTransformer`/GL workbuffer path; external `omarchy-desktop-cube` API | Companion checks, ABI/crash-marker tests, bounded physics tests | Experimental and untested with a loaded matching companion on physical hardware | Non-GL, rotated, X11, ABI mismatch, shader failure, or missing external backend fails closed |
| Performance and resource ownership | Owner-only process registry, PID/start-time identity, bounded lanes/backoff, lazy views, debounced writes, notify-only watchdog | `performance-test`, `performance-check`, repeated lifecycle fixture, CI | Stable deterministic budgets; idle CPU/frame-rate/thermal certification is not measured | Metrics are separated from whole-system CPU; watchdog never kills a process |
| Update, rollback, recovery, uninstall | Stable-release resolution, transactional journal, user-owned snapshots, health rollback, interrupted recovery, ownership-safe uninstall | Portable install/update/reload/suspend/rollback/uninstall E2E and CLI tests | Stable portable lifecycle contract; host package-manager behavior remains host-dependent | Updates require an explicit command; uninstall dry-run previews exact paths and preserves settings by default |
| Companion install and recovery | Versioned source build, API/ABI handshake, pending-load marker, safe mode and backup restore | Companion tests and `companion doctor` contract | Experimental; no universal binary or physical compositor certification | Companion is optional and disabled after an unconfirmed load or mismatch |
| Privacy and diagnostics | Redacted doctor/support bundle, no clipboard payloads/window titles/typed text/secrets in diagnostics, local handwriting slot | Dependency audit, support-bundle and diagnostics tests | Stable contract | Review support archives before sharing; no cloud recognition or telemetry is enabled by default |
| Accessibility, localization, onboarding | Shared semantic `ActionButton`, 48px minimum touch target, text scale, high contrast, reduced motion/transparency, screen-reader hints, EN/RU locale data, first-run setup | Locale key-set test, source contract test, QML lint | Stable source contract; screen-reader and GUI interaction need manual host acceptance | Missing host accessibility services do not prevent normal operation; onboarding can be skipped after migration |

## Certification boundary

The repository contains non-certifying fixtures and portable CI only. The
validation environment has Omarchy 4.0.1-1, Quickshell 0.3.1, Hyprland 0.56.2,
and no attached physical touchscreen or stylus. Therefore this release does
not claim certification for pressure, palm rejection, tilt, eraser buttons,
screen rotation, suspend/resume, multi-monitor behavior, text focus, or a loaded
optional companion. Those checks are listed in [`HARDWARE.md`](HARDWARE.md) and
must be performed on the target device.
