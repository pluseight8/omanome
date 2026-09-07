// Session/backend lifecycle transitions are explicit and idempotent. The
// model is used by the shell around event-driven suspend/resume and reconnect
// notifications; it never polls or owns a process itself.

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function eventName(value) {
  return String(value || "").toLowerCase().replace(/[_\s]+/g, "-")
}

function emptyState() {
  return { schemaVersion: 1, phase: "active", locked: false, generation: 0, lastEvent: "", lastChangedAt: 0, reconnect: { attempts: 0, blocked: false } }
}

function transition(previous, rawEvent, now) {
  var old = Object.assign(emptyState(), object(previous))
  var source = object(rawEvent)
  var kind = eventName(source.event || source.action || source.state)
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var next = Object.assign({}, old)
  next.lastEvent = kind
  next.generation = Number(old.generation || 0)
  next.lastChangedAt = Number(old.lastChangedAt || 0)
  if (kind === "suspend" || kind === "sleep" || kind === "prepare-for-sleep") {
    if (old.phase !== "suspended") next.generation++
    next.phase = "suspended"
    next.lastChangedAt = timestamp
  } else if (kind === "resume" || kind === "wakeup" || kind === "post-sleep") {
    if (old.phase !== "active") next.generation++
    next.phase = "active"
    next.lastChangedAt = timestamp
  } else if (kind === "lock" || kind === "locked") {
    next.locked = true
    next.lastChangedAt = timestamp
  } else if (kind === "unlock" || kind === "unlocked") {
    next.locked = false
    next.lastChangedAt = timestamp
  } else if (kind === "wayland-disconnected" || kind === "disconnect") {
    next.phase = "reconnecting"
    next.generation++
    next.lastChangedAt = timestamp
  } else if (kind === "wayland-reconnected" || kind === "reconnect") {
    next.phase = "active"
    next.generation++
    next.lastChangedAt = timestamp
    next.reconnect = { attempts: 0, blocked: false }
  } else return { changed: false, state: next, action: "ignore" }
  next.locked = kind === "lock" || kind === "locked" ? true : (kind === "unlock" || kind === "unlocked" ? false : old.locked === true)
  var action = next.phase === "suspended" ? "pause-backends" : (next.phase === "active" ? "refresh-backends" : "reconnect-backends")
  if (next.locked) action += "+privacy-lock"
  return { changed: next.generation !== old.generation || next.locked !== (old.locked === true), state: next, action: action }
}

function reconnect(previous, now, policy) {
  var old = Object.assign({ attempts: 0, blocked: false, startedAt: 0 }, object(previous))
  var settings = object(policy)
  var maximum = Math.max(1, Number(settings.maxAttempts || 5))
  var initial = Math.max(100, Number(settings.initialDelayMs || 1000))
  var maximumDelay = Math.max(initial, Number(settings.maxDelayMs || 30000))
  var attempts = Number(old.attempts || 0) + 1
  var blocked = attempts >= maximum
  var delay = Math.min(maximumDelay, initial * Math.pow(2, Math.max(0, attempts - 1)))
  return { attempts: attempts, blocked: blocked, delayMs: delay, retry: !blocked, reason: blocked ? "reconnect-crash-loop-limit" : "bounded-backoff" }
}

var api = { emptyState: emptyState, transition: transition, reconnect: reconnect }
if (typeof module !== "undefined") module.exports = api
