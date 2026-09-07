var INPUTS = ["mouse", "touchpad", "touch", "stylus", "keyboard"]

function normalize(value) {
  var result = String(value || "keyboard").toLowerCase()
  return INPUTS.indexOf(result) >= 0 ? result : "keyboard"
}

function delay(kind, configured) {
  var value = Number(configured)
  if (!isFinite(value) || value < 80) value = 320
  var input = normalize(kind)
  if (input === "touch" || input === "stylus") return Math.max(value, 360)
  if (input === "keyboard") return Math.min(value, 280)
  return value
}

function state(source) {
  var value = source || {}
  return {
    current: normalize(value.current),
    pending: value.pending ? normalize(value.pending) : "",
    pendingSince: Number(value.pendingSince) > 0 ? Number(value.pendingSince) : 0
  }
}

function observe(source, candidate, now, configuredDelay) {
  var result = state(source)
  var value = normalize(candidate)
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = 0
  if (value === result.current) {
    result.pending = ""
    result.pendingSince = 0
    return result
  }
  if (result.pending !== value) {
    result.pending = value
    result.pendingSince = timestamp
    return result
  }
  if (timestamp - result.pendingSince >= delay(value, configuredDelay)) {
    result.current = value
    result.pending = ""
    result.pendingSince = 0
  }
  return result
}

function commit(source, now, configuredDelay) {
  var result = state(source)
  if (!result.pending) return result
  var timestamp = Number(now)
  if (isFinite(timestamp) && timestamp - result.pendingSince >= delay(result.pending, configuredDelay)) {
    result.current = result.pending
    result.pending = ""
    result.pendingSince = 0
  }
  return result
}

var api = { INPUTS: INPUTS, normalize: normalize, delay: delay, state: state, observe: observe, commit: commit }
if (typeof module !== "undefined") module.exports = api
