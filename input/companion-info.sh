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
safe_mode_marker="$config_home/omanome/safe-mode"

json_bool() {
  [[ "$1" == "1" ]] && printf true || printf false
}

runtime_version="unknown"
runtime_abi="unknown"
if command -v hyprctl >/dev/null 2>&1; then
  version_output="$(hyprctl version 2>/dev/null || true)"
  runtime_version="$(printf '%s\n' "$version_output" | sed -n '1s/^Hyprland[[:space:]]\+//p' | awk '{print $1}')"
  runtime_abi="$(printf '%s\n' "$version_output" | sed -n 's/^Version ABI string:[[:space:]]*//p' | head -n 1)"
fi

loaded=0
if command -v hyprctl >/dev/null 2>&1 && hyprctl plugins list 2>/dev/null | grep -Fq 'omanome-hypr'; then
  loaded=1
fi

built=0
[[ -f "$artifact" ]] && built=1
installed="$built"
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
if [[ -f "$install_dir/compatibility.json" ]] && command -v jq >/dev/null 2>&1; then
  build_abi="$(jq -r '.hyprland.abi // "unknown"' "$install_dir/compatibility.json")"
fi

abi_match=0
if [[ "$runtime_abi" != "unknown" && "$build_abi" != "unknown" && "$runtime_abi" == "$build_abi" ]]; then
  abi_match=1
fi

reason="companion unavailable"
if [[ "$crash_marker" == true ]]; then reason="previous load did not complete; explicit disable or rebuild is required"
elif [[ "$safe_mode" == true ]]; then reason="Omanome safe mode is active"
elif [[ "$loaded" -eq 1 && "$abi_match" -eq 1 ]]; then reason="compatible and loaded"
elif [[ "$loaded" -eq 1 ]]; then reason="loaded state could not be matched to the current ABI"
elif [[ "$built" -eq 1 ]]; then reason="installed but not loaded"
elif ! command -v hyprctl >/dev/null 2>&1; then reason="Hyprland IPC unavailable"
fi

jq -n \
  --arg runtimeVersion "$runtime_version" \
  --arg runtimeAbi "$runtime_abi" \
  --arg buildAbi "$build_abi" \
  --arg pluginVersion "$plugin_version" \
  --arg reason "$reason" \
  --argjson crashMarker "$crash_marker" \
  --argjson safeMode "$safe_mode" \
  --argjson protocolVersion "$protocol" \
  --argjson installed "$(json_bool "$installed")" \
  --argjson built "$(json_bool "$built")" \
  --argjson loaded "$(json_bool "$loaded")" \
  --argjson abiMatch "$(json_bool "$abi_match")" \
  '{protocolVersion:$protocolVersion,pluginVersion:$pluginVersion,installed:$installed,built:$built,loaded:$loaded,abiMatch:$abiMatch,crashMarker:$crashMarker,safeMode:$safeMode,reason:$reason,runtime:{version:$runtimeVersion,abi:$runtimeAbi},build:{abi:$buildAbi},capabilities:{blur:false,livePreview:false,wobblyWindows:false,desktopCube:false}}'
