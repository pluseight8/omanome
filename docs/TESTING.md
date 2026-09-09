# Testing and acceptance notes

## Local checks

Run:

```sh
make check
make input-check
make companion-check
make dependency-audit
make performance-test
make hardware-test
make multitasking-check
make adaptive-check
make device-check
make version-check
omarchy plugin validate .
./cli/omanome doctor
```

The command performs:

1. manifest/config safety validation;
2. `bash -n` on the CLI, clipboard and Force Quit helpers, capability probes, scanners, sensor/rotation helpers, and audio helper;
3. Python unit tests for the GitHub install contract, bar coexistence, config version/migrations, OSK layouts and controls, capability-based stylus fixtures, touch conflict policy, rotation transforms, sensor diagnostics, companion ABI/crash-marker handling, Force Quit PID protection, clipboard safety/data operations, notification grouping, uninstall scope, and native Omarchy validation;
4. Qt `qmllint` with temporary import links to the installed Omarchy `qs.Commons` and `qs.Ui` modules.

`dependency-audit` is a static policy check for sudo, X11, replacement-bar,
name-based kill, and curl-pipe-shell regressions. `performance-test` is a
deterministic config projection/JSON round-trip budget check; it is not a
frame-rate certification. `performance-check` additionally audits unbounded
loops, fast/process polling, Lua invocations, ownership markers, and hot-path
config writes. `hardware-test` consumes a fixture and explicitly reports
`realHardwareValidated: false`. The 1.1 fixtures cover native tablet
pressure/tilt/distance/rotation/eraser/buttons, bounded ink, input/display
hotplug, suspend/resume, output remap, and rollback; fixture evidence never
certifies physical hardware.
`multitasking-check` additionally runs the bounded 1.1 multitasking model suite,
validates the 1.1 source/config contracts, and checks the eight interactive
scenarios as `Untested` fixture evidence; it never simulates a touchscreen or
stylus. `version-check` verifies that the manifest,
companion descriptor, README, changelog, and release metadata agree.

`adaptive-check` runs the 1.2 Control Center, feature registry, keyboard
classification, transition, Docked mode, privacy boundary, and no-config-write
contracts. `test_config_migration` proves that 1.1-style settings gain the new
sections without losing user values; `test_update_lifecycle` proves rollback
restores the exact pre-migration file. The adaptive fixture contains the eight
interactive scenarios, but every row is `Untested` until an operator confirms
real hardware.
`device-check` runs the 1.3 Device Graph, relationship confidence, calibration
rollback, display mapping, topology coalescing, setup matching, battery-source
privacy, diagnostics-only quirks, and event-driven performance contracts. Its
fixture evidence is explicitly not physical certification. The device gate
also checks that the standard Omarchy bar remains a bar-widget extension and
that no raw hardware identifier crosses a public diagnostics boundary.
The runtime service coalesces Quick Settings into one state probe and only starts
Wi-Fi, Bluetooth, and audio enumeration when their pickers are opened. Device
inventory uses a slow compatibility snapshot plus one event-driven udev hotplug
observer; all subprocess actions are argv-based and missing optional commands
produce disabled controls. `omanome input-info` is the truthful native/fallback
diagnostic and does not include typed or surrounding text.

The temporary QML import directory is outside the checkout and is removed when the lint target exits, so it cannot make `omarchy plugin validate` reject the repository for containing symlinks.

## Manual matrix

The QML code is designed for the following manual matrix when hardware is available:

| Area | Check |
| --- | --- |
| Input | mouse, keyboard, touchpad, touchscreen, generic tablet/stylus, eraser and side buttons |
| Shell coexistence | standard bar, multiple bar widgets, a panel, overlay, menu, and service plugin remain usable |
| Outputs | one monitor, multiple monitors, portrait and landscape |
| Scale | 1.0x through 2.0x fractional scaling |
| Apps | GTK, Qt, Electron, terminal, browser, fullscreen client, drawing application |
| Lifecycle | disable, safe-mode, clean install, update check/dry-run, successful update, health-failure rollback, interrupted journal recovery, rollback inventory, uninstall with and without settings |
| 1.1 performance/lifecycle | owner-only process snapshot and watchdog, strict identity, bounded restarts/backoff, search/write debounce, panel resource release, performance modes/migration, repeated open/close fixture, native input suspend/reconnect lifecycle, portable install/update/reload/rollback/uninstall E2E, multitasking no-polling/no-drag-subprocess gate |
| 1.2 adaptive/lifecycle | Control Center master/suspend/resume, feature precedence, opaque keyboard identity, attach/detach reversal, Docked mode, 100-event hotplug stream, migration/rollback byte preservation, private diagnostic redaction, and adaptive fixture gate |
| 1.3 device intelligence | Device Graph and relationship confidence, five-point touch workflow, stylus capability gating, wrong-display diagnosis, mapping ambiguity, persistent calibration rollback, setup exact/partial matching, dock event coalescing, multi-source battery privacy, quirks visibility, safe recovery, and 1000-event bounded recomputation |
| 0.7 lifecycle | transactional journal, bounded snapshots, config migration refusal, ownership manifest, dry-run/JSON uninstall, symlink refusal, support bundle redaction |
| 0.6 surfaces retained | responsive Overview/App Grid/Dock, Settings deep links, onboarding migration, accessibility semantics, multi-signal Tablet Mode |
| 0.6 effects retained | real layer-rule blur, native toplevel Coverflow, compositor-owned ScreencopyView streams, public-API Wobbly workbuffer renderer, external cube detection |
| Safety | Force Quit protected PID 1/session process, sensitive MIME rejection, no payload command arguments, companion pending-load marker |

## Acceptance evidence available in this checkout

- `manifest.json` contains no replacement-bar kind.
- `scripts/validate.py` rejects unsafe absolute/parent entry points and symlinks.
- `Service.qml` uses a single namespaced IPC handler and no second shell process.
- `input/clipboard-capture.sh` drops sensitive/private state and password-like MIME hints and emits no payload logs.
- `shell/models/Clipboard.js` covers pinning, tags, text editing, retention/storage pruning, app exclusions, and persisted-pinned-only behavior without logging payloads.
- `shell/models/Notifications.js` groups only snapshots from Omarchy's native popup model; it does not create a notification daemon.
- `input/force-quit.sh` accepts only a numeric selected PID, protects session processes, and never searches by name or kills a process group.
- `input/companion-info.sh` and the CLI expose ABI, safe-mode, and pending-load crash-marker state; a failed companion load is not retried automatically.
- `hypr/omanome-hypr/wobbly-physics-test.cpp` runs bounded mesh physics without a desktop session; when matching Hyprland headers are installed, `make companion-check` also compiles the public `IWindowTransformer`/GL renderer.
- `input/system-state.sh`, `input/wifi-scan.sh`, `input/bluetooth-scan.sh`, and `input/audio-devices.sh` return capability-safe JSON; they do not invent state when a backend is absent.
- `tests/fixtures/stylus-devices.json` covers touchscreen, generic tablet tools, eraser, no-pressure, serial, and mapped-output input records without requiring hardware.
- `input/sensor-info.sh` and `omanome sensor-info` distinguish monitor-sensor, iio D-Bus, and manual fallback, expose orientation/posture state when supplied by the session, and expose the orientation debounce/dwell policy.
- `omanome stylus-info` and `omanome touch-info` return capability-safe JSON even when Hyprland or a physical device is absent; they include native protocol and privacy status without typed or surrounding text.
- `scripts/hardware_test.py`, `scripts/support_bundle.py`, `scripts/dependency_audit.py`, and `scripts/performance_test.py` provide explicit non-certifying probes, redacted support evidence, static dependency policy, and deterministic performance budgets.
- `scripts/multitasking_check.py` separates portable multitasking safety from the user-assisted hardware matrix; its fixture cannot set `realHardwareValidated`.
- `hypr/README.md` records why no unpinned compositor `.so` is loaded.

Hardware-specific pressure, tilt, eraser, screen rotation, multi-monitor, and focus/text-input tests require the corresponding device/backend; they should not be represented as passed by static CI. The manual hardware workflow is dispatch-only for that reason.
