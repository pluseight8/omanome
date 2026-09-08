# Changelog

## 1.2.0

### Highlights

- Delivers the Adaptive Mode release while preserving the existing Omarchy bar,
  Quickshell host, Hyprland ownership, accessibility settings, stylus paths,
  Dock, Overview, and tablet multitasking.
- Adds an adaptive Control Center with one master toggle, suspend/resume,
  compact toggles, configurable modules, status OSD, and explicit escape
  hatches for manual control.

### Adaptive Mode

- Adds Auto, Desktop, Tablet, Hybrid, Presentation, Gaming, and Custom profile
  policy with per-component behavior, feature-state precedence, and temporary
  previews that never become durable configuration.
- Adds capability-based keyboard classification for built-in, USB, detachable,
  and Bluetooth devices, explainable attach/detach transitions, keyboard rules,
  and bounded stability/debounce handling.
- Adds Docked mode for external monitor and keyboard combinations, preserving
  internal touch when configured and restoring the last stable Auto state after
  undocking.
- Keeps all transition choreography event-driven and reversible: hotplug flaps,
  transition reversal, master-off, suspend, and resume release native input
  safely without competing animations or config churn.

### Lifecycle, privacy, and validation

- Completes the 1.1 to 1.2 configuration migration by adding Control Center and
  Adaptive defaults while preserving existing multitasking, input, performance,
  accessibility, stylus, Dock, Overview, and general profile values.
- Rollback restores the exact pre-migration configuration bytes and removes
  newly introduced adaptive state when returning to the previous checkout.
- Status, feature, and mode diagnostics expose opaque device summaries only;
  private support export applies stricter redaction for device paths, Bluetooth
  addresses, serials, names, typed text, clipboard values, and window titles.
- Adds a 100-event hotplug regression guard and portable adaptive fixture gate.
  Fixture scenarios remain Untested and never count as physical hardware
  certification.
- Synchronizes the manifest, native helper, optional companion, README files,
  release runbook, compatibility snapshot, and lifecycle fixtures at 1.2.0.

## 1.1.0

### Highlights

- Delivers the tablet multitasking release while preserving the standard
  Omarchy bar, the existing Quickshell host, and normal Hyprland ownership.
- Adds portable safety evidence for snap, split, group, gesture, workspace,
  and multi-monitor state without claiming GUI or physical-device certification.

### Multitasking

- Adds bounded Snap Assist layout families for halves, thirds, quarters,
  portrait, gaps, reserved bar space, fractional scale, and minimum geometry.
- Adds Split View with a large divider handle, clamped ratios, portrait
  conversion, second-window selection, and transaction rollback on rejection.
- Connects Dock, Overview, and App Grid drops to split slots with deterministic
  application matching and no arbitrary app insertion.
- Adds floating, mini-window, picture-in-picture, edge-snap, and per-monitor
  placement policies through explicit context actions.

### Window groups and App Pairs

- Adds bounded Omanome-managed Window Groups and App Pairs with duplicate-window
  choice, close/break handling, workspace movement, persistence, and monitor
  recovery.
- Session restore remains `ask` by default; metadata stores app identities and
  layout intent, never live PIDs, addresses, titles, or stale window handles.

### Gestures

- Adds one event-driven gesture coordinator for touchscreen navigation, edge
  actions, workspace switching, Overview, Dock, Quick Settings, and back.
- Keeps touchpad gestures opt-in and separate from touchscreen policy, with
  thresholds, velocity, hysteresis, cancellation, reduced-motion handling,
  fullscreen/game/drawing-app suppression, and presentation/touch locks.
- Adds the transient workspace switcher overlay and user-owned shortcut
  conflict checks without silently rewriting Hyprland bindings.

### Multi-monitor

- Adds active-output snap geometry, scale/orientation-aware layout conversion,
  hotplug recovery, and bounded movement back inside a surviving output.
- Reconciles groups, split pairs, overlays, and saved layouts after monitor
  removal or reappearance without continuously forcing geometry.

### Tablet

- Adds a large-card tablet switcher with swipe navigation and explicit close
  policy, plus bounded recent/saved layout persistence.
- Keeps portrait/landscape behavior, stylus drag thresholds, native tablet
  semantics, rotation rollback, and capability-driven unavailable states.

### Performance

- Adds a portable multitasking safety gate covering no subprocess per drag,
  no polling loop, bounded update lanes, stable process ownership, and
  debounced persistence.
- Keeps idle CPU, process-count, subprocess-rate, input, companion, privacy,
  update, rollback, and uninstall invariants as release blockers.

### Fixes

- Completes the 1.0.0 to 1.1.0 configuration migration for tablet switcher,
  layout persistence, and multitasking shortcuts while preserving user values.
- Aligns manifest, companion, native helper, diagnostics, documentation, and
  stable update fixtures on the same release version.

### Known limitations

- The committed multitasking fixture is portable contract evidence, not a
  certification artifact. No physical touchscreen, stylus, sensor, external
  monitor, suspend/resume matrix, or loaded optional companion was available.
- Live previews, sensor auto-rotation, handwriting recognition, Wobbly, and
  other optional capabilities remain unavailable or untested when their real
  host backend is absent; no fake screenshots or cloud telemetry are used.

## 1.0.0

### Highlights

- Delivers the production source release of the Omarchy/Quickshell touch and
  stylus enhancement suite while preserving the standard Omarchy bar and other
  plugins.
- Adds a feature-truth matrix, troubleshooting runbook, accessibility
  acceptance contract, equal-key EN/RU locale coverage, and release evidence.

### Input

- Ships the native Rust input transport with bounded Wayland JSON IPC,
  xkbcommon EN/RU layouts, capability-aware keyboard/tablet state, and explicit
  `wtype` fallback behavior.
- Keeps OSK prediction, autocorrect, handwriting ink, and diagnostics local;
  typed or surrounding text is not persisted or logged.

### Tablet

- Covers capability-driven pressure, tilt, distance, rotation, eraser,
  buttons, proximity, output mapping, hotplug, suspend/resume, palm-policy
  configuration, and transactional rotation rollback.
- Includes non-certifying fixture evidence and truthful unavailable states when
  a physical device or sensor backend is absent.

### Desktop

- Retains Overview, App Grid, Dock, Quick Settings, notifications, clipboard,
  touch-sized controls, accessibility settings, onboarding, and native
  foreign-toplevel activation as one namespaced plugin surface.
- Keeps live previews, Wobbly, and Desktop Cube behind real compositor/provider
  boundaries; no screenshot or unpinned `.so` imitation is used.

### Performance

- Keeps owner-only process accounting, bounded helper lifecycle, lazy views,
  debounced persistence, deterministic budgets, and a notify-only watchdog.
- Portable checks measure contracts and JSON/config budgets, not frame rate,
  idle CPU, thermals, or physical-device latency.

### Safety

- Preserves privacy-filtered clipboard handling, protected session processes,
  PID-scoped Force Quit fallback, redacted diagnostics, safe mode, and
  ownership-safe uninstall.

### Updates

- Validates stable releases by GitHub release tag, journals updates, creates
  rollback snapshots, restores failed health checks, recovers interrupted
  transactions, and supports an explicit no-argument rollback to the newest
  valid snapshot.
- Publishes a source archive and SHA-256 checksum from the green `main` commit.

### Compatibility

- Targets Omarchy Quattro 4.0.1-1, Quickshell 0.3.1, Hyprland 0.56.2, and
  Qt 6.11.2 in the validation environment.
- `omarchy plugin validate .`, portable CI, native input checks, companion
  checks, dependency/performance audits, hardware fixtures, and lifecycle E2E
  are release gates.

### Known limitations

- No physical touchscreen, stylus, sensor, multi-monitor matrix, suspend test,
  or loaded optional companion was available in the release environment;
  hardware certification is intentionally not claimed.
- Native text-focus, live previews, Wobbly, Cube, sensor auto-rotation, and
  handwriting recognition remain unavailable when their real backend/provider
  is not exposed.

## 0.9.0

- Adds the native Rust `omanome-input` Wayland backend with one bounded seat
  connection, `zwp_virtual_keyboard_v1`, xkbcommon EN/RU keymaps, explicit
  text-focus capability reporting, bounded JSON IPC, and an honest `wtype`
  fallback policy.
- Adds capability-driven Wayland tablet-v2 handling for stylus proximity,
  pressure, tilt, distance, rotation, eraser, buttons, tool type, output
  mapping, hotplug, suspend/resume, reconnect backoff, and transactional
  rotation rollback without vendor-specific assumptions.
- Adds OSK 3.0 local prediction/autocorrect boundaries, bounded stylus ink,
  local handwriting-provider architecture, explicit recognition-unavailable
  status, privacy-safe diagnostics, and no cloud recognition by default.
- Adds `stylus-info`, `touch-info`, and enriched `sensor-info`/capabilities
  diagnostics plus non-certifying fixtures for stylus events, hotplug,
  suspend/resume, output remap, rollback, and handwriting policy.
- Preserves the 0.8 lifecycle, performance, safety, standard-bar coexistence,
  companion fail-closed, updater, recovery, and uninstall invariants.

## 0.8.0

- Adds an owner-only CPU/process investigation boundary with strict PID
  identity, start-time checks, an atomic registry, JSON snapshots, a
  notify-only sustained-pressure watchdog, and an explicit separation between
  Omanome CPU and whole-system CPU.
- Audits the repository for Lua/subprocess/timer paths and keeps unrelated
  Omarchy helpers outside Omanome's measurements; no foreign process is
  terminated or claimed as an Omanome regression.
- Adds bounded subprocess lanes, backoff and crash-loop suppression, slow or
  event-driven fallback refreshes, debounced config/clipboard writes, and
  resource release when the panel closes.
- Adds `automatic`, `quality`, `balanced`, `performance`, and `battery-saver`
  modes, schema-2 migration from `performance.qualityPreset`, deterministic
  benchmark/profiler commands, and performance Settings diagnostics.
- Hardens OSK release handling, rotation/clipboard watcher lifecycle, search
  debounce, optional wobbly disable reconciliation, and lifecycle regression
  fixtures for repeated panel open/close cycles.
- Documents high-CPU triage, ownership evidence, measured-vs-unmeasured
  metrics, the no-name-kill policy, and the 0.8.0 release/CI contract.

## 0.7.0

- Adds a transactional updater with channel-aware checks, phase journals,
  user-owned rollback snapshots, health checks, automatic restore, interrupted
  transaction recovery, retention, and preserved failed-update evidence.
- Adds schema-2 config migration/validation tooling with future-schema refusal,
  atomic import/export/diff operations, and explicit safe-mode recovery state.
- Adds capability, hardware-fixture, redacted support-bundle, doctor JSON, and
  dependency/performance audit commands; fixture output never claims physical
  hardware certification.
- Adds ownership manifests, exact-path uninstall preflight, dry-run/JSON output,
  symlink/broad-root refusal, companion cleanup, and settings-preserving default
  uninstall behavior.
- Adds explicit Updates, Backup, Recovery and support-bundle controls to Settings,
  release metadata validation, source archives/checksums, and tag-driven release CI.
- Preserves the Omarchy standard bar, single Quickshell host, Wayland/X11 safety
  boundaries, optional companion fail-closed behavior, and all 0.6 surfaces.

## 0.6.0

- Adds a cohesive tablet-first Overview with current-workspace-first mosaic
  layout, dynamic/fixed workspace presentation, real search providers, and
  native window/app/settings/action activation.
- Adds App Grid 2.0 and Dock 2.0: real desktop icons, shared favorites,
  recent ordering, categories, persistent folders, drag reorder, running
  indicators, explicit launcher/settings items, and responsive placement.
- Adds Settings 2.0 with category search, `settings://` deep links, portrait
  navigation, reset boundaries, accessibility controls, safe diagnostics copy,
  and an in-panel doctor runner.
- Adds multi-signal Auto/Desktop/Tablet/Hybrid mode and a first-run onboarding
  flow; legacy configs migrate without showing onboarding again.
- Adds responsive logical-size tokens, input hysteresis, tablet profiles,
  accessibility semantics, adaptive Quick Settings, and orientation-aware Dock
  and window controls.
- Bumps the optional companion identity to 0.6.0 while preserving its exact
  ABI/API handshake and fail-closed loading policy.

## 0.5.0

- Adds a versioned optional `omanome-hypr` Wobbly renderer using Hyprland's
  public `IWindowTransformer` workbuffer boundary, bounded mesh physics, and a
  real GL shader/VAO/VBO path with transparent fail-closed fallback.
- Adds explicit `wobbly enable|disable` status IPC, QML Settings integration,
  lifecycle-aware companion reporting, and tests for the public renderer
  boundary and unsafe-loader invariants.
- Adds bounded Wobbly configuration IPC for mesh/physics parameters, a debounced
  Settings bridge, an advanced-effects master switch, and battery/fullscreen
  fail-safe policy enforcement.
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
