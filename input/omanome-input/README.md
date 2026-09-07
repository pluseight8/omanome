# omanome-input

`omanome-input` is a single user-session process. It owns one Wayland
connection and exposes a bounded, versioned JSON-lines IPC stream over its
standard input/output. The shell starts it once and sends keyboard/text
events over the existing process stdin; it does not spawn a process per key.

The backend binds `zwp_virtual_keyboard_v1` only when the compositor advertises
the manager and reports the result as `native-wayland`. It also probes the
wlroots `zwp_input_method_v2` manager and the standard `zwp_text_input_v3`
family. Missing or unauthorized globals are reported as unavailable so the
shell can use its explicit `wtype` fallback.

The protocol is intentionally payload-private: typed text is accepted at
runtime but never emitted in events, diagnostics, or logs. Surrounding text is
used only in memory by the Wayland event handler and is not persisted.

Build locally with:

```sh
cargo build --release --locked
```

The portable contract and state-machine tests do not require a live Wayland
session. A live native session is required to report `native-wayland` or to
exercise compositor-specific focus and input-method behavior.
