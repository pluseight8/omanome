# Compatibility snapshot

The repository was validated in the provided desktop environment on 2026-09-06 with:

| Component | Observed version | Validation |
| --- | --- | --- |
| Omarchy | `4.0.1-1` | `omarchy plugin validate .` passed |
| Quickshell | `0.3.1` | QML imports and plugin contract inspected |
| Hyprland | `0.56.2` | `hyprctl devices/monitors/clients -j` and IPC paths inspected |
| Qt `qmllint` | Qt `6.11.2` | all project QML files linted with exit status 0 |

The machine exposed the expected `touch`, `tablets`, and `switches` keys in `hyprctl devices -j`; no physical touchscreen or stylus was attached during the static validation run, so pressure, tilt, eraser, rotation, and palm-rejection behavior are not marked as hardware-tested.

The 0.4 core uses Hyprland layer-rule IPC for real blur and native foreign-toplevel objects for Coverflow Alt-Tab. Live window thumbnails remain unavailable in this environment because Quickshell 0.3.1 exposes no compositor texture provider. The external `omarchy-desktop-cube` plugin is detected and integrated through its Lua API when loaded; Omanome does not duplicate that renderer. Compositor-rendered wobbly windows remain intentionally unavailable without a pinned native renderer. Automatic text-input focus discovery, persistent virtual input, stylus button-event mapping, and handwriting recognition remain optional. Sensor-driven rotation is supported through monitor-sensor or the iio-sensor-proxy D-Bus fallback when the service and accelerometer are present; this environment exposed neither sensor backend. The main plugin remains loadable when any optional capability is absent.
