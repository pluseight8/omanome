# `omanome-hypr` companion boundary

The core Omarchy plugin remains QML/IPC-only and installs without a compiler.
The optional `hypr/omanome-hypr` module is a separate Hyprland plugin. It is
compiled against the local Hyprland headers and refuses to load when the
runtime API hash differs from the headers used to build it. This is the
version-aware fail-closed boundary required for compositor code.

The 0.5 companion adds a real Wobbly renderer through Hyprland's public
`Render::IWindowTransformer` boundary. It renders the compositor-owned window
workbuffer through a bounded mesh and returns the transformed framebuffer to
Hyprland; it does not paint a QML imitation or replace the window with a
screenshot. The implementation is enabled explicitly through the versioned
status IPC and stays disabled on non-GL backends, rotated outputs, X11 windows,
unsupported API hashes, shader/buffer failures, or any other failed precondition.

Desktop Cube is still maintained as the separate
`pluseight8/omarchy-desktop-cube` Hyprland companion; Omanome detects and can
integrate with that backend instead of duplicating its renderer.

Build and install are explicit and user-owned:

```sh
omanome companion doctor
omanome companion build
omanome companion install
omanome companion enable
hyprctl -j omanome-effects
hyprctl -j omanome-effects wobbly enable
hyprctl -j omanome-effects wobbly disable
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
