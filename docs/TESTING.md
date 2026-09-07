# Testing and acceptance notes

## Local checks

Run:

```sh
make check
```

The command performs:

1. manifest/config safety validation;
2. `bash -n` on the CLI, clipboard and Force Quit helpers, capability probes, scanners, sensor/rotation helpers, and audio helper;
3. Python unit tests for the GitHub install contract, bar coexistence, config version/migrations, OSK layouts and controls, capability-based stylus fixtures, touch conflict policy, rotation transforms, sensor diagnostics, companion ABI/crash-marker handling, Force Quit PID protection, clipboard safety/data operations, notification grouping, uninstall scope, and native Omarchy validation;
4. Qt `qmllint` with temporary import links to the installed Omarchy `qs.Commons` and `qs.Ui` modules.

The runtime service coalesces Quick Settings into one state probe and only starts
Wi-Fi, Bluetooth, and audio enumeration when their pickers are opened. Device
inventory refreshes are periodic but intentionally slow; all subprocess actions
are argv-based and missing optional commands produce disabled controls.

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
| Lifecycle | disable, safe-mode, update check, rollback, uninstall with and without settings |
| 0.5 effects | real layer-rule blur, native toplevel Coverflow, compositor-owned ScreencopyView streams, public-API Wobbly workbuffer renderer, external cube detection |
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
- `input/sensor-info.sh` and `omanome sensor-info` distinguish monitor-sensor, iio D-Bus, and manual fallback.
- `hypr/README.md` records why no unpinned compositor `.so` is loaded.

Hardware-specific pressure, tilt, eraser, screen rotation, multi-monitor, and focus/text-input tests require the corresponding device/backend; they should not be represented as passed by static CI. The manual hardware workflow is dispatch-only for that reason.
