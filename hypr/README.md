# `omanome-hypr` companion boundary

The core Omarchy plugin remains QML/IPC-only and installs without a compiler.
The optional `hypr/omanome-hypr` module is a separate Hyprland plugin. It is
compiled against the local Hyprland headers and refuses to load when the
runtime API hash differs from the headers used to build it. This is the
version-aware fail-closed boundary required for compositor code.

The companion currently provides the compatibility handshake and a stable
capability report. It does not claim wobbly or cube support merely because a
`.so` exists. Desktop Cube is already maintained as the separate
`pluseight8/omarchy-desktop-cube` Hyprland companion; Omanome detects and can
integrate with that backend instead of duplicating its renderer. Wobbly window
deformation remains unavailable until its own compositor renderer is complete.

Build and install are explicit and user-owned:

```sh
omanome companion doctor
omanome companion build
omanome companion install
omanome companion enable
```

No command in this repository invokes `sudo`, edits the Hyprland source, uses
LD_PRELOAD, or binary-patches Hyprland. If development headers are missing,
`companion doctor` prints the dependency names and leaves the core plugin
usable. `companion enable` performs the runtime hash check before asking
Hyprland to load the module; a mismatch is reported and the module is not
loaded.

The core continues to use stable Hyprland IPC for read-only state and normal
window/workspace actions. It never renders screenshots as fake window content
and never changes input coordinates to simulate a compositor transform.
