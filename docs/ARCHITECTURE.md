# Omanome architecture

## Host contract

Omanome targets the Quattro plugin contract shipped by Omarchy. The manifest declares three entry points:

| Entry point | Role |
| --- | --- |
| `shell/Service.qml` | one shared headless service, IPC target, config/state owner, optional dock/control loaders |
| `shell/BarWidget.qml` | ordinary widget registered in the existing Omarchy bar |
| `shell/Panel.qml` | one on-demand panel whose views are lazy-loaded |

The manifest deliberately has no `bar` kind. The plugin therefore cannot become the active replacement bar. It also does not modify `$OMARCHY_PATH`, another plugin manifest, or the user's Hyprland configuration.

## Process and state model

The Omarchy shell creates the service and injects `shell` and `manifest`. The panel is created by the existing panel loader. Dock and window controls are QML `Loader` children of the service and use layer-shell `PanelWindow`; they are not separate Quickshell processes.

The only global IPC name is `io.omanome.shell`. The service owns configuration migration and persistence at `XDG_CONFIG_HOME/omanome/config.json`. Clipboard state is separate below `XDG_STATE_HOME/omanome`, with images content-addressed by SHA-256. Clipboard capture uses stdin and JSON records; secrets are never put in process arguments or diagnostic output.

## Public APIs used

- `DesktopEntries.applications` for launcher/dock entries;
- `ToplevelManager` and `Hyprland.workspaces` for overview and active-window controls;
- `hyprctl ... -j` and `hyprctl keyword` for device discovery and stable compositor IPC;
- `wtype` for the optional virtual-keyboard-v1 insertion path;
- Omarchy's first-party notification service for DND/history/popups;
- `PanelWindow`/`WlrLayershell` for non-exclusive overlays.

Quick Settings uses one coalesced session probe (`input/system-state.sh`) and
small on-demand Wi-Fi/Bluetooth scanners. Those scripts return JSON snapshots;
the QML service never keeps a guessed local toggle as the source of truth and
marks unavailable backends explicitly.

The plugin is intentionally capability-aware. Missing `wtype`, `nmcli`, Bluetooth, brightness, screenshot, sensor, or optional compositor support disables only the affected action.

## Compatibility rules

The standard bar remains untouched except for a normal registered `bar-widget`, and its presence is optional. All other plugins continue to be discovered and loaded by Omarchy's own registry. Omanome uses no singleton names shared with the rest of the shell and never silently rewrites shortcut or plugin state.

## Companion boundary

`hypr/README.md`, `input/README.md`, and `stylus/README.md` document the boundaries for future companions. A real wobbly renderer or workspace cube must be version-pinned to a compatible Hyprland ABI and fail closed. Until that companion exists, the settings report those effects as unavailable instead of displaying a QML imitation of a compositor transform.
