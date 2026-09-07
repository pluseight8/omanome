# Stylus integration

Stylus discovery comes from the JSON device inventory exposed by Hyprland.
Omanome uses explicit device types, capability fields, and trusted tablet
group context; it does not identify a stylus from a vendor-name substring. The
diagnostic record includes pressure, tilt X/Y, rotation, distance, proximity,
eraser, button count, tool type, serial, backend, and mapped output when the
input stack reports them. Native pressure, tilt, eraser, and tablet events stay
native for Wayland clients (Krita, GIMP, and other drawing applications).

The settings UI exposes capability-aware pressure/palm/hover preferences. It
does not synthesize mouse events in place of tablet protocol events. Output
mapping and rotation are delegated to Hyprland's `input.tablet` settings, with
no hardcoded monitor or device name.

Omanome also provides a real annotation layer with pen, highlighter, eraser,
colors, undo/redo, screenshot, and clipboard capture. It is opened from Quick
Settings and disappears completely when closed, so it does not keep intercepting
input. Generic barrel-button mappings are displayed in Settings only for devices
that report buttons, but remain explicitly unavailable until a portable libinput
button-event companion exists; the current public Omarchy API does not expose
those events to a plugin. Omanome never invents pressure or eraser events.

Rotation uses Hyprland's runtime `input.touchdevice.transform` and
`input.tablet.transform` options and the dynamically reported monitor names.
Auto rotation prefers the optional `monitor-sensor` client from
`iio-sensor-proxy`, then uses its `net.hadess.SensorProxy` D-Bus API through a
persistent signal monitor. `omanome sensor-info` reports the selected backend;
manual landscape/portrait transforms remain available through Quick Settings
when Hyprland is present.
