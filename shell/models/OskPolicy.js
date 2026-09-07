// OSK visibility is a policy decision, not a focus guess.  The helper must
// report a real text-input activation before this state can become visible.

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function desired(source) {
  var item = source && typeof source === "object" ? source : {}
  if (item.autoShow !== true) return { visible: false, reason: "auto-show-disabled" }
  if (item.textFocus !== true) return { visible: false, reason: "text-focus-unavailable" }
  if (item.secure === true && item.securePolicy === "never") return { visible: false, reason: "secure-field-policy" }
  if (item.physicalKeyboard === true) return { visible: false, reason: "physical-keyboard-present" }
  if (item.detachableKeyboard === true || item.bluetoothKeyboard === true)
    return { visible: false, reason: "external-keyboard-present" }
  if (["touch", "stylus"].indexOf(String(item.lastInput || "")) < 0)
    return { visible: false, reason: "last-input-not-touch" }
  if (item.mode === "desktop" && item.touchscreen !== true && item.lastInput !== "stylus")
    return { visible: false, reason: "desktop-without-touchscreen" }
  return { visible: true, reason: item.lastInput === "stylus" ? "stylus-text-focus" : "touch-text-focus" }
}

function transition(source, state, now) {
  var current = state && typeof state === "object" ? state : {}
  var timestamp = number(now, 0)
  var target = desired(source)
  var visible = current.visible === true
  var pending = current.pending === true ? true : (current.pending === false ? false : null)
  var pendingSince = number(current.pendingSince, 0)
  if (target.visible === visible) {
    return {
      changed: false,
      pending: false,
      delayMs: 0,
      reason: target.reason,
      state: { visible: visible, pending: false, pendingSince: 0, reason: target.reason }
    }
  }
  if (pending !== target.visible) {
    return {
      changed: false,
      pending: true,
      delayMs: target.visible ? 120 : 240,
      reason: target.reason,
      state: { visible: visible, pending: target.visible, pendingSince: timestamp, reason: target.reason }
    }
  }
  var delay = target.visible ? 120 : 240
  if (timestamp - pendingSince < delay) {
    return {
      changed: false,
      pending: true,
      delayMs: Math.max(1, delay - Math.max(0, timestamp - pendingSince)),
      reason: target.reason,
      state: { visible: visible, pending: target.visible, pendingSince: pendingSince, reason: target.reason }
    }
  }
  return {
    changed: true,
    pending: false,
    delayMs: 0,
    reason: target.reason,
    state: { visible: target.visible, pending: false, pendingSince: 0, reason: target.reason }
  }
}

var api = { desired: desired, transition: transition }
if (typeof module !== "undefined") module.exports = api
