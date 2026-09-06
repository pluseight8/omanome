# Stylus integration

Stylus discovery comes from the JSON device inventory exposed by Hyprland.
Omanome does not identify a pen by brand: it records the capabilities the
backend reports and leaves native pressure, tilt, eraser, and tablet events to
the Wayland client (Krita, GIMP, and other drawing applications).

The settings UI exposes capability-aware pressure/palm/hover preferences. It
does not synthesize mouse events in place of tablet protocol events. Output
mapping and rotation are delegated to Hyprland's `input.tablet` settings, with
no hardcoded monitor or device name.
