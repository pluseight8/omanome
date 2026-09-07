# Omanome

Omanome is an open-source, GNOME-inspired touch and stylus enhancement suite for the current Omarchy Quattro shell on Hyprland. It is intentionally an Omarchy plugin, not a replacement desktop session: the standard Omarchy bar remains in charge of the top edge, the existing Quickshell process hosts the plugin, and all plugin state is namespaced under `io.omanome.shell`.

This repository is the runnable 0.8.0 phase. It uses public Omarchy/Quickshell/Hyprland interfaces for the core and explicit, version-aware optional compositor integrations for advanced effects. Features without a real backend remain visibly unavailable rather than becoming fake overlays.

## What is included

- An Omarchy Quattro manifest with `service`, `bar-widget`, and `panel` entry points. It never declares the replacement `bar` kind.
- A compact Omanome bar widget that is added to the existing Omarchy layout like any other widget.
- One lazy-loaded panel with Overview, workspaces, launcher, quick settings, OSK, clipboard, notifications, and settings views.
- GNOME-like Overview with current-workspace-first mosaic windows, dynamic/fixed
  workspace strip, real app/window/settings/action search, and native activation.
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
- Diagnostics and lifecycle commands: status, doctor, logs, enable/disable, safe mode, devices, stylus-info, touch-info, sensor-info, capabilities, hardware-test, redacted support bundles, GitHub install/update checks, transactional rollback/recovery, and ownership-safe uninstall.

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

## Use

The widget opens the panel with the left mouse button, Quick Settings with the right button, and the keyboard view with the middle button. The panel can also be summoned by the host shell:

```sh
omarchy-shell shell summon io.omanome.shell '{"view":"overview"}'
omarchy-shell shell toggle io.omanome.shell '{"view":"quicksettings"}'
```

Use a user-owned Hyprland keybinding for those commands if desired. Omanome does not overwrite existing shortcuts silently.

Configuration is stored at `~/.config/omanome/config.json` (or `$XDG_CONFIG_HOME/omanome/config.json`). Runtime state and clipboard images are stored below `$XDG_STATE_HOME/omanome`. Clipboard capture skips sensitive/private state and password, secret, credential, token, and private-key MIME hints; payloads are never written to logs or command-line arguments.

## CLI

The wrapper is `./cli/omanome`; install or symlink it into a user `PATH` if desired.

```text
omanome status
omanome doctor
omanome logs
omanome reload
omanome enable | disable
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
omanome input-info
omanome hardware-test --fixture tests/fixtures/hardware-tablet.json --json
omanome diagnostics bundle [output.tar.gz]
omanome stylus-info
omanome touch-info
omanome sensor-info
omanome devices
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

## Stylus and tablet behavior

Omanome detects Hyprland's `touch` and `tablets` inventories from explicit device types/capabilities and trusted backend groups; it does not classify styluses from vendor-name substrings. Diagnostics expose pressure, tilt X/Y, rotation, distance, proximity, eraser, buttons, serial, backend, and mapped output only when reported. Native client tablet events remain native: Omanome does not replace pressure/tilt/eraser events with synthetic mouse motion. Pressure curves, palm-rejection policy, monitor mapping, and button actions are configuration surfaces for the input companion described in `stylus/README.md`.

The OSK uses `wtype` and is intentionally safe when it is unavailable. Automatic appearance on a focused text field and persistent cursor/repeat input require an optional native text-input/virtual-input companion; the current panel can always be opened explicitly. Handwriting recognition is a local, pluggable slot and is not enabled by a cloud service.

Rotation prefers `monitor-sensor`, then the iio-sensor-proxy D-Bus API through a persistent signal monitor. Manual rotation works independently. Dynamic monitor names and device mappings are used; a synchronized batch is rolled back if Hyprland rejects it.

## Development

```sh
make check
```

The check runs repository validation, shell syntax checks, Python tests including hardware-independent input fixtures, Omarchy's native manifest validator when available, and Qt `qmllint` against the installed Omarchy QML modules. Warnings from `qmllint` about dynamically injected Omarchy properties are expected; syntax and fatal errors fail the command. Hardware checks are documented separately in the manual matrix and are never marked as passed by portable CI.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/TESTING.md`](docs/TESTING.md), and [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) for the plugin contract, coexistence rules, test matrix, performance evidence, and safe integration boundaries.

## 0.8 compositor, lifecycle and safety boundaries

Blur is applied through Hyprland layer-rule IPC to Omanome namespaces; it is not a translucent-rectangle imitation. Coverflow selects real Hyprland foreign-toplevel objects and activates them through native APIs. Live previews stay disabled unless the running Quickshell/companion exposes an actual texture provider. Force Quit starts with the selected foreign window's native close request and only falls back to the selected numeric PID; session processes are protected and no process-name broadcast is used.

The optional `omanome-hypr` companion uses the exact Hyprland API hash handshake and the public `IWindowTransformer` workbuffer path for Wobbly. It is fail-closed on non-GL backends, rotated outputs, X11 windows, shader/buffer errors, lifecycle markers, ABI/version mismatches, or missing artifacts. Wobbly can be controlled with `hyprctl -j omanome-effects wobbly enable|disable` and configured with bounded `key=value` arguments; the QML setting debounces those commands and applies the same mesh/physics values. The advanced-effects master switch plus battery/fullscreen policy bypass expensive render hooks. The true Desktop Cube is integrated through the separately maintained, version-matched `omarchy-desktop-cube` backend when it is loaded; Omanome does not duplicate its renderer. Without that external backend, cube controls remain unavailable. Omanome never animates screenshots and never loads an unpinned Hyprland `.so`.

The 0.8 lifecycle policy adds bounded subprocess backoff, crash-loop suppression,
one owned command lane, debounced persistence, slow/event-driven fallbacks,
owner-only snapshots, and explicit release of preview delegates on panel close.
OSK repeat stops on release, rotation and clipboard watchers do not restart in a
tight loop, and optional wobbly control fails closed when the companion is not
available. Automatic text-field focus detection, persistent virtual input, local
handwriting recognition, and stylus button-event mapping remain explicitly
gated until their corresponding public backend is selected. App-grid
favorites/folders are persisted locally; compositor-level drag semantics remain
scoped to real app metadata. Auto-rotation remains manual-only when neither
sensor backend is present.

These limitations are isolated: Omanome still loads without them, and `omanome safe-mode`/`omanome disable` returns to the normal Omarchy shell immediately.

## License

MIT. See [`LICENSE`](LICENSE).
