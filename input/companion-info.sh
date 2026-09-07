#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$script_dir/.." && pwd -P)"
manifest="$repo_dir/hypr/omanome-hypr/compatibility.json"
user_home="${HOME:-}"
data_home="${XDG_DATA_HOME:-$user_home/.local/share}"
install_dir="$data_home/omanome/companion"
artifact="$install_dir/omanome-hypr.so"
state_home="${XDG_STATE_HOME:-$user_home/.local/state}"
config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
pending_marker="$state_home/omanome/companion/load.pending"
disabled_marker="$state_home/omanome/companion/disabled"
lifecycle_file="$state_home/omanome/companion/lifecycle.json"
safe_mode_marker="$config_home/omanome/safe-mode"

json_bool() {
  [[ "$1" == "1" ]] && printf true || printf false
}

runtime_version="unknown"
runtime_abi="unknown"
runtime_commit="unknown"
if command -v hyprctl >/dev/null 2>&1; then
  version_output="$(hyprctl version 2>/dev/null || true)"
  runtime_version="$(printf '%s\n' "$version_output" | sed -n '1s/^Hyprland[[:space:]]\+//p' | awk '{print $1}')"
  runtime_commit="$(printf '%s\n' "$version_output" | sed -n '1s/.*commit[[:space:]]\+\([[:alnum:]_:-]\+\).*/\1/p' | head -n 1)"
  runtime_abi="$(printf '%s\n' "$version_output" | sed -n 's/^Version ABI string:[[:space:]]*//p' | head -n 1)"
fi

loaded=0
plugin_status='{}'
if command -v hyprctl >/dev/null 2>&1 && hyprctl plugins list 2>/dev/null | grep -Fq 'omanome-hypr'; then
  loaded=1
  plugin_status="$(hyprctl -j omanome-effects 2>/dev/null || true)"
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$plugin_status"; then plugin_status='{}'; fi
fi

built=0
[[ -f "$artifact" ]] && built=1
installed="$built"
enabled=0
[[ "$built" -eq 1 && ! -f "$disabled_marker" ]] && enabled=1
crash_marker=false
safe_mode=false
[[ -f "$pending_marker" ]] && crash_marker=true
[[ -f "$safe_mode_marker" ]] && safe_mode=true

protocol="0"
plugin_version="unknown"
if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
  protocol="$(jq -r '.protocolVersion // 0' "$manifest")"
  plugin_version="$(jq -r '.pluginVersion // "unknown"' "$manifest")"
fi

build_abi="unknown"
build_version="unknown"
build_commit="unknown"
build_compiler="unknown"
build_plugin="unknown"
artifact_hash="unknown"
artifact_hash_match=0
if [[ -f "$install_dir/compatibility.json" ]] && command -v jq >/dev/null 2>&1; then
  build_abi="$(jq -r '.build.hyprlandAbi // .hyprland.abi // "unknown"' "$install_dir/compatibility.json")"
  build_version="$(jq -r '.build.hyprlandVersion // .hyprland.version // "unknown"' "$install_dir/compatibility.json")"
  build_commit="$(jq -r '.build.hyprlandCommit // .hyprland.commit // "unknown"' "$install_dir/compatibility.json")"
  build_compiler="$(jq -r '.build.compiler // "unknown"' "$install_dir/compatibility.json")"
  build_plugin="$(jq -r '.build.pluginBuild // "unknown"' "$install_dir/compatibility.json")"
  artifact_hash="$(jq -r '.build.artifactSha256 // "unknown"' "$install_dir/compatibility.json")"
fi

abi_match=0
if [[ "$runtime_abi" != "unknown" && "$build_abi" != "unknown" && "$runtime_abi" == "$build_abi" ]]; then
  abi_match=1
fi

version_match=0
if [[ "$runtime_version" != "unknown" && "$build_version" != "unknown" && "$runtime_version" == "$build_version" ]]; then
  version_match=1
fi

plugin_build_match=0
if [[ "$build_plugin" != "unknown" && "$plugin_version" != "unknown" && "$build_plugin" == "$plugin_version" ]]; then
  plugin_build_match=1
fi

actual_hash="unknown"
if [[ "$built" -eq 1 ]] && command -v sha256sum >/dev/null 2>&1; then
  actual_hash="$(sha256sum "$artifact" | awk '{print $1}')"
  if [[ "$artifact_hash" != "unknown" && "$actual_hash" == "$artifact_hash" ]]; then artifact_hash_match=1; fi
fi

status_protocol=0
status_hash_match=0
if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$plugin_status"; then
  status_protocol="$(jq -r '.protocolVersion // 0' <<<"$plugin_status")"
  [[ "$(jq -r '.api.hashMatch // false' <<<"$plugin_status")" == true ]] && status_hash_match=1
fi

crash_count=0
load_failure_count=0
last_crash=""
last_load_failure=""
if [[ -f "$lifecycle_file" ]] && command -v jq >/dev/null 2>&1; then
  crash_count="$(jq -r '.crashCount // 0' "$lifecycle_file" 2>/dev/null || printf '0')"
  load_failure_count="$(jq -r '.loadFailureCount // 0' "$lifecycle_file" 2>/dev/null || printf '0')"
  last_crash="$(jq -r 'if .lastCrash then (.lastCrash.at + ": " + .lastCrash.reason) else "" end' "$lifecycle_file" 2>/dev/null || true)"
  last_load_failure="$(jq -r 'if .lastLoadFailure then (.lastLoadFailure.at + ": " + .lastLoadFailure.reason) else "" end' "$lifecycle_file" 2>/dev/null || true)"
fi

reason="companion unavailable"
if [[ "$crash_marker" == true ]]; then reason="previous load did not complete; explicit disable or rebuild is required"
elif [[ "$safe_mode" == true ]]; then reason="Omanome safe mode is active"
elif [[ "$enabled" -eq 0 && "$built" -eq 1 ]]; then reason="disabled by user policy"
elif [[ "$loaded" -eq 1 && "$abi_match" -eq 1 && "$version_match" -eq 1 && "$plugin_build_match" -eq 1 && "$artifact_hash_match" -eq 1 && "$status_protocol" == "$protocol" && "$status_hash_match" -eq 1 ]]; then reason="compatible and loaded"
elif [[ "$loaded" -eq 1 ]]; then reason="loaded state could not be matched to the current version, ABI, integrity hash, plugin build, or protocol"
elif [[ "$built" -eq 1 && "$version_match" -eq 0 ]]; then reason="installed companion targets a different Hyprland version"
elif [[ "$built" -eq 1 ]]; then reason="installed but not loaded"
elif ! command -v hyprctl >/dev/null 2>&1; then reason="Hyprland IPC unavailable"
fi

jq -n \
  --arg runtimeVersion "$runtime_version" \
  --arg runtimeCommit "$runtime_commit" \
  --arg runtimeAbi "$runtime_abi" \
  --arg buildVersion "$build_version" \
  --arg buildCommit "$build_commit" \
  --arg buildAbi "$build_abi" \
  --arg buildCompiler "$build_compiler" \
  --arg buildPlugin "$build_plugin" \
  --arg artifactHash "$artifact_hash" \
  --arg actualHash "$actual_hash" \
  --arg lastCrash "$last_crash" \
  --arg lastLoadFailure "$last_load_failure" \
  --arg pluginVersion "$plugin_version" \
  --arg reason "$reason" \
  --argjson crashMarker "$crash_marker" \
  --argjson safeMode "$safe_mode" \
  --argjson protocolVersion "$protocol" \
  --argjson pluginStatus "$plugin_status" \
  --argjson installed "$(json_bool "$installed")" \
  --argjson built "$(json_bool "$built")" \
  --argjson enabled "$(json_bool "$enabled")" \
  --argjson loaded "$(json_bool "$loaded")" \
  --argjson abiMatch "$(json_bool "$abi_match")" \
  --argjson versionMatch "$(json_bool "$version_match")" \
  --argjson pluginBuildMatch "$(json_bool "$plugin_build_match")" \
  --argjson artifactHashMatch "$(json_bool "$artifact_hash_match")" \
  --argjson statusProtocol "$status_protocol" \
  --argjson statusHashMatch "$(json_bool "$status_hash_match")" \
  --argjson crashCount "$crash_count" \
  --argjson loadFailureCount "$load_failure_count" \
  '{protocolVersion:$protocolVersion,pluginVersion:$pluginVersion,installed:$installed,built:$built,enabled:$enabled,loaded:$loaded,abiMatch:$abiMatch,versionMatch:$versionMatch,pluginBuildMatch:$pluginBuildMatch,artifactHashMatch:$artifactHashMatch,crashMarker:$crashMarker,safeMode:$safeMode,crashCount:$crashCount,loadFailureCount:$loadFailureCount,lastCrash:$lastCrash,lastLoadFailure:$lastLoadFailure,reason:$reason,runtime:{version:$runtimeVersion,commit:$runtimeCommit,abi:$runtimeAbi},build:{version:$buildVersion,commit:$buildCommit,abi:$buildAbi,compiler:$buildCompiler,pluginBuild:$buildPlugin,artifactSha256:$artifactHash,actualArtifactSha256:$actualHash},statusProtocol:$statusProtocol,statusHashMatch:$statusHashMatch,status:$pluginStatus,capabilities:($pluginStatus.capabilities // {blur:false,livePreview:false,wobblyWindows:false,desktopCube:false})}'
