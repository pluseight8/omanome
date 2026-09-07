// Pure lifecycle helpers shared by the headless service and its tests.
// A restart is a policy decision, never an unconditional timer loop.

var DEFAULTS = {
  initialDelayMs: 1000,
  maxDelayMs: 30000,
  maxConsecutiveFailures: 5,
  stableAfterMs: 30000
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function policy(spec) {
  var source = spec && typeof spec === "object" ? spec : {}
  return {
    initialDelayMs: Math.max(0, number(source.initialDelayMs, DEFAULTS.initialDelayMs)),
    maxDelayMs: Math.max(0, number(source.maxDelayMs, DEFAULTS.maxDelayMs)),
    maxConsecutiveFailures: Math.max(1, Math.floor(number(source.maxConsecutiveFailures, DEFAULTS.maxConsecutiveFailures))),
    stableAfterMs: Math.max(0, number(source.stableAfterMs, DEFAULTS.stableAfterMs))
  }
}

function backoffDelay(failures, spec) {
  var settings = policy(spec)
  var count = Math.max(0, Math.floor(number(failures, 0)))
  var delay = settings.initialDelayMs * Math.pow(2, Math.min(count, 10))
  return Math.min(settings.maxDelayMs, delay)
}

function nextRestart(state, now, spec) {
  var current = state && typeof state === "object" ? state : {}
  var settings = policy(spec)
  var timestamp = number(now, Date.now())
  var startedAt = number(current.startedAt, 0)
  var previousFailures = Math.max(0, Math.floor(number(current.consecutiveFailures, 0)))
  if (startedAt > 0 && timestamp - startedAt >= settings.stableAfterMs) previousFailures = 0
  var failures = previousFailures + 1
  if (failures > settings.maxConsecutiveFailures) {
    return {
      restart: false,
      blocked: true,
      consecutiveFailures: failures,
      delayMs: 0,
      reason: "crash-loop-limit"
    }
  }
  return {
    restart: true,
    blocked: false,
    consecutiveFailures: failures,
    delayMs: backoffDelay(failures - 1, settings),
    reason: "bounded-backoff"
  }
}

function stable(state, now, spec) {
  var current = state && typeof state === "object" ? state : {}
  var settings = policy(spec)
  var startedAt = number(current.startedAt, 0)
  return startedAt > 0 && number(now, Date.now()) - startedAt >= settings.stableAfterMs
}

function coalesceKey(argv) {
  var command = Array.isArray(argv) ? argv.map(function(item) { return String(item) }) : []
  if (command.length === 0) return ""
  var executable = command[0].split("/").pop()
  if (executable === "brightnessctl" && command[1] === "set") return "brightness"
  if (executable === "wpctl" && command[1] === "set-volume") return "volume:" + String(command[2] || "")
  if (executable === "powerprofilesctl" && command[1] === "set") return "power-profile"
  if (executable === "hyprctl" && command[1] === "keyword") return "hypr-keyword:" + String(command[2] || "")
  return ""
}

function redactedCommand(argv) {
  var command = Array.isArray(argv) ? argv.map(function(item) { return String(item) }) : []
  var result = []
  var executable = command.length > 0 ? command[0].split("/").pop() : ""
  var redactNext = false
  for (var i = 0; i < command.length; i++) {
    var value = command[i]
    if (redactNext) {
      result.push("<redacted>")
      redactNext = false
      continue
    }
    if (["password", "--password", "secret", "--secret", "token", "--token"].indexOf(value) >= 0) {
      result.push(value)
      redactNext = true
      continue
    }
    if (executable === "wtype" && i > 0 && ["-k", "-M", "-m", "--"].indexOf(value) < 0) {
      result.push("<input>")
      continue
    }
    if (executable === "bash" && value === "-c") {
      result.push(value)
      if (i + 1 < command.length) result.push("<script>")
      break
    }
    result.push(value)
  }
  return result
}

var api = {
  DEFAULTS: DEFAULTS,
  policy: policy,
  backoffDelay: backoffDelay,
  nextRestart: nextRestart,
  stable: stable,
  coalesceKey: coalesceKey,
  redactedCommand: redactedCommand
}

if (typeof module !== "undefined") module.exports = api
