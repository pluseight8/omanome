#![deny(unsafe_op_in_unsafe_fn)]

mod input_method_v2 {
    use wayland_client;
    use wayland_client::protocol::*;
    use wayland_protocols::wp::text_input::zv3::client::*;

    pub mod __interfaces {
        use wayland_client::protocol::__interfaces::*;
        wayland_scanner::generate_interfaces!("protocols/input-method-unstable-v2.xml");
    }

    use self::__interfaces::*;
    wayland_scanner::generate_client_code!("protocols/input-method-unstable-v2.xml");
}

mod virtual_keyboard {
    use wayland_client;
    use wayland_client::protocol::*;

    pub mod __interfaces {
        use wayland_client::protocol::__interfaces::*;
        wayland_scanner::generate_interfaces!("protocols/virtual-keyboard-unstable-v1.xml");
    }

    use self::__interfaces::*;
    wayland_scanner::generate_client_code!("protocols/virtual-keyboard-unstable-v1.xml");
}

use input_method_v2::zwp_input_method_manager_v2::ZwpInputMethodManagerV2;
use input_method_v2::zwp_input_method_v2::{self, ZwpInputMethodV2};
use serde::Deserialize;
use serde_json::{json, Value};
use std::ffi::{c_char, c_void, CStr, CString};
use std::io::{self, Write};
use std::os::fd::{AsFd, AsRawFd, FromRawFd, OwnedFd};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use virtual_keyboard::zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1;
use virtual_keyboard::zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1;
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_registry, wl_seat};
use wayland_client::{delegate_noop, Connection, Dispatch, EventQueue, QueueHandle};
use wayland_protocols::wp::text_input::zv3::client::zwp_text_input_manager_v3::ZwpTextInputManagerV3;

const PROTOCOL: &str = "omanome-input";
const PROTOCOL_VERSION: u32 = 1;
const MAX_COMMAND_BYTES: usize = 16 * 1024;
const MAX_PENDING_COMMANDS: usize = 256;
const XKB_KEYMAP_FORMAT_TEXT_V1: u32 = 1;
const KEY_STATE_RELEASED: u32 = 0;
const KEY_STATE_PRESSED: u32 = 1;
const CONTENT_HINT_HIDDEN_TEXT: u32 = 0x40;
const CONTENT_HINT_SENSITIVE_DATA: u32 = 0x80;
const PURPOSE_PASSWORD: u32 = 8;
const PURPOSE_TERMINAL: u32 = 13;

type SharedEmitter = Arc<Mutex<Emitter>>;

struct Emitter {
    stdout: io::BufWriter<io::Stdout>,
}

impl Emitter {
    fn new() -> Self {
        Self {
            stdout: io::BufWriter::new(io::stdout()),
        }
    }

    fn send(&mut self, value: Value) {
        // Never include command payloads in the output stream. Only structured
        // capability/state metadata and event types are emitted.
        let _ = serde_json::to_writer(&mut self.stdout, &value);
        let _ = self.stdout.write_all(b"\n");
        let _ = self.stdout.flush();
    }
}

fn emit(emitter: &SharedEmitter, value: Value) {
    if let Ok(mut output) = emitter.lock() {
        output.send(value);
    }
}

#[derive(Debug, Deserialize)]
struct Command {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    text: String,
    #[serde(default)]
    key: String,
    #[serde(default)]
    modifiers: Vec<String>,
    #[serde(default)]
    before: u32,
    #[serde(default)]
    after: u32,
    #[serde(default)]
    language: String,
    #[serde(default)]
    layout: String,
    #[serde(default)]
    group: Option<u32>,
    #[serde(default)]
    depressed: Option<u32>,
    #[serde(default)]
    latched: Option<u32>,
    #[serde(default)]
    locked: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BackendKind {
    NativeWayland,
    Unavailable,
}

impl BackendKind {
    fn as_str(self) -> &'static str {
        match self {
            Self::NativeWayland => "native-wayland",
            Self::Unavailable => "unavailable",
        }
    }
}

struct Keymap {
    context: *mut xkb_context,
    keymap: *mut xkb_keymap,
    state: *mut xkb_state,
    text: Vec<u8>,
    shift_mask: u32,
    min_keycode: u32,
    max_keycode: u32,
}

unsafe impl Send for Keymap {}

impl Drop for Keymap {
    fn drop(&mut self) {
        // SAFETY: each pointer was returned by xkbcommon and is released once.
        unsafe {
            if !self.state.is_null() {
                xkb_state_unref(self.state);
            }
            if !self.keymap.is_null() {
                xkb_keymap_unref(self.keymap);
            }
            if !self.context.is_null() {
                xkb_context_unref(self.context);
            }
        }
    }
}

impl Keymap {
    fn new(layout: &str) -> Result<Self, String> {
        let requested = normalize_layout(layout);
        let layout_name = CString::new(if requested == "ru" { "us,ru" } else { "us,ru" }).unwrap();
        let rules = CString::new("evdev").unwrap();
        let model = CString::new("pc105").unwrap();
        let names = xkb_rule_names {
            rules: rules.as_ptr(),
            model: model.as_ptr(),
            layout: layout_name.as_ptr(),
            variant: std::ptr::null(),
            options: std::ptr::null(),
        };
        // SAFETY: xkbcommon receives valid, NUL-terminated rule-name strings.
        let (context, keymap, state, text, shift_mask, min_keycode, max_keycode) = unsafe {
            let context = xkb_context_new(0);
            if context.is_null() {
                return Err("xkbcommon context unavailable".into());
            }
            let keymap = xkb_keymap_new_from_names(context, &names, 0);
            if keymap.is_null() {
                xkb_context_unref(context);
                return Err("xkbcommon could not create en,ru keymap".into());
            }
            let state = xkb_state_new(keymap);
            let text_ptr = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
            if state.is_null() || text_ptr.is_null() {
                if !state.is_null() {
                    xkb_state_unref(state);
                }
                if !text_ptr.is_null() {
                    libc::free(text_ptr.cast::<c_void>());
                }
                xkb_keymap_unref(keymap);
                xkb_context_unref(context);
                return Err("xkbcommon could not serialize keymap".into());
            }
            let text = CStr::from_ptr(text_ptr).to_bytes_with_nul().to_vec();
            libc::free(text_ptr.cast::<c_void>());
            let shift_name = CString::new("Shift").unwrap();
            let shift_mask = 1u32 << xkb_keymap_mod_get_index(keymap, shift_name.as_ptr());
            let min_keycode = xkb_keymap_min_keycode(keymap);
            let max_keycode = xkb_keymap_max_keycode(keymap);
            (
                context,
                keymap,
                state,
                text,
                shift_mask,
                min_keycode,
                max_keycode,
            )
        };
        let mut result = Self {
            context,
            keymap,
            state,
            text,
            shift_mask,
            min_keycode,
            max_keycode,
        };
        result.set_group(if requested == "ru" { 1 } else { 0 });
        Ok(result)
    }

    fn set_group(&mut self, group: u32) {
        // SAFETY: state is owned by this keymap and masks are bounded.
        unsafe {
            let _ = xkb_state_update_mask(self.state, 0, 0, 0, group, 0, 0);
        }
    }

    fn find_text_key(&mut self, text: &str, group: u32) -> Option<(u32, bool)> {
        if text.chars().count() != 1 {
            return None;
        }
        let mut buffer = [0i8; 16];
        for shifted in [false, true] {
            // SAFETY: state belongs to this keymap and the output buffer is valid.
            unsafe {
                let mask = if shifted { self.shift_mask } else { 0 };
                let _ = xkb_state_update_mask(self.state, mask, 0, 0, group, 0, 0);
                for keycode in self.min_keycode..=self.max_keycode {
                    let length = xkb_state_key_get_utf8(
                        self.state,
                        keycode,
                        buffer.as_mut_ptr(),
                        buffer.len(),
                    );
                    if length == 0 || length >= buffer.len() {
                        continue;
                    }
                    let bytes = std::slice::from_raw_parts(buffer.as_ptr().cast::<u8>(), length);
                    if bytes == text.as_bytes() {
                        return keycode.checked_sub(8).map(|code| (code, shifted));
                    }
                }
            }
        }
        None
    }
}

struct BackendState {
    emitter: SharedEmitter,
    seat: Option<wl_seat::WlSeat>,
    virtual_keyboard: Option<ZwpVirtualKeyboardV1>,
    input_method: Option<ZwpInputMethodV2>,
    keymap: Option<Keymap>,
    backend: BackendKind,
    input_method_available: bool,
    text_active: bool,
    content_purpose: u32,
    content_hints: u32,
    done_serial: u32,
    layout: String,
    group: u32,
    modifiers: u32,
    queue_depth: usize,
}

impl BackendState {
    fn new(emitter: SharedEmitter) -> Self {
        Self {
            emitter,
            seat: None,
            virtual_keyboard: None,
            input_method: None,
            keymap: None,
            backend: BackendKind::Unavailable,
            input_method_available: false,
            text_active: false,
            content_purpose: 0,
            content_hints: 0,
            done_serial: 0,
            layout: "en".into(),
            group: 0,
            modifiers: 0,
            queue_depth: 0,
        }
    }

    fn capabilities(&self) -> Value {
        json!({
            "protocol": PROTOCOL,
            "version": PROTOCOL_VERSION,
            "type": "input.capabilities",
            "backend": self.backend.as_str(),
            "waylandConnection": self.seat.is_some(),
            "seat": self.seat.is_some(),
            "virtualKeyboard": if self.virtual_keyboard.is_some() { "native" } else { "unavailable" },
            "textInput": "registry-probed",
            "inputMethod": if self.input_method_available { "v2" } else { "unavailable" },
            "keymap": if self.keymap.is_some() { "xkbcommon" } else { "unavailable" },
            "layouts": ["en", "ru"],
            "queueLimit": MAX_PENDING_COMMANDS,
            "queueDepth": self.queue_depth,
            "securePayloads": true,
        })
    }

    fn status(&self) -> Value {
        json!({
            "protocol": PROTOCOL,
            "version": PROTOCOL_VERSION,
            "type": "input.status",
            "backend": self.backend.as_str(),
            "connected": self.seat.is_some(),
            "textActive": self.text_active,
            "purpose": purpose_name(self.content_purpose),
            "purposeCode": self.content_purpose,
            "secure": self.secure_context(),
            "layout": self.layout,
            "group": self.group,
            "modifiers": self.modifiers,
            "inputMethod": if self.input_method_available { "v2" } else { "unavailable" },
            "queueDepth": self.queue_depth,
        })
    }

    fn secure_context(&self) -> bool {
        self.content_purpose == PURPOSE_PASSWORD
            || self.content_hints & (CONTENT_HINT_HIDDEN_TEXT | CONTENT_HINT_SENSITIVE_DATA) != 0
    }

    fn emit_capabilities(&self) {
        emit(&self.emitter, self.capabilities());
    }
    fn emit_status(&self) {
        emit(&self.emitter, self.status());
    }

    fn set_keymap(&mut self, layout: &str) -> Result<(), String> {
        let wanted = normalize_layout(layout);
        if self.keymap.as_ref().is_some_and(|_| self.layout == wanted) {
            return Ok(());
        }
        self.keymap = Some(Keymap::new(&wanted)?);
        self.layout = wanted;
        self.group = if self.layout == "ru" { 1 } else { 0 };
        if let Some(keyboard) = &self.virtual_keyboard {
            send_keymap(keyboard, self.keymap.as_ref().unwrap())?;
            keyboard.modifiers(self.modifiers, 0, 0, self.group);
        }
        Ok(())
    }

    fn handle(&mut self, command: Command) -> bool {
        self.queue_depth = self.queue_depth.saturating_sub(1);
        match command.kind.as_str() {
            "input.status" => self.emit_status(),
            "input.capabilities" => self.emit_capabilities(),
            "set.language" | "keyboard.layout" => {
                if let Err(error) = self.set_keymap(if !command.layout.is_empty() {
                    &command.layout
                } else {
                    &command.language
                }) {
                    emit(
                        &self.emitter,
                        json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"input.error","code":"keymap-unavailable","retryable":false,"detail":error}),
                    );
                } else {
                    self.emit_status();
                }
            }
            "keyboard.text" | "text.commit" => {
                if command.text.as_bytes().len() > 4096 {
                    self.error("payload-too-large", false);
                } else if let Err(error) = self.commit_text(&command.text) {
                    self.error(&error, true);
                }
            }
            "keyboard.key" => {
                if let Err(error) = self.send_named_key(&command.key, KEY_STATE_PRESSED) {
                    self.error(&error, true);
                }
            }
            "keyboard.modifiers" => {
                let depressed = command
                    .depressed
                    .unwrap_or_else(|| modifier_mask(&command.modifiers));
                let group = command.group.unwrap_or(self.group);
                self.modifiers = depressed;
                self.group = group.min(1);
                if let Some(keyboard) = &self.virtual_keyboard {
                    keyboard.modifiers(
                        depressed,
                        command.latched.unwrap_or(0),
                        command.locked.unwrap_or(0),
                        self.group,
                    );
                }
                self.emit_status();
            }
            "text.delete" => {
                if let Err(error) = self.delete_surrounding(command.before, command.after) {
                    self.error(&error, true);
                }
            }
            "text.state" => self.emit_status(),
            "shutdown" => return false,
            _ => self.error("unknown-command", false),
        }
        true
    }

    fn error(&self, code: &str, retryable: bool) {
        emit(
            &self.emitter,
            json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"input.error","code":code,"retryable":retryable}),
        );
    }

    fn commit_text(&mut self, text: &str) -> Result<(), String> {
        if text.is_empty() {
            return Ok(());
        }
        if let Some(input_method) = &self.input_method {
            if self.text_active {
                input_method.commit_string(text.to_string());
                input_method.commit(self.done_serial);
                return Ok(());
            }
        }
        let group = self.group;
        let mut keymap = self
            .keymap
            .take()
            .ok_or_else(|| "native-keymap-unavailable".to_string())?;
        let result = self.commit_text_as_keys(text, &mut keymap, group);
        self.keymap = Some(keymap);
        result
    }

    fn commit_text_as_keys(
        &self,
        text: &str,
        keymap: &mut Keymap,
        group: u32,
    ) -> Result<(), String> {
        let keyboard = self
            .virtual_keyboard
            .as_ref()
            .ok_or_else(|| "native-virtual-keyboard-unavailable".to_string())?;
        for character in text.chars() {
            let value = character.to_string();
            let (keycode, shifted) = keymap
                .find_text_key(&value, group)
                .ok_or_else(|| "character-not-in-keymap".to_string())?;
            if shifted {
                keyboard.modifiers(self.modifiers | keymap.shift_mask, 0, 0, group);
            }
            keyboard.key(now_millis(), keycode, KEY_STATE_PRESSED);
            keyboard.key(now_millis(), keycode, KEY_STATE_RELEASED);
            if shifted {
                keyboard.modifiers(self.modifiers, 0, 0, group);
            }
        }
        Ok(())
    }

    fn delete_surrounding(&mut self, before: u32, after: u32) -> Result<(), String> {
        let input_method = self
            .input_method
            .as_ref()
            .ok_or_else(|| "input-method-unavailable".to_string())?;
        if !self.text_active {
            return Err("text-focus-unavailable".into());
        }
        input_method.delete_surrounding_text(before, after);
        input_method.commit(self.done_serial);
        Ok(())
    }

    fn send_named_key(&mut self, name: &str, state: u32) -> Result<(), String> {
        let keycode = named_keycode(name).ok_or_else(|| "unknown-key".to_string())?;
        let keyboard = self
            .virtual_keyboard
            .as_ref()
            .ok_or_else(|| "native-virtual-keyboard-unavailable".to_string())?;
        keyboard.key(now_millis(), keycode, state);
        Ok(())
    }
}

fn send_keymap(keyboard: &ZwpVirtualKeyboardV1, keymap: &Keymap) -> Result<(), String> {
    let fd = create_keymap_fd(&keymap.text)?;
    keyboard.keymap(
        XKB_KEYMAP_FORMAT_TEXT_V1,
        fd.as_fd(),
        keymap.text.len() as u32,
    );
    Ok(())
}

fn create_keymap_fd(bytes: &[u8]) -> Result<OwnedFd, String> {
    let name = CString::new("omanome-input-keymap").unwrap();
    // SAFETY: memfd_create and the bounded write/ftruncate calls operate on a
    // private descriptor and the exact keymap byte slice.
    unsafe {
        let fd = libc::memfd_create(name.as_ptr(), libc::MFD_CLOEXEC as u32);
        if fd < 0 {
            return Err("memfd-unavailable".into());
        }
        if libc::ftruncate(fd, bytes.len() as i64) != 0 {
            libc::close(fd);
            return Err("keymap-size-failed".into());
        }
        let mut offset = 0usize;
        while offset < bytes.len() {
            let written = libc::write(
                fd,
                bytes[offset..].as_ptr().cast::<c_void>(),
                bytes.len() - offset,
            );
            if written <= 0 {
                libc::close(fd);
                return Err("keymap-write-failed".into());
            }
            offset += written as usize;
        }
        Ok(OwnedFd::from_raw_fd(fd))
    }
}

fn now_millis() -> u32 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u32
}

fn normalize_layout(value: &str) -> String {
    match value.to_ascii_lowercase().as_str() {
        "ru" | "russian" | "ru_ru" => "ru".into(),
        _ => "en".into(),
    }
}

fn purpose_name(value: u32) -> &'static str {
    match value {
        2 => "digits",
        3 => "number",
        4 => "phone",
        5 => "url",
        6 => "email",
        7 => "name",
        8 => "password",
        9 => "date",
        10 => "time",
        11 => "datetime",
        PURPOSE_TERMINAL => "terminal",
        _ => "normal",
    }
}

fn modifier_mask(modifiers: &[String]) -> u32 {
    let mut mask = 0;
    for modifier in modifiers {
        match modifier.to_ascii_lowercase().as_str() {
            "shift" => mask |= 1 << 0,
            "ctrl" | "control" => mask |= 1 << 2,
            "alt" => mask |= 1 << 3,
            "logo" | "super" | "meta" => mask |= 1 << 6,
            _ => {}
        }
    }
    mask
}

fn named_keycode(value: &str) -> Option<u32> {
    let key = value.to_ascii_lowercase();
    let code = match key.as_str() {
        "esc" | "escape" => 1,
        "1" => 2,
        "2" => 3,
        "3" => 4,
        "4" => 5,
        "5" => 6,
        "6" => 7,
        "7" => 8,
        "8" => 9,
        "9" => 10,
        "0" => 11,
        "backspace" => 14,
        "tab" => 15,
        "enter" | "return" => 28,
        "control" | "ctrl" => 29,
        "shift" => 42,
        "alt" => 56,
        "space" => 57,
        "caps" | "capslock" => 58,
        "f1" => 59,
        "f2" => 60,
        "f3" => 61,
        "f4" => 62,
        "f5" => 63,
        "f6" => 64,
        "f7" => 65,
        "f8" => 66,
        "f9" => 67,
        "f10" => 68,
        "f11" => 87,
        "f12" => 88,
        "home" => 102,
        "up" | "arrowup" => 103,
        "pageup" => 104,
        "left" | "arrowleft" => 105,
        "right" | "arrowright" => 106,
        "end" => 107,
        "down" | "arrowdown" => 108,
        "pagedown" => 109,
        "insert" => 110,
        "delete" => 111,
        "super" | "logo" | "meta" => 125,
        _ => return None,
    };
    Some(code)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::args().any(|arg| arg == "--version") {
        println!("omanome-input {PROTOCOL_VERSION} (0.9.0)");
        return Ok(());
    }
    if std::env::args().any(|arg| arg == "--protocol") {
        println!("{PROTOCOL} {PROTOCOL_VERSION}");
        return Ok(());
    }

    let emitter: SharedEmitter = Arc::new(Mutex::new(Emitter::new()));
    let connection = match Connection::connect_to_env() {
        Ok(connection) => connection,
        Err(_) => {
            emit(
                &emitter,
                json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"input.status","backend":"unavailable","connected":false,"reason":"wayland-connection-unavailable"}),
            );
            return Err("Wayland connection unavailable".into());
        }
    };
    let (globals, mut queue) = registry_queue_init::<BackendState>(&connection)?;
    let qh = queue.handle();
    let mut state = BackendState::new(emitter.clone());

    let seat: wl_seat::WlSeat = globals.bind::<wl_seat::WlSeat, _, _>(&qh, 1..=9, ())?;
    state.seat = Some(seat.clone());
    state.keymap = Some(Keymap::new("en")?);

    if let Ok(manager) = globals.bind::<ZwpVirtualKeyboardManagerV1, _, _>(&qh, 1..=1, ()) {
        let keyboard = manager.create_virtual_keyboard(&seat, &qh, ());
        send_keymap(&keyboard, state.keymap.as_ref().unwrap())?;
        keyboard.modifiers(0, 0, 0, 0);
        state.virtual_keyboard = Some(keyboard);
        state.backend = BackendKind::NativeWayland;
    }
    if let Ok(manager) = globals.bind::<ZwpInputMethodManagerV2, _, _>(&qh, 1..=1, ()) {
        state.input_method = Some(manager.get_input_method(&seat, &qh, ()));
        state.input_method_available = true;
    }
    // Binding the text-input manager is a capability probe. The application
    // owns text focus, so the native backend never fabricates focus for it.
    let _text_input_available = globals
        .bind::<ZwpTextInputManagerV3, _, _>(&qh, 1..=2, ())
        .is_ok();
    queue.roundtrip(&mut state)?;
    state.emit_capabilities();
    state.emit_status();

    run_ipc_loop(&mut queue, &connection, &mut state)?;
    Ok(())
}

fn run_ipc_loop(
    queue: &mut EventQueue<BackendState>,
    connection: &Connection,
    state: &mut BackendState,
) -> Result<(), Box<dyn std::error::Error>> {
    let stdin_fd = io::stdin().as_raw_fd();
    let wayland_fd = connection.backend().poll_fd().as_raw_fd();
    let mut input = Vec::<u8>::new();
    let mut buffer = [0u8; 8192];
    loop {
        queue.dispatch_pending(state)?;
        queue.flush()?;
        let mut poll_fds = [
            libc::pollfd {
                fd: stdin_fd,
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: wayland_fd,
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        let result =
            unsafe { libc::poll(poll_fds.as_mut_ptr(), poll_fds.len() as libc::nfds_t, -1) };
        if result < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(io::Error::last_os_error().into());
        }
        if poll_fds[1].revents & (libc::POLLIN | libc::POLLHUP | libc::POLLERR) != 0 {
            if let Some(guard) = queue.prepare_read() {
                guard.read()?;
            }
            queue.dispatch_pending(state)?;
        }
        if poll_fds[0].revents & (libc::POLLIN | libc::POLLHUP | libc::POLLERR) != 0 {
            let read =
                unsafe { libc::read(stdin_fd, buffer.as_mut_ptr().cast::<c_void>(), buffer.len()) };
            if read <= 0 {
                break;
            }
            input.extend_from_slice(&buffer[..read as usize]);
            if input.len() > MAX_PENDING_COMMANDS * MAX_COMMAND_BYTES {
                return Err("input command buffer exceeded bound".into());
            }
            while let Some(position) = input.iter().position(|byte| *byte == b'\n') {
                let line: Vec<u8> = input.drain(..=position).collect();
                let line = &line[..line.len().saturating_sub(1)];
                if line.len() > MAX_COMMAND_BYTES {
                    state.error("command-too-large", false);
                    continue;
                }
                if line.is_empty() {
                    continue;
                }
                let command = match serde_json::from_slice::<Command>(line) {
                    Ok(command) => command,
                    Err(_) => {
                        state.error("invalid-command", false);
                        continue;
                    }
                };
                if state.queue_depth >= MAX_PENDING_COMMANDS {
                    state.error("queue-full", true);
                    continue;
                }
                state.queue_depth += 1;
                if !state.handle(command) {
                    return Ok(());
                }
            }
        }
    }
    Ok(())
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for BackendState {
    fn event(
        _: &mut Self,
        _: &wl_registry::WlRegistry,
        _: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwpInputMethodV2, ()> for BackendState {
    fn event(
        state: &mut Self,
        _: &ZwpInputMethodV2,
        event: zwp_input_method_v2::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            zwp_input_method_v2::Event::Activate => {
                state.text_active = true;
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"text.enter","purpose":purpose_name(state.content_purpose),"secure":state.secure_context()}),
                );
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"osk.request","request":"show","reason":"text-input-activate","secure":state.secure_context()}),
                );
            }
            zwp_input_method_v2::Event::Deactivate => {
                state.text_active = false;
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"text.leave"}),
                );
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"osk.request","request":"hide","reason":"text-input-deactivate"}),
                );
            }
            zwp_input_method_v2::Event::SurroundingText {
                text,
                cursor,
                anchor,
            } => {
                // Keep only bounded metadata. The text itself is never logged
                // or emitted, including for password/sensitive fields.
                let bytes = text.len().min(4096);
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"text.state","surroundingBytes":bytes,"cursor":cursor.min(4096),"anchor":anchor.min(4096),"purpose":purpose_name(state.content_purpose),"secure":state.secure_context()}),
                );
            }
            zwp_input_method_v2::Event::ContentType { hint, purpose } => {
                state.content_hints = hint.into();
                state.content_purpose = purpose.into();
                state.emit_status();
            }
            zwp_input_method_v2::Event::Done => {
                state.done_serial = state.done_serial.saturating_add(1);
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"text.state","doneSerial":state.done_serial,"purpose":purpose_name(state.content_purpose),"secure":state.secure_context()}),
                );
            }
            zwp_input_method_v2::Event::Unavailable => {
                state.input_method_available = false;
                state.text_active = false;
                emit(
                    &state.emitter,
                    json!({"protocol":PROTOCOL,"version":PROTOCOL_VERSION,"type":"input.capabilities","backend":state.backend.as_str(),"inputMethod":"unavailable","reason":"input-method-unavailable"}),
                );
            }
            _ => {}
        }
    }
}

delegate_noop!(BackendState: ignore wl_seat::WlSeat);
delegate_noop!(BackendState: ZwpVirtualKeyboardManagerV1);
delegate_noop!(BackendState: ZwpVirtualKeyboardV1);
delegate_noop!(BackendState: ZwpInputMethodManagerV2);
delegate_noop!(BackendState: ZwpTextInputManagerV3);

#[repr(C)]
struct xkb_context {
    _private: [u8; 0],
}
#[repr(C)]
struct xkb_keymap {
    _private: [u8; 0],
}
#[repr(C)]
struct xkb_state {
    _private: [u8; 0],
}
#[repr(C)]
struct xkb_rule_names {
    rules: *const c_char,
    model: *const c_char,
    layout: *const c_char,
    variant: *const c_char,
    options: *const c_char,
}

#[link(name = "xkbcommon")]
unsafe extern "C" {
    fn xkb_context_new(flags: u32) -> *mut xkb_context;
    fn xkb_context_unref(context: *mut xkb_context);
    fn xkb_keymap_new_from_names(
        context: *mut xkb_context,
        names: *const xkb_rule_names,
        flags: u32,
    ) -> *mut xkb_keymap;
    fn xkb_keymap_unref(keymap: *mut xkb_keymap);
    fn xkb_keymap_get_as_string(keymap: *mut xkb_keymap, format: u32) -> *mut c_char;
    fn xkb_keymap_min_keycode(keymap: *mut xkb_keymap) -> u32;
    fn xkb_keymap_max_keycode(keymap: *mut xkb_keymap) -> u32;
    fn xkb_keymap_mod_get_index(keymap: *mut xkb_keymap, name: *const c_char) -> u32;
    fn xkb_state_new(keymap: *mut xkb_keymap) -> *mut xkb_state;
    fn xkb_state_unref(state: *mut xkb_state);
    fn xkb_state_update_mask(
        state: *mut xkb_state,
        depressed: u32,
        latched: u32,
        locked: u32,
        group: u32,
        latched_group: u32,
        locked_group: u32,
    ) -> u32;
    fn xkb_state_key_get_utf8(
        state: *mut xkb_state,
        key: u32,
        buffer: *mut c_char,
        size: usize,
    ) -> usize;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layout_is_restricted_to_supported_languages() {
        assert_eq!(normalize_layout("ru_RU"), "ru");
        assert_eq!(normalize_layout("en_US"), "en");
        assert_eq!(normalize_layout("de"), "en");
    }

    #[test]
    fn modifier_masks_are_deterministic() {
        assert_eq!(modifier_mask(&["ctrl".into(), "shift".into()]), 5);
        assert_eq!(modifier_mask(&["alt".into(), "super".into()]), 72);
    }

    #[test]
    fn named_keycodes_cover_navigation_and_function_keys() {
        assert_eq!(named_keycode("Esc"), Some(1));
        assert_eq!(named_keycode("F12"), Some(88));
        assert_eq!(named_keycode("PageDown"), Some(109));
        assert_eq!(named_keycode("unknown"), None);
    }

    #[test]
    fn purpose_and_secure_policy_are_explicit() {
        assert_eq!(purpose_name(PURPOSE_PASSWORD), "password");
        assert_eq!(purpose_name(PURPOSE_TERMINAL), "terminal");
        let mut state = BackendState::new(Arc::new(Mutex::new(Emitter::new())));
        assert!(!state.secure_context());
        state.content_hints = CONTENT_HINT_SENSITIVE_DATA;
        assert!(state.secure_context());
    }

    #[test]
    fn xkbcommon_can_build_the_en_ru_keymap_when_installed() {
        let keymap = Keymap::new("en").expect("xkbcommon keymap");
        assert!(!keymap.text.is_empty());
        assert!(keymap.max_keycode >= keymap.min_keycode);
    }
}
