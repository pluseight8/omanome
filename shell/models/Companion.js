function stringValue(value, fallback) {
  var result = String(value === undefined || value === null ? "" : value)
  return result || String(fallback || "")
}

function boolValue(value) {
  return value === true || value === 1 || value === "1" || value === "true"
}

function capability(snapshot, name) {
  var capabilities = snapshot && snapshot.capabilities && typeof snapshot.capabilities === "object" ? snapshot.capabilities : {}
  return boolValue(capabilities[name])
}

function normalize(snapshot) {
  var source = snapshot && typeof snapshot === "object" ? snapshot : {}
  var runtime = source.runtime && typeof source.runtime === "object" ? source.runtime : {}
  var build = source.build && typeof source.build === "object" ? source.build : {}
  var compatibility = source.compatibility && typeof source.compatibility === "object" ? source.compatibility : {}
  var installed = boolValue(source.installed)
  var loaded = boolValue(source.loaded)
  var safeMode = boolValue(source.safeMode)
  var protocolVersion = Number(source.protocolVersion || compatibility.protocolVersion || 0)
  var runtimeAbi = stringValue(runtime.abi, source.runtimeAbi)
  var buildAbi = stringValue(build.abi, source.buildAbi)
  var abiMatch = boolValue(source.abiMatch) || Boolean(runtimeAbi && buildAbi && runtimeAbi === buildAbi)
  var pluginVersion = stringValue(source.pluginVersion, compatibility.pluginVersion)
  var versionMatch = boolValue(source.versionMatch) || !compatibility.pluginVersion || Boolean(pluginVersion && pluginVersion === stringValue(compatibility.pluginVersion))
  var compatible = !safeMode && installed && loaded && protocolVersion === 1 && abiMatch && versionMatch
  return {
    installed: installed,
    built: boolValue(source.built),
    loaded: loaded,
    safeMode: safeMode,
    protocolVersion: protocolVersion,
    pluginVersion: pluginVersion || "unknown",
    runtime: { version: stringValue(runtime.version, "unknown"), abi: runtimeAbi || "unknown" },
    build: { version: stringValue(build.version, "unknown"), abi: buildAbi || "unknown" },
    abiMatch: abiMatch,
    versionMatch: versionMatch,
    compatible: compatible,
    capabilities: {
      blur: capability(source, "blur"),
      livePreview: capability(source, "livePreview"),
      wobblyWindows: capability(source, "wobblyWindows"),
      desktopCube: capability(source, "desktopCube")
    },
    reason: stringValue(source.reason, compatible ? "compatible" : "companion unavailable or incompatible")
  }
}

function canLoad(snapshot) {
  var state = normalize(snapshot)
  return state.installed && state.built && !state.safeMode && state.protocolVersion === 1 && state.abiMatch && state.versionMatch
}

function effectAvailable(snapshot, name) {
  var state = normalize(snapshot)
  return state.compatible && state.capabilities[name] === true
}

var api = { normalize: normalize, canLoad: canLoad, effectAvailable: effectAvailable }
if (typeof module !== "undefined") module.exports = api
