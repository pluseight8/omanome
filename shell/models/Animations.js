var PRESETS = {
  "GNOME": { durationScale: 1.0, speedMultiplier: 1.0, easing: "standard", springStrength: 0.65 },
  "Smooth": { durationScale: 1.18, speedMultiplier: 0.9, easing: "smooth", springStrength: 0.78 },
  "Snappy": { durationScale: 0.72, speedMultiplier: 1.25, easing: "snappy", springStrength: 0.45 },
  "Playful": { durationScale: 1.12, speedMultiplier: 0.95, easing: "spring", springStrength: 0.95 },
  "Minimal": { durationScale: 0.56, speedMultiplier: 1.4, easing: "linear", springStrength: 0.15 },
  "Disabled": { durationScale: 0.0, speedMultiplier: 100.0, easing: "linear", springStrength: 0.0 }
}

function clamp(value, minimum, maximum, fallback) {
  var number = Number(value)
  if (!isFinite(number)) number = Number(fallback)
  return Math.max(minimum, Math.min(maximum, number))
}

function normalize(config, reducedMotion) {
  var source = config && typeof config === "object" ? config : {}
  var presetName = String(source.preset || "GNOME")
  var preset = PRESETS[presetName] || PRESETS.GNOME
  var reduced = reducedMotion === true || source.reducedMotion === true
  var enabled = source.enabled !== false && presetName !== "Disabled" && !reduced
  return {
    enabled: enabled,
    preset: reduced ? "Reduced motion" : (PRESETS[presetName] ? presetName : "GNOME"),
    durationScale: enabled ? clamp(source.durationScale, 0.1, 2.0, preset.durationScale) : 0.0,
    speedMultiplier: enabled ? clamp(source.speedMultiplier, 0.25, 3.0, preset.speedMultiplier) : 100.0,
    easing: String(source.easing || preset.easing),
    springStrength: enabled ? clamp(source.springStrength, 0.0, 1.0, preset.springStrength) : 0.0,
    reducedMotion: reduced
  }
}

function transition(config, baseDuration, reducedMotion) {
  var motion = normalize(config, reducedMotion)
  var duration = Math.max(0, Math.round(Number(baseDuration || 0) * motion.durationScale / motion.speedMultiplier))
  if (motion.reducedMotion) duration = Math.min(80, duration)
  return { enabled: motion.enabled, duration: duration, easing: motion.easing, springStrength: motion.springStrength }
}

function dockHover(config, inputKind) {
  var kind = String(inputKind || "mouse")
  var touchLike = kind === "touch" || kind === "stylus" || kind === "touchpad"
  return { enabled: !touchLike && config && config.hoverZoom === true, scale: touchLike ? 1.0 : clamp(config && config.hoverScale, 1.0, 1.8, 1.2) }
}

var api = { PRESETS: PRESETS, normalize: normalize, transition: transition, dockHover: dockHover }
if (typeof module !== "undefined") module.exports = api
