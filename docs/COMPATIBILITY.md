# Compatibility snapshot (0.7.0)

The repository was validated in the provided desktop environment on 2026-09-06 with:

| Component | Observed version | Validation |
| --- | --- | --- |
| Omarchy | `4.0.1-1` | `omarchy plugin validate .` passed |
| Quickshell | `0.3.1` | QML imports and plugin contract inspected |
| Hyprland | `0.56.2` | `hyprctl devices/monitors/clients -j` and IPC paths inspected |
| Qt `qmllint` | Qt `6.11.2` | all project QML files linted with exit status 0 |

The machine exposed the expected `touch`, `tablets`, and `switches` keys in `hyprctl devices -j`; no physical touchscreen or stylus was attached during the static validation run, so pressure, tilt, eraser, rotation, and palm-rejection behavior are not marked as hardware-tested.

The 0.7 core retains the 0.6 layer-rule blur, native foreign-toplevel Coverflow, and fail-closed companion boundaries. The transactional updater, schema-2 config migration, recovery journal, ownership-safe uninstall, redacted support bundle, and capability probes are independent of optional compositor backends. Live window thumbnails use Quickshell 0.3.1 `ScreencopyView` with the compositor-owned `hyprland-toplevel-export-v1` source and remain unavailable until a stream reports content. The optional `omanome-hypr` companion renders Wobbly through the public `IWindowTransformer` workbuffer boundary on a matching GL runtime; the implementation is fail-closed on rotated outputs, X11 windows, unsupported backends, or draw failures. The external `omarchy-desktop-cube` plugin is detected and integrated through its Lua API when loaded; Omanome does not duplicate that renderer. Auto/Desktop/Tablet/Hybrid mode combines device, input, keyboard and orientation signals; onboarding is skipped for migrated configurations. Automatic text-input focus discovery, persistent virtual input, stylus button-event mapping, and handwriting recognition remain optional. Sensor-driven rotation is supported through monitor-sensor or the iio-sensor-proxy D-Bus fallback when the service and accelerometer are present; this environment exposed neither sensor backend. The main plugin remains loadable when any optional capability is absent.
