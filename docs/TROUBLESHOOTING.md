# Omanome troubleshooting

The commands below are intentionally read-only unless the section says
otherwise. JSON output is useful when attaching a redacted diagnostic result to
a report.

## Panel does not open or the shell did not reload

Check the plugin and its capabilities first:

```sh
omanome status --json
omanome capabilities --json
omanome doctor --json
omanome logs
```

If a reload is required, use `omanome reload`. If a recent change prevents the
panel from loading, run `omanome safe-mode`; this disables Omanome's optional
surfaces while leaving the standard Omarchy shell in place. `omanome disable`
is the stronger reversible stop. Re-enable with `omanome enable` after the
diagnostic is complete.

## Adaptive mode or Control Center behaves unexpectedly

Inspect the effective runtime policy before changing configuration:

```sh
omanome mode-info --json
omanome feature list --json
omanome status --json
```

`mode-info` reports the selected profile, stable posture signals, keyboard
state, Docked state, and transition reason. Use `omanome master off` for a
reversible global stop, or `omanome suspend` when the service should remain
loaded but native input and adaptive transitions must be paused. `omanome
resume` restores runtime state. These actions do not write automatic posture
changes into the user's config. If a keyboard or monitor is rapidly connecting
and disconnecting, wait for the debounce window and inspect the last stable
state; the event stream is intentionally bounded.

## OSK or text insertion is unavailable

Run:

```sh
omanome input-info --json
command -v wtype
```

The native virtual-keyboard and text-focus paths require the corresponding
Wayland protocols. `wtype` is the explicit fallback and does not provide
automatic focused-field detection by itself. A missing provider is reported as
unavailable; it is not replaced with a fake text stream. Open the OSK manually
from the panel and confirm that the focused application accepts Wayland input.
Never include typed text or surrounding text in a support report.

## Native input, stylus, rotation, or tablet mode is unavailable

Use the capability-specific probes:

```sh
omanome devices --json
omanome stylus-info --json
omanome touch-info --json
omanome sensor-info --json
omanome hardware-test --fixture tests/fixtures/hardware-tablet.json --json
```

The fixture proves schema and fallback behavior only. A real device must expose
the relevant Hyprland/Wayland type and capabilities for pressure, tilt,
distance, eraser, buttons, proximity, palm policy, output mapping, or hotplug
to become available. Rotation uses `monitor-sensor` first and the
iio-sensor-proxy D-Bus path second; manual rotation works without either. If a
transform is rejected, Omanome rolls the batch back rather than leaving a
partially mapped device.

## Device Graph or setup is not detected

Inspect the privacy-safe inventory and setup reason:

    omanome devices --json
    omanome hardware graph --json
    omanome hardware-setup status --json

A setup is matched only from complete topology evidence; a keyboard without
its required display is a partial match. The graph reports relationships as
Confirmed, Probable, or Unknown. Display names alone never force a mapping.
Use hardware-setup apply only after reviewing the selected policy. It changes
Omanome preferences and does not rewrite arbitrary compositor monitor config.

## Touch is on the wrong display

Run the mapping/calibration view from Settings > Devices and identify the input
and output explicitly. A systematic wrong-display result is diagnosed as a
mapping problem before any correction is proposed. Identical displays or
touchscreens fail closed and require a user choice. Apply keeps the previous
mapping as the last-known-good snapshot; use:

    omanome device info <id> --json
    omanome device rollback <id> --json

If the device disappeared during calibration, the transaction is cancelled and
the previous mapping is restored. The screen may be rotated or scaled, but
calibration remains in device-native coordinates and uses monitor-local logical
geometry.

## Stylus or pen calibration is unavailable

Run omanome devices --json and omanome device test <id> --json. Pressure, tilt,
proximity, eraser, and button controls appear only when the backend reports
those capabilities. The default pressure behavior is linear and native data
is not replaced with synthetic mouse events. During the button test actions
are not executed; assign actions only after the test is confirmed.

## Calibration was reverted or broke reconnect

Use omanome recover --json and inspect the device health result. Safe mode
ignores custom calibration and device automation, while device rollback restores
the last-known-good Omanome metadata without removing the system device or its
Bluetooth pairing. Reset removes only Omanome-owned profile and calibration
metadata. It never deletes a kernel device or unrelated compositor settings.

## Dock, external monitor, or OSK target is wrong

A monitor/keyboard/mouse hotplug burst is settled into one topology update.
Check omanome hardware-setup status --json and the Docked/OSK policy before
changing settings. Partial or ambiguous setups remain unselected. On undock,
Omanome returns surfaces to a valid output and delegates window placement to
the existing multi-monitor recovery policy; it does not move every window or
launch applications. The OSK target can be the primary touch display, the
focused-app display, Ask, or Disabled according to the user policy.

## CPU or memory looks high

Inspect only Omanome-owned processes:

```sh
omanome processes --json
omanome profiler --json --interval 1
omanome benchmark --json
omanome watchdog --watch --json
```

The registry checks the Omanome owner marker and PID start time. A similarly
named foreign helper, including an unmarked `lua`, is not an Omanome process.
The watchdog is notify-only and never sends a signal. Do not run a broad
`pkill lua`; investigate the owning package or service instead.

## Companion, Wobbly, or Cube is disabled

Run `omanome companion status --json` and `omanome companion doctor --json`.
The companion requires the exact Hyprland API/ABI handshake, a supported GL
backend, and a valid artifact. A pending-load crash marker or any mismatch
keeps it disabled. `omanome companion recover` restores the newest user-owned
backup without enabling it. The Desktop Cube is supplied by the external,
version-matched `omarchy-desktop-cube` backend; Omanome does not ship a second
renderer. Missing or unsafe optional effects are expected to fail closed.

## Update failed or the shell stopped during an update

Start with the recovery journal:

```sh
omanome recover --json
omanome doctor --json
omanome rollback --list --json
```

Updates are explicit and transactional. A health-check failure restores the
previous snapshot and retains failed evidence. `omanome rollback` with no
argument restores the newest valid user-owned snapshot; use an explicit
snapshot id only after reviewing the list. `omanome update --dry-run --json`
is read-only. Check configuration independently with:

```sh
omanome export-config
omanome import-config /path/to/config.json
```

Imports validate schema 2 and refuse future schemas or unsafe paths.

## Uninstall and ownership safety

Preview first:

```sh
omanome uninstall --dry-run --json
```

`omanome uninstall --yes` removes only paths in Omanome's ownership manifest.
Settings are preserved by default; add `--purge-settings` only when that is
intentional. Symlink escapes, broad roots, foreign plugins, the standard bar,
themes, and user Hyprland files are refused. If the preview is unexpected,
stop and attach it to the report instead of deleting paths manually.

## Privacy-safe support report

Create a bundle with:

```sh
omanome diagnostics bundle /tmp/omanome-support.tar.gz
```

For sharing outside a trusted local review, use the stricter local policy:

```sh
omanome diagnostics export /tmp/omanome-private.tar.gz --private
```

Review the archive before sharing it. It contains capability, version,
validation, and lifecycle metadata, but intentionally omits config values,
clipboard payloads, image data, window titles, typed/surrounding text, and
secrets. Do not paste raw command lines containing user data into an issue.
