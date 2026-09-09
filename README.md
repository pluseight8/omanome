# Omanome

Omanome is an open-source, GNOME-inspired touch and stylus enhancement suite for the current Omarchy Quattro shell on Hyprland. It is intentionally an Omarchy plugin, not a replacement desktop session: the standard Omarchy bar remains in charge of the top edge, the existing Quickshell process hosts the plugin, and all plugin state is namespaced under `io.omanome.shell`.

This repository is the runnable 1.4.0 release. It uses public Omarchy/Quickshell/Hyprland interfaces for the core and explicit, version-aware optional compositor integrations for advanced effects. The native Wayland input helper owns one bounded seat/keyboard/tablet connection, supports xkbcommon EN/RU layouts, and reports unavailable compositor protocols honestly. Features without a real backend remain visibly unavailable rather than becoming fake overlays. The 1.4 release is a polish and reliability pass: shared tokens, semantic controls, reduced-motion/transparency handling, bounded preview lifecycle, transient-state teardown, and deterministic migration/update coverage.

## What is Omanome

Omanome is a single Omarchy plugin that adds touch, stylus, input, overview,
launcher, dock, quick-settings, notification, clipboard, and accessibility
surfaces to the existing shell. It keeps the standard Omarchy bar and other
plugins intact and stores user configuration and runtime state under the
namespaced `io.omanome.shell` / `omanome` paths.

## Screens and features

- An Omarchy Quattro manifest with `service`, `bar-widget`, and `panel` entry points. It never declares the replacement `bar` kind.
- A compact Omanome bar widget that is added to the existing Omarchy layout like any other widget.
- An adaptive Control Center popup and bar widget with one master switch,
  suspend/resume, compact toggles, module ordering, status OSD, and no second
  shell or replacement bar.
- One lazy-loaded panel with Overview, workspaces, launcher, quick settings, OSK, clipboard, notifications, and settings views.
- GNOME-like Overview with current-workspace-first mosaic windows, dynamic/fixed
  workspace strip, real app/window/settings/action search, and native activation.
- Tablet multitasking with Snap Assist halves, thirds, quarters, portrait
  layouts, bounded geometry previews, and Split View ratios/divider rollback.
- Window Groups and App Pairs with persistent layout intent, duplicate-window
  choice, floating/mini/PiP actions, and an explicit `ask` session-restore policy.
- Unified touchscreen gesture arbitration, a transient workspace switcher,
  user-owned shortcut conflict checks, and monitor hotplug recovery without
  per-frame geometry polling or subprocesses on drag events.
- A full adaptive App Grid with real desktop icons, shared favorites with Dock,
  recent ordering, categories, folders, drag reorder, context actions, and
  keyboard/touch navigation.
- A first-run setup flow for input mode, Dock placement, Overview, OSK, stylus,
  rotation, and privacy; upgrades from earlier versions skip it automatically.
- Settings 2.0 with searchable categories, deep links, portrait push navigation,
  live capability reasons, accessibility controls, safe diagnostics export, and
  an in-panel `omanome doctor` result view.
- Multi-signal Tablet Mode (Auto/Desktop/Tablet/Hybrid) using touch, stylus,
  physical keyboard, orientation, recent input, and a detected hardware switch;
  transitions update targets, Dock, window controls, and responsive density live.
- Capability-aware Quick Settings backed by live Wi-Fi/Bluetooth/PipeWire,
  brightness, power-profile, battery, and optional night-light/recording
  session probes; unavailable backends are visibly disabled.
- Native tablet capability inventory, an annotation overlay with undo/redo and
  screenshot/copy, and dynamic Hyprland touch/tablet/output transforms for
  manual rotation; sensor auto-rotation is optional.
- An optional multi-monitor Dash-to-Dock style surface using layer-shell and native `DesktopEntries`/foreign-toplevel objects, persisted favorites, running indicators, context actions, configurable position/mode, and intelligent autohide guardrails.
- Touch-sized active-window controls in tablet or hybrid mode.
- Tablet-mode detection from Hyprland device inventory, adaptive desktop/tablet/hybrid modes, stylus capability inventory, input hysteresis, responsive logical-size breakpoints, and touch gesture keyword integration through Hyprland IPC.
- Adaptive Auto/Desktop/Tablet/Hybrid profiles with presentation and gaming
  overrides, per-component policies, capability-based keyboard rules, and a
  Docked mode for external monitor plus keyboard setups.
- A universal Device Graph that records only capability-based, privacy-safe
  nodes, outputs, relationships, mappings, and Confirmed/Probable/Unknown
  confidence; the same graph feeds adaptive policy, diagnostics, and the
  Device Center.
- Device Profiles 2.0 for displays, touchscreens, styluses, and keyboards,
  kept separate from Adaptive Profiles and persisted with opaque identities that
  do not depend on \`/dev/input/eventN\`.
- A Hardware Calibration Center with guided five-point touch calibration,
  capability-gated stylus pressure/tilt/eraser/button checks, monitor/input
  mapping, preview/apply/cancel transactions, and last-known-good rollback.
- Hardware Setup Profiles for Tablet, Desk, Portable, Drawing, and Custom
  topologies, with bounded dock event coalescing, partial-match safety, surface
  continuity, and no surprise window moves or app launches.
- Event-driven UPower battery-source inventory and diagnostics. Multiple real
  sources remain separate, absent sources remain absent, and power signals never
  create a polling loop or a fabricated keyboard battery.
- English/Russian UI strings, profiles, versioned configuration, import/export/reset, and privacy-aware clipboard history for text and PNG images.
- Compositor-backed blur for Omanome layer surfaces through Hyprland layer rules, with per-surface settings, adaptive quality, battery/fullscreen policies, and application-rule exclusions. The standard Omarchy bar remains untouched by default.
- Native foreign-toplevel Coverflow Alt-Tab with grouping, workspace scope, shared animations, and a capability-gated live-preview path; this environment reports previews unavailable because no real compositor texture provider is exposed.
- Safe Force Quit mode with native close, PID-scoped TERM/KILL fallback, protected session processes, cancellation, and no name-based `pkill` behavior.
- Clipboard 2.0 with pinning, search, text edit, tags, image preview, retention/storage limits, per-app exclusions, clear-unpinned, password/secret MIME filtering, private mode, and stdin-only payload handling.
- Notification center grouping, timestamps, actions, touch/stylus swipe dismissal, per-app mute, and clear-group/all controls backed by Omarchy's native notification service.
- Optional compositor capability boundary: the companion provides a real bounded Wobbly mesh through Hyprland's public `IWindowTransformer` API when the exact ABI and GL renderer checks pass; Omanome integrates the real `omarchy-desktop-cube` API when loaded.
- A Wayland-native OSK surface driven by `wtype` (`virtual-keyboard-v1`), with English/Russian QWERTY, standard/floating/split/thumb/left-right one-handed layouts, numeric/symbols/emoji/editing layers, toolbar, key popup, long-press alternates, repeat settings, and a local handwriting canvas.
- A persistent native `omanome-input` transport with bounded JSON IPC, xkbcommon EN/RU state, event-driven input/display hotplug, capability-based keyboard identity, detachable/Bluetooth classification, and explainable posture hysteresis. `omanome input-info` reports the actual native protocol and explicit fallback state.
- Integration with Omarchy's native notification service for DND, popups, history, and dismissal.
- Diagnostics and lifecycle commands: status, doctor, logs, enable/disable,
  master/suspend/resume, mode-info, feature list/control, safe mode, devices,
  device info/test/reset/rollback, hardware graph, hardware setup list/status/
  apply, stylus-info, touch-info, sensor-info, capabilities, hardware-test,
  redacted support bundles, GitHub install/update checks, transactional
  rollback/recovery, and ownership-safe uninstall.

## Requirements

Runtime requirements are:

- Omarchy Quattro and its `omarchy-shell` plugin manager;
- Hyprland and Quickshell;
- a Wayland session with `wl-paste`/`wl-copy`;
- `wtype` for OSK text insertion.

Optional commands used only when available are `nmcli`, `bluetoothctl`, `wpctl`, `brightnessctl`, `grim`, `wf-recorder`, `gdbus`, and `iio-sensor-proxy`. Missing optional commands disable only their action.

## Install from GitHub

Install the public repository directly with the official Omarchy plugin manager:

```sh
omarchy plugin add https://github.com/pluseight8/omanome.git --enable --yes
omanome doctor
```

The convenience command is equivalent and uses the same official manager:

```sh
omanome install
```

In the graphical Omarchy Plugin Manager, open `Setup → Plugins → Add`, enter
`https://github.com/pluseight8/omanome.git`, review the manifest, and enable
`io.omanome.shell`. Omanome is a service/panel/bar-widget plugin, so the
standard Omarchy top bar remains the active bar; add the Omanome widget through
the normal bar layout if it is not already present.

If this checkout is being developed locally, run `./cli/omanome setup` and add the checkout through the local plugin mechanism supported by the installed Omarchy version. Omanome never invokes `sudo` and never edits files under `$OMARCHY_PATH`.

After installation, add the `Omanome` bar widget through Omarchy's normal bar settings if it is not already in the layout. This extends the existing bar; it does not replace it.

## Quick start

The widget opens the panel with the left mouse button, Quick Settings with the right button, and the keyboard view with the middle button. The panel can also be summoned by the host shell:

```sh
omarchy-shell shell summon io.omanome.shell '{"view":"overview"}'
omarchy-shell shell toggle io.omanome.shell '{"view":"quicksettings"}'
```

Use a user-owned Hyprland keybinding for those commands if desired. Omanome does not overwrite existing shortcuts silently.

For a first health check after installation:

```sh
omanome status
omanome capabilities
omanome doctor
```

Configuration is stored at `~/.config/omanome/config.json` (or `$XDG_CONFIG_HOME/omanome/config.json`). Runtime state and clipboard images are stored below `$XDG_STATE_HOME/omanome`. Clipboard capture skips sensitive/private state and password, secret, credential, token, and private-key MIME hints; payloads are never written to logs or command-line arguments.

## CLI

The wrapper is `./cli/omanome`; install or symlink it into a user `PATH` if desired.

```text
omanome status
omanome doctor
omanome logs
omanome reload
omanome enable | disable
omanome master on|off
omanome suspend | resume
omanome safe-mode
omanome setup
omanome install
omanome export-config [file]
omanome import-config <file>
omanome reset [--yes]
omanome update --check
omanome update
omanome update --dry-run --json
omanome rollback --list --json
omanome recover --json
omanome capabilities
omanome mode-info [--json]
omanome feature list [--json]
omanome feature enable|disable <id>
omanome input-info
omanome hardware-test --fixture tests/fixtures/hardware-tablet.json --json
omanome hardware-test --guided --session "$HOME/.local/state/omanome/hardware-session.json" --confirm-hardware --json
omanome diagnostics bundle [output.tar.gz] [--private]
omanome diagnostics export [output.tar.gz] [--private]
omanome stylus-info
omanome touch-info
omanome sensor-info
omanome devices
omanome device info <id>
omanome device test <id>
omanome device reset <id> --yes
omanome device rollback <id>
omanome hardware graph [--json]
omanome hardware-setup list|status
omanome hardware-setup apply <name>
omanome effects
omanome benchmark
omanome processes [--json]
omanome profiler [--json] [--interval 1]
omanome watchdog [--watch] [--json]
omanome performance reset|check [--json]
omanome companion status|doctor|build|install|rebuild|enable|disable
omanome uninstall [--purge-settings] [--yes]
```

`update --check` reports the installed and latest repository versions, current
and remote commits, update channel, and whether an update is available.
The default `stable` channel resolves the latest non-prerelease GitHub Release
tag; it does not follow arbitrary commits on `main`. `beta` follows the beta
branch, and `main` is an explicit development channel. Updates are never
installed without an explicit `omanome update` command.
`update` verifies that the installed checkout points at the official GitHub
origin, journals each phase, creates a user-owned rollback copy, then calls
Omarchy's standard plugin updater. It validates the installed checkout before
reloading the shell and restores the rollback point automatically if validation
fails. An interrupted journal is recovered before another update or uninstall.
`rollback --list --json` inventories snapshots without changing them.
`uninstall --dry-run --json` previews exact owned paths; a verified ownership
manifest and symlink checks prevent broad deletion. `uninstall --yes` removes
only Omanome's plugin, companion data, cache, state, and optionally settings;
it does not remove Omarchy, the standard bar, other plugins, themes, or user
Hyprland files.

mode-info explains the selected profile, effective mode, keyboard posture,
Docked state, and transition reason. feature list exposes the effective
availability of each registered feature and keeps user preference separate from
temporary profile or safety suppression. master off and suspend release the
native input boundary before stopping optional surfaces; resume restores the
runtime state without rewriting the user's configuration.

## Performance, ownership and high-CPU triage

The runtime has one explicit ownership boundary: Omanome-owned helpers carry
`OMANOME_OWNER=io.omanome.shell` and are recorded with PID plus start-time
identity. `omanome processes` and the Settings performance page inspect only
that boundary. Foreign processes with a similar executable name, including
unmarked `lua`, are excluded and are never attributed to Omanome.

Use the following commands when investigating a report:

```sh
omanome processes --json
omanome benchmark --json
omanome watchdog --watch --json
omanome profiler [--json] [--interval 1]
```

The process snapshot separates Omanome CPU from system CPU. The deterministic
benchmark measures config projection and JSON round-trips; it is not a claim
about frame rate or idle CPU. The watchdog is notify-only: it requires a
sustained owner threshold, applies no signal, and never terminates a process.
For an unowned high-CPU process, inspect its executable, command line, and
parent chain and report it to the owning package or service. Do not use a
name-based command such as `pkill lua`.

Performance modes are `automatic`, `quality`, `balanced`, `performance`, and
`battery-saver`. Automatic mode uses available power, thermal, fullscreen, and
GPU signals; missing hardware telemetry does not become a fake metric. Expensive
preview streams are budgeted, panel views are lazy, search is debounced, and
closed panel views release their live preview resources. Legacy schema-2
`performance.qualityPreset` values migrate to `performance.mode`.

## Adaptive Mode and Control Center

Adaptive Mode is a runtime policy layer over the existing tablet, input,
multitasking, Dock, Overview, OSK, gesture, and accessibility models. Auto
selects a stable desktop/tablet/hybrid posture from capability and posture
signals; Desktop, Tablet, and Hybrid are explicit profiles. Presentation,
gaming, and custom profiles can override individual component behavior without
copying or replacing the global configuration.

The Control Center has one master enable/disable switch and a separate
suspend/resume boundary. Both are reversible: disabling or suspending releases
native input safely, stops adaptive transitions, and leaves the standard Omarchy
bar and shell running. Runtime mode changes, hotplug events, transition previews,
and temporary safety suppression are not persisted as user settings. A
debounced, event-driven device stream handles keyboard/display changes without
polling loops or a subprocess per event.

Keyboard policy uses capability-based, opaque identifiers. Device rules can
remember a built-in, USB, detachable, or Bluetooth behavior without exposing a
full Bluetooth address, serial number, raw device path, typed text, or window
title in status or diagnostics. omanome diagnostics export --private applies
the stricter local redaction policy and never uploads the archive.

Docked mode is selected from external-monitor and keyboard capability signals.
It can apply a desktop profile while preserving internal touch, and undocking
restores the last stable Auto state when configured. If a monitor, keyboard, or
compositor capability is absent, the affected action reports Unavailable;
portable fixtures remain Untested and are never hardware certification.

## Hardware and devices

The Device Center exposes the universal graph, relevant displays and input
devices, mappings, calibration state, hardware setups, battery sources, and
diagnostics. Device Profiles are per-device settings; Adaptive Profiles remain
the Desktop/Tablet/Hybrid policy layer. Relations and display mappings are
shown as Confirmed, Probable, or Unknown, and an explicit user mapping always
wins over inference.

Calibration is guided and reversible. Touch uses five real targets and first
checks for a wrong-display mapping; stylus pressure, tilt, proximity, eraser,
and buttons appear only when the backend reports those capabilities. Apply
keeps the prior mapping as a last-known-good snapshot, waits for confirmation,
and restores it on timeout or disconnect. \`omanome recover\` and safe mode
ignore custom device automation when the stored mapping is not healthy.

\`omanome hardware graph --json\` and \`omanome devices --json\` are safe export
boundaries: raw serials, MAC addresses, syspaths, event nodes, typed text, and
window titles are not emitted. Hardware fixtures and portable CI prove
contracts only. They do not certify a physical touchscreen, stylus, monitor,
keyboard, sensor, or dock.

## Stylus and tablet behavior

Omanome detects Hyprland's `touch` and `tablets` inventories from explicit device types/capabilities and trusted backend groups; it does not classify styluses from vendor-name substrings. Diagnostics expose pressure, tilt X/Y, rotation, distance, proximity, eraser, buttons, serial, backend, and mapped output only when reported. Native client tablet events remain native: Omanome does not replace pressure/tilt/eraser events with synthetic mouse motion. Pressure curves, palm-rejection policy, monitor mapping, and button actions are configuration surfaces for the input companion described in `stylus/README.md`.

The OSK uses `wtype` and is intentionally safe when it is unavailable. Automatic appearance on a focused text field and persistent cursor/repeat input require an optional native text-input/virtual-input companion; the current panel can always be opened explicitly. Handwriting recognition is a local, pluggable slot and is not enabled by a cloud service.

Rotation prefers `monitor-sensor`, then the iio-sensor-proxy D-Bus API through a persistent signal monitor. Manual rotation works independently. Dynamic monitor names and device mappings are used; a synchronized batch is rolled back if Hyprland rejects it.

## Limitations and honest status

Portable CI and the included hardware fixture validate contracts and fallback
behavior; they are not physical touchscreen, stylus, sensor, multi-monitor, or
loaded-companion certification. Native OSK and text-focus behavior depends on
the compositor protocols and `wtype` being available. Handwriting recognition
is local and provider-based, with no cloud service enabled by default. Live
window previews, Wobbly, and Cube remain unavailable when their real compositor
stream, exact companion ABI, GL backend, or external cube backend is absent;
each path fails closed and leaves the normal shell usable.

## Advanced

See [`docs/FEATURES.md`](docs/FEATURES.md) for the feature truth matrix,
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for recovery procedures,
and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/TESTING.md`](docs/TESTING.md),
and [`docs/HARDWARE.md`](docs/HARDWARE.md) for integration boundaries,
acceptance evidence, and the manual hardware matrix.

## Development

```sh
make check
```

The check runs repository validation, shell syntax checks, Python tests including hardware-independent input fixtures, Omarchy's native manifest validator when available, and Qt `qmllint` against the installed Omarchy QML modules. Warnings from `qmllint` about dynamically injected Omarchy properties are expected; syntax and fatal errors fail the command. Hardware checks are documented separately in the manual matrix and are never marked as passed by portable CI.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/TESTING.md`](docs/TESTING.md), and [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) for the plugin contract, coexistence rules, test matrix, performance evidence, and safe integration boundaries.

## 1.0 native input, stylus, lifecycle and safety boundaries

Blur is applied through Hyprland layer-rule IPC to Omanome namespaces; it is not a translucent-rectangle imitation. Coverflow selects real Hyprland foreign-toplevel objects and activates them through native APIs. Live previews stay disabled unless the running Quickshell/companion exposes an actual texture provider. Force Quit starts with the selected foreign window's native close request and only falls back to the selected numeric PID; session processes are protected and no process-name broadcast is used.

The optional `omanome-hypr` companion uses the exact Hyprland API hash handshake and the public `IWindowTransformer` workbuffer path for Wobbly. It is fail-closed on non-GL backends, rotated outputs, X11 windows, shader/buffer errors, lifecycle markers, ABI/version mismatches, or missing artifacts. Wobbly can be controlled with `hyprctl -j omanome-effects wobbly enable|disable` and configured with bounded `key=value` arguments; the QML setting debounces those commands and applies the same mesh/physics values. The advanced-effects master switch plus battery/fullscreen policy bypass expensive render hooks. The true Desktop Cube is integrated through the separately maintained, version-matched `omarchy-desktop-cube` backend when it is loaded; Omanome does not duplicate its renderer. Without that external backend, cube controls remain unavailable. Omanome never animates screenshots and never loads an unpinned Hyprland `.so`.

The 1.0 input stack retains the 0.8 lifecycle policy: bounded subprocess backoff, crash-loop suppression,
one owned command lane, debounced persistence, slow/event-driven fallbacks,
owner-only snapshots, and explicit release of preview delegates on panel close.
The native `omanome-input` path uses `zwp_virtual_keyboard_v1` when available,
the compositor's real text-focus protocol when available, and an explicit
`wtype` fallback only when enabled by policy. OSK 3.0 keeps prediction and
autocorrect local and bounded; surrounding/password text is never persisted or
logged. Tablet-v2 pressure, tilt, distance, rotation, eraser, buttons,
proximity, output mapping, suspend/resume, and rollback are capability-driven;
handwriting ink is local and recognition remains explicitly unavailable until a
provider is selected. App-grid
favorites/folders are persisted locally; compositor-level drag semantics remain
scoped to real app metadata. Auto-rotation remains manual-only when neither
sensor backend is present.

These limitations are isolated: Omanome still loads without them, and `omanome safe-mode`/`omanome disable` returns to the normal Omarchy shell immediately.

## License

MIT. See [`LICENSE`](LICENSE).
