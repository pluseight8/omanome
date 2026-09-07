# Omanome input backend

`omanome-input/` contains the optional native Wayland backend. It owns one
Wayland connection and one bounded JSON-lines stream; it does not use X11,
`xdotool`, a process per key, or private text logs. The helper reports native
capabilities only after probing the compositor registry at runtime.

The primary transport is `zwp_virtual_keyboard_v1`. `zwp_input_method_v2` and
`zwp_text_input_v3` are probed independently, and xkbcommon provides the
authoritative `en,ru` keymap. Missing or unauthorized globals are reported as
`unavailable`; the shell may then use its explicit, capability-gated `wtype`
fallback.

The public IPC limits and privacy rules are documented in
[`omanome-input/protocol.json`](omanome-input/protocol.json). Portable checks
run with:

```sh
make input-check
```

A live Wayland session is required to exercise compositor-specific focus,
input-method, and virtual-keyboard behavior. `--version` and `--protocol` are
safe metadata-only smoke tests and do not connect to a compositor.

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

`device-monitor.sh` is a single event-driven `udevadm` observer for input and
display hotplug. It emits only bounded capability metadata; when udev is not
available the shell keeps the last snapshot and reports hotplug as unavailable.
`omanome input-info` combines the helper metadata, a short runtime Wayland
probe when a session is present, keyboard/device counts, and the explicit
`wtype` fallback. It never reports fallback as native and never includes typed
text, surrounding text, or clipboard payloads.
