// Orientation input is noisy on real sensors. This model keeps a candidate
// until it has been stable long enough and enforces a minimum dwell between
// committed rotations.

function clean(value) {
  var name = String(value || "").toLowerCase()
  if (name.indexOf("right-up") >= 0 || name === "portrait") return "right-up"
  if (name.indexOf("left-up") >= 0 || name === "portrait-flipped") return "left-up"
  if (name.indexOf("bottom-up") >= 0 || name === "landscape-flipped") return "bottom-up"
  if (name.indexOf("normal") >= 0 || name === "landscape") return "normal"
  return ""
}

function emptyState() {
  return { current: "normal", candidate: "", candidateSince: 0, lastChangedAt: 0 }
}

function observe(previous, value, now, config) {
  var old = Object.assign(emptyState(), previous || {})
  var next = String(clean(value) || old.current || "normal")
  var timestamp = Number(now)
  if (!isFinite(timestamp)) timestamp = Date.now()
  var settings = config || {}
  var stableMs = Math.max(120, Number(settings.stableMs || 550))
  var dwellMs = Math.max(0, Number(settings.minimumDwellMs || 1000))
  if (next === old.current) return { changed: false, pending: false, delayMs: 0, value: old.current, state: { current: old.current, candidate: "", candidateSince: 0, lastChangedAt: old.lastChangedAt || timestamp } }
  if (old.candidate !== next || !Number(old.candidateSince || 0)) {
    return { changed: false, pending: true, delayMs: stableMs, value: old.current, state: { current: old.current, candidate: next, candidateSince: timestamp, lastChangedAt: old.lastChangedAt || timestamp } }
  }
  var remaining = Math.max(stableMs - (timestamp - old.candidateSince), dwellMs - (timestamp - Number(old.lastChangedAt || 0)))
  if (remaining > 0) return { changed: false, pending: true, delayMs: remaining, value: old.current, state: old }
  return { changed: true, pending: false, delayMs: 0, value: next, state: { current: next, candidate: "", candidateSince: 0, lastChangedAt: timestamp } }
}

var api = { clean: clean, emptyState: emptyState, observe: observe }
if (typeof module !== "undefined") module.exports = api
