# Stylus integration

Stylus discovery comes from the JSON device inventory exposed by Hyprland.
Omanome does not identify a pen by brand: it records the capabilities the
backend reports and leaves native pressure, tilt, eraser, and tablet events to
the Wayland client (Krita, GIMP, and other drawing applications).

The settings UI exposes capability-aware pressure/palm/hover preferences. It
does not synthesize mouse events in place of tablet protocol events. Output
mapping and rotation are delegated to Hyprland's `input.tablet` settings, with
no hardcoded monitor or device name.

Omanome also provides a real annotation layer with pen, highlighter, eraser,
colors, undo/redo, screenshot, and clipboard capture. It is opened from Quick
Settings and disappears completely when closed, so it does not keep intercepting
input. Generic barrel-button mappings are displayed in Settings, but remain
explicitly unavailable until a portable libinput button-event companion exists;
the current public Omarchy API does not expose those events to a plugin.

Rotation uses Hyprland's runtime `input.touchdevice.transform` and
`input.tablet.transform` options and the dynamically reported monitor names.
Auto rotation is enabled only when the optional `monitor-sensor` client from
`iio-sensor-proxy` is installed; manual landscape/portrait transforms remain
available through Quick Settings when Hyprland is present.
