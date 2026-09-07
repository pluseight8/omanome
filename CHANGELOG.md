# Changelog

## 0.5.0

- Adds a versioned optional `omanome-hypr` Wobbly renderer using Hyprland's
  public `IWindowTransformer` workbuffer boundary, bounded mesh physics, and a
  real GL shader/VAO/VBO path with transparent fail-closed fallback.
- Adds explicit `wobbly enable|disable` status IPC, QML Settings integration,
  lifecycle-aware companion reporting, and tests for the public renderer
  boundary and unsafe-loader invariants.
- Adds live `ScreencopyView` sources for window previews; previews report
  available only after a compositor-owned stream has content.
- Keeps Desktop Cube capability-gated to the separately maintained,
  version-matched external backend.

## 0.4.0

- Adds real Hyprland layer-rule blur for Omanome surfaces with per-surface
  configuration, adaptive quality, fullscreen/battery policies, and app rules.
- Adds native foreign-toplevel Coverflow Alt-Tab and shared animation/performance
  models; live previews remain capability-gated until a real texture provider exists.
- Adds compositor-only cube integration through the external `omarchy-desktop-cube`
  API and keeps wobbly fail-closed without a compatible native renderer.
- Adds safe Force Quit with native close, PID-scoped TERM/KILL fallback,
  protected session processes, cancellation, and tests for the safety boundary.
- Adds clipboard pinning, tags, text editing, image preview, retention/storage
  controls, app exclusions, sensitive MIME filtering, and clear-unpinned.
- Adds grouped native notification-center views with timestamps, actions,
  swipe dismissal, per-app mute, and clear-group/all controls.
- Adds companion ABI/crash-marker diagnostics, 0.4 Settings/About capability
  reporting, effects/benchmark CLI diagnostics, and CI coverage.

## 0.3.0

- Expands the Wayland OSK with standard, floating, split, thumb, left/right
  one-handed, numeric, symbols, emoji, editing, and handwriting surfaces.
- Adds a local data model for toolbar actions, emoji categories/recent items,
  alternate-character long press, key popup, Shift/Caps behavior, backspace
  repeat settings, floating position, split geometry, and configurable height.
- Adds capability/type-based stylus discovery with pressure, tilt X/Y, rotation,
  distance, proximity, eraser, buttons, serial, backend, and mapped-output
  diagnostics; no vendor-name stylus detection is used.
- Adds an event-driven iio-sensor-proxy D-Bus fallback when monitor-sensor is
  absent, sensor-info/touch-info, and atomic synchronized rotation with
  dynamic output selection and rollback on failure.
- Adds fullscreen touch-gesture conflict policy and adaptive target-size
  diagnostics without modifying touchpad gesture settings.
- Keeps text-field auto-show, persistent input, handwriting recognition, and
  stylus button-event mapping explicitly gated until an optional native backend
  is installed; no cloud service, telemetry, X11, or hidden sudo is added.

## 0.2.0

- Documents direct GitHub installation and the graphical Omarchy Plugin Manager flow.
- Adds `omanome install` and official-origin-aware `update --check` output with
  installed/latest versions, commits, channel, and rollback-safe updates.
- Expands the dock/launcher/overview configuration contract for favorites,
  running indicators, dynamic workspaces, autohide, and touch-friendly actions.
- Adds portable CI and regression-test coverage for installation, configuration,
  and plugin coexistence invariants.

## 0.1.0

- Initial Omarchy Quattro plugin baseline.
- Uses the existing Omarchy bar through a namespaced, optional `bar-widget`.
- Adds a single-process service and panel for overview, launcher, quick settings,
  clipboard history, and a Wayland-native `wtype` keyboard surface.
- Quick Settings now reads live Wi-Fi, Bluetooth, PipeWire, brightness,
  power-profile, battery, night-light, and recording capabilities; network
  discovery and controls are disabled cleanly when their backend is absent.
- Expands the Wayland OSK with a number row, Caps Lock, one-shot Ctrl/Alt/Super,
  arrows/function layer, and compact floating/one-handed layouts.
- Adds a lazy annotation overlay with pen/highlighter/eraser, undo/redo,
  screenshot/copy, and dynamic Hyprland touch/tablet/output rotation transforms.
- Adds real PipeWire output/input selection and trims trailing empty dynamic
  workspaces to one available workspace.
- Adds an optional multi-monitor dock, touch-sized active-window controls, and a
  notification-center view backed by Omarchy's existing notification service.
- Adds versioned configuration, migrations, diagnostics, rollback, and safe-mode
  CLI flows.
- Deliberately leaves compositor-level wobbly windows and desktop cube disabled
  until a version-pinned Hyprland companion is available.
