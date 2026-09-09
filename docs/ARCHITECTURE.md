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

The only global IPC name is `io.omanome.shell`. The service owns configuration migration and persistence at `XDG_CONFIG_HOME/omanome/config.json`. Clipboard state is separate below `XDG_STATE_HOME/omanome`, with images content-addressed by SHA-256. Clipboard capture uses stdin and JSON records; sensitive MIME hints are rejected before persistence, and secrets are never put in process arguments or diagnostic output. Pinning, tags, retention, storage limits, and per-app exclusions are applied by `shell/models/Clipboard.js`.

The CLI updater is a user-owned transaction boundary. It records a JSON journal
under `XDG_STATE_HOME/omanome/transactions`, creates a bounded rollback snapshot
before invoking Omarchy's official updater, validates the resulting checkout,
and restores the snapshot on update or health-check failure. A pending journal is
recovered before a later update, rollback, or uninstall. Failed replacements are
kept under `failed-updates` for inspection rather than silently discarded.
Configuration migration is explicit and atomic: invalid or future schemas are
not overwritten, while known older schemas migrate into schema 2. The ownership
manifest records only exact Omanome paths; uninstall refuses mismatches,
symlinks, and broad roots, and offers a no-write dry-run plan.

## Adaptive state model

The Control Center, Feature State Registry, Adaptive Mode, keyboard transition
model, and Docked Mode share one service-owned runtime state boundary. Durable
configuration contains user preferences, profile overlays, device rules, and
escape-hatch toggles; detected posture, transition phases, preview state,
temporary suppression, and hotplug snapshots remain in memory. Automatic
transitions therefore do not churn the config file or create a new profile.

Device and display changes arrive through one event-driven monitor and a
debounced refresh lane. Keyboard identity is capability-based and opaque:
status and support output receives only stable hashed identifiers and safe
classification fields. The master-off and suspend paths cancel pending
transitions and release native input before optional surfaces are disabled.
Resume rehydrates runtime state from the existing config without changing the
user's settings.

## Device intelligence model

The 1.3 Device Graph is the shared inventory for displays, touchscreens,
styluses, tablet pads, keyboards, docks, batteries, and audio devices. It
keeps explicit parent, attachment, mapping, and reporting relationships with
`confirmed`, `probable`, or `unknown` confidence. Public status uses opaque
device/output identifiers and bounded capability fields; raw syspaths, event
nodes, serials, MAC addresses, and UPower object paths stay inside the input
boundary.

Device Profiles 2.0, Hardware Setup Profiles, and Adaptive overlays are separate
state layers. A guided calibration writes only validated mappings and retains
one persistent last-known-good value. Timeout, disconnect, invalid output, or
ambiguous display identification rolls back the active transaction. Dock
continuity stores only bounded layout intent and requires an explicit choice
when a safe output cannot be inferred.

Power state is sourced from real UPower signals, with at most 16 separate
battery/UPS sources and a conservative primary-source decision. Data-driven
quirks are diagnostics-only: structural matches remain visible, while critical
mapping notes are blocked until a separate user confirmation. Safe mode ignores
custom calibration, device automation, setup overlays, and quirk actions.

## Public APIs used

- `DesktopEntries.applications` for launcher/dock entries;
- `ToplevelManager` and `Hyprland.workspaces` for overview and active-window controls;
- `hyprctl ... -j` and `hyprctl keyword` for device discovery and stable compositor IPC;
- `wtype` for the optional virtual-keyboard-v1 insertion path;
- Omarchy's first-party notification service for DND/history/popups; Omanome only groups and presents its native popup model and never starts a second notification daemon;
- `PanelWindow`/`WlrLayershell` for non-exclusive overlays.

Quick Settings uses one coalesced session probe (`input/system-state.sh`) and
small on-demand Wi-Fi/Bluetooth scanners. Those scripts return JSON snapshots;
the QML service never keeps a guessed local toggle as the source of truth and
marks unavailable backends explicitly.

The annotation overlay is a lazy `PanelWindow` owned by the same service. Its
Canvas stores only the current in-memory strokes and closes to release the
overlay. Rotation uses runtime Hyprland input transforms and monitor names
returned by `hyprctl monitors -j`; mapped outputs are preferred, then focused
or primary dynamic outputs. Touch, tablet, and monitor transforms are sent in
one batch and a failed batch triggers a rollback batch. Sensor rotation is a
persistent event stream: `monitor-sensor` is preferred and
`net.hadess.SensorProxy` D-Bus signals are the fallback.

The plugin is intentionally capability-aware. Missing `wtype`, `nmcli`, Bluetooth, brightness, screenshot, sensor, persistent input, compositor blur, live preview, or optional effect support disables only the affected action. Force Quit is a separate PID-scoped safety path: it starts with native foreign-toplevel close and rejects protected session processes.

## Compatibility rules

The standard bar remains untouched except for a normal registered `bar-widget`, and its presence is optional. All other plugins continue to be discovered and loaded by Omarchy's own registry. Omanome uses no singleton names shared with the rest of the shell and never silently rewrites shortcut or plugin state.

## Companion boundary

`hypr/README.md`, `input/README.md`, and `stylus/README.md` document the companion boundaries. The optional `omanome-hypr` handshake is exact-ABI and protocol-version aware; a pending load marker blocks an automatic retry after an incomplete load. Its Wobbly path uses only Hyprland's public `IWindowTransformer` workbuffer API and a bounded GL mesh, with the original framebuffer retained on every failed precondition. The real external `omarchy-desktop-cube` backend is detected and called through its documented Lua API. Settings report these states instead of displaying a QML imitation of a compositor transform.
