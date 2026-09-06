# Omanome input backend

Omanome's keyboard uses the Wayland `virtual-keyboard-v1` protocol through the
small `wtype` client. It does not use X11 or `xdotool`. The Quickshell panel is
only the UI; key delivery is performed by the native Wayland client.

The repository keeps this boundary behind `Service.qml` so a future
`omanome-input` helper can replace `wtype` without changing the keyboard UI.
The optional helper may implement text-input focus observation and input-method
integration when the compositor exposes it. Omanome never claims automatic
text-field focus detection when that protocol is unavailable.

Required for the current backend:

- `wtype`
- a compositor advertising `zwp_virtual_keyboard_v1`

Use `omanome doctor` to see whether the backend is available.
