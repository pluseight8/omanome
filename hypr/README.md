# omanome-hypr companion boundary

Omanome intentionally does not load an unpinned Hyprland `.so` plugin. The
current baseline uses stable Hyprland IPC and core configuration only:

- `hyprctl clients -j` / `monitors -j` for read-only state;
- `hyprctl dispatch` for focus, workspace, fullscreen, close, and kill-mode;
- `hyprctl keyword` only for explicitly enabled touch/rotation settings;
- the Hyprland event socket may be used by a future event bridge.

`wobbly windows` and `desktop cube` are represented in the settings model but
remain disabled until a version-pinned companion is built and tested against
the exact Hyprland ABI. Omanome never fakes these effects with screenshots or
window copies, and a failed optional companion must not affect the shell.

Any future companion must be installed separately, report its ABI, and be
loaded only after `omanome doctor` confirms a matching Hyprland build.
