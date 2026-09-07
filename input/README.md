# Omanome input backend

Omanome's keyboard uses the Wayland `virtual-keyboard-v1` protocol through the
small `wtype` client. It does not use X11 or `xdotool`. The Quickshell panel is
only the UI; key delivery is performed by the native Wayland client. Ordinary
keys therefore remain capability-gated one-shot calls until an optional
persistent input companion is installed; Omanome does not hide that limitation.

The repository keeps this boundary behind `Service.qml` so a future
`omanome-input` helper can replace `wtype` without changing the keyboard UI.
The optional helper may implement text-input focus observation, persistent
UTF-8/modifier delivery, key repeat, cursor motion, and input-method
integration when the compositor exposes them. Omanome never claims automatic
text-field focus detection when that protocol is unavailable and the core
plugin never requires the helper to install.

Required for the current backend:

- `wtype`
- a compositor advertising `zwp_virtual_keyboard_v1`

Use `omanome doctor` to see whether the backend is available. The OSK labels
cursor mode, suggestions, and auto-show as unavailable until
`inputBackendAvailable` is provided by such a companion.

Rotation has a separate event-driven path in `rotation-monitor.sh`: it first
executes `monitor-sensor --accel`, then falls back to
`net.hadess.SensorProxy` over D-Bus with `ClaimAccelerometer` and a
persistent signal monitor. `sensor-info` reports which path is selected;
manual rotation is always independent of this capability.

Quick Settings reads its live state through `system-state.sh`. The probe is
best-effort and reports backend availability instead of inventing toggle
state. `wifi-scan.sh` and `bluetooth-scan.sh` expose nearby devices as JSON
without storing network passwords or starting a second daemon. Volume,
microphone, brightness, power-profile, Wi-Fi, Bluetooth, screenshot, and
recording actions remain capability-gated in the shared service.

`audio-devices.sh` reads the current PipeWire/WirePlumber sink and source
nodes for the expandable Quick Settings picker; selecting one calls
`wpctl set-default` with the reported node id. It does not persist a guessed
device name or start another audio service.
