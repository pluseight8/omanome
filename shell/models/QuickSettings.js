function enabled(config, key, fallback) {
  var source = config && config.quickSettings ? config.quickSettings : {}
  return source[key] === undefined ? fallback !== false : source[key] === true
}

function stateFromSystem(system) {
  var value = system || {}
  return {
    wifi: value.wifiEnabled === true,
    bluetooth: value.bluetoothPowered === true,
    airplane: value.airplane === true,
    volume: value.volumeMuted !== true,
    microphone: value.microphoneMuted !== true,
    nightLight: value.nightLight === true,
    dnd: value.dnd === true,
    rotationLock: value.rotationLock === true,
    recording: value.recording === true,
    powerProfile: String(value.powerProfile || "balanced")
  }
}

function cyclePowerProfile(profile) {
  var values = ["balanced", "performance", "power-saver"]
  var current = String(profile || "balanced")
  var index = values.indexOf(current)
  return values[(index + 1 + values.length) % values.length]
}

var api = { enabled: enabled, stateFromSystem: stateFromSystem, cyclePowerProfile: cyclePowerProfile }
if (typeof module !== "undefined") module.exports = api
