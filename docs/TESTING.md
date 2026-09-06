# Testing and acceptance notes

## Local checks

Run:

```sh
make check
```

The command performs:

1. manifest/config safety validation;
2. `bash -n` on the CLI and clipboard helper;
3. Python unit tests for the bar contract, config version, secret clipboard path, and native Omarchy validation;
4. Qt `qmllint` with temporary import links to the installed Omarchy `qs.Commons` and `qs.Ui` modules.

The temporary QML import directory is outside the checkout and is removed when the lint target exits, so it cannot make `omarchy plugin validate` reject the repository for containing symlinks.

## Manual matrix

The QML code is designed for the following manual matrix when hardware is available:

| Area | Check |
| --- | --- |
| Input | mouse, keyboard, touchpad, touchscreen, generic tablet/stylus, eraser and side buttons |
| Shell coexistence | standard bar, multiple bar widgets, a panel, overlay, menu, and service plugin remain usable |
| Outputs | one monitor, multiple monitors, portrait and landscape |
| Scale | 1.0x through 2.0x fractional scaling |
| Apps | GTK, Qt, Electron, terminal, browser, fullscreen client, drawing application |
| Lifecycle | disable, safe-mode, update check, rollback, uninstall with and without settings |

## Acceptance evidence available in this checkout

- `manifest.json` contains no replacement-bar kind.
- `scripts/validate.py` rejects unsafe absolute/parent entry points and symlinks.
- `Service.qml` uses a single namespaced IPC handler and no second shell process.
- `input/clipboard-capture.sh` drops sensitive clipboard state and emits no payload logs.
- `hypr/README.md` records why no unpinned compositor `.so` is loaded.

Hardware-specific pressure, tilt, screen rotation, and focus/text-input tests require the corresponding device/backend; they should not be represented as passed by static CI.
