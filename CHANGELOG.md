# Changelog

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
