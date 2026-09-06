# Omanome

Omanome is an open-source, GNOME-inspired touch and stylus enhancement suite for the current Omarchy Quattro shell on Hyprland. It is intentionally an Omarchy plugin, not a replacement desktop session: the standard Omarchy bar remains in charge of the top edge, the existing Quickshell process hosts the plugin, and all plugin state is namespaced under `io.omanome.shell`.

This repository is a runnable 0.2.0 baseline. It focuses on the parts that can be implemented safely with the public Omarchy/Quickshell/Hyprland interfaces. Features that require a compositor ABI or a text-input/handwriting engine are explicit optional integration points rather than fake overlays.

## What is included

- An Omarchy Quattro manifest with `service`, `bar-widget`, and `panel` entry points. It never declares the replacement `bar` kind.
- A compact Omanome bar widget that is added to the existing Omarchy layout like any other widget.
- One lazy-loaded panel with Overview, workspaces, launcher, quick settings, OSK, clipboard, notifications, and settings views.
- An optional multi-monitor Dash-to-Dock style surface using layer-shell and native `DesktopEntries`/foreign-toplevel objects, persisted favorites, running indicators, context actions, configurable position/mode, and intelligent autohide guardrails.
- Touch-sized active-window controls in tablet or hybrid mode.
- Tablet-mode detection from Hyprland device inventory, adaptive desktop/tablet/hybrid modes, stylus capability inventory, and touch gesture keyword integration through Hyprland IPC.
- English/Russian UI strings, profiles, versioned configuration, import/export/reset, and privacy-aware clipboard history for text and PNG images.
- A Wayland-native OSK surface driven by `wtype` (`virtual-keyboard-v1`), with English, Russian, numeric, floating, split, one-handed, and handwriting-panel modes.
- Integration with Omarchy's native notification service for DND, popups, history, and dismissal.
- Diagnostics and lifecycle commands: status, doctor, logs, enable/disable, safe mode, GitHub install/update checks, rollback, and uninstall.

## Requirements

Runtime requirements are:

- Omarchy Quattro and its `omarchy-shell` plugin manager;
- Hyprland and Quickshell;
- a Wayland session with `wl-paste`/`wl-copy`;
- `wtype` for OSK text insertion.

Optional commands used only when available are `nmcli`, `bluetoothctl`, `wpctl`, `brightnessctl`, `grim`, `wf-recorder`, and `iio-sensor-proxy`. Missing optional commands disable only their action.

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

Configuration is stored at `~/.config/omanome/config.json` (or `$XDG_CONFIG_HOME/omanome/config.json`). Runtime state and clipboard images are stored below `$XDG_STATE_HOME/omanome`. Clipboard capture skips `CLIPBOARD_STATE=sensitive`, password/secret MIME hints, and private mode; payloads are never written to logs or command-line arguments.

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
omanome rollback
omanome stylus-info
omanome devices
omanome uninstall [--purge-settings] [--yes]
```

`update --check` reports the installed and latest repository versions, current
and remote commits, update channel, and whether an update is available.
`update` verifies that the installed checkout points at the official GitHub
origin, creates a user-owned rollback copy, then calls Omarchy's standard
plugin updater. It validates the installed checkout before reloading the shell
and restores the rollback point automatically if validation fails. `rollback`
restores the newest snapshot. `uninstall --yes` removes only Omanome's plugin,
cache, state, and optional settings; it does not remove Omarchy, the standard
bar, other plugins, themes, or user Hyprland files.

## Stylus and tablet behavior

Omanome detects Hyprland's `touch` and `tablets` inventories without assuming a vendor, monitor name, serial number, or set of capabilities. Native client tablet events remain native: Omanome does not replace pressure/tilt/eraser events with synthetic mouse motion. Pressure curves, palm-rejection policy, monitor mapping, and button actions are configuration surfaces for the input companion described in `stylus/README.md`.

The OSK uses `wtype` and is intentionally safe when it is unavailable. Automatic appearance on a focused text field requires a compositor text-input focus provider; the current panel can always be opened explicitly. Handwriting recognition is a local, pluggable slot and is not enabled by a cloud service.

## Development

```sh
make check
```

The check runs repository validation, shell syntax checks, Python tests, Omarchy's native manifest validator when available, and Qt `qmllint` against the installed Omarchy QML modules. Warnings from `qmllint` about dynamically injected Omarchy properties are expected; syntax and fatal errors fail the command.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/TESTING.md`](docs/TESTING.md) for the plugin contract, coexistence rules, test matrix, and safe integration boundaries.

## Deliberate limitations

The current public Omarchy/Hyprland APIs do not provide a portable way for a third-party QML plugin to implement compositor-rendered wobbly windows or a true 3D workspace cube. Omanome leaves both disabled and reports why in Settings/status; it does not animate screenshots and does not load an unpinned Hyprland `.so`. Live window thumbnails, automatic text-field focus detection, sensor-driven rotation, local handwriting recognition, and full drag-and-drop app-grid persistence are likewise extension points until their corresponding public backend is selected.

These limitations are isolated: Omanome still loads without them, and `omanome safe-mode`/`omanome disable` returns to the normal Omarchy shell immediately.

## License

MIT. See [`LICENSE`](LICENSE).
