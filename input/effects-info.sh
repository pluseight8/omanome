#!/usr/bin/env bash
set -Eeuo pipefail

# Probe only compositor contracts. This script never infers an effect from a
# translucent QML rectangle or a screenshot file. Live preview is implemented
# by Quickshell ScreencopyView and is reported as usable only after the running
# shell observes compositor-owned content from hyprland-toplevel-export-v1.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$script_dir/.." && pwd -P)"

hyprland_available=false
runtime_version="unknown"
runtime_abi="unknown"
plugin_output=""
if command -v hyprctl >/dev/null 2>&1; then
  version_output="$(hyprctl version 2>/dev/null || true)"
  if [[ "$version_output" == *Hyprland* ]]; then
    hyprland_available=true
    runtime_version="$(printf '%s\n' "$version_output" | sed -n '1s/^Hyprland[[:space:]]\+//p' | awk '{print $1}')"
    runtime_abi="$(printf '%s\n' "$version_output" | sed -n 's/^Version ABI string:[[:space:]]*//p' | head -n 1)"
  fi
  plugin_output="$(hyprctl plugins list 2>/dev/null || true)"
fi

layer_rules_available="$hyprland_available"
omanome_loaded=false
desktop_cube_loaded=false
if [[ "$plugin_output" == *omanome-hypr* ]]; then omanome_loaded=true; fi
if [[ "$plugin_output" == *omarchy-desktop-cube* || "$plugin_output" == *desktop-cube* ]]; then desktop_cube_loaded=true; fi

companion='{}'
if [[ -x "$repo_dir/input/companion-info.sh" ]]; then
  companion="$(bash "$repo_dir/input/companion-info.sh" 2>/dev/null || printf '{}')"
fi
if ! jq -e . >/dev/null 2>&1 <<<"$companion"; then companion='{}'; fi

jq -cn \
  --arg runtimeVersion "$runtime_version" \
  --arg runtimeAbi "$runtime_abi" \
  --argjson hyprlandAvailable "$hyprland_available" \
  --argjson layerRulesAvailable "$layer_rules_available" \
  --argjson omanomeLoaded "$omanome_loaded" \
  --argjson desktopCubeLoaded "$desktop_cube_loaded" \
  --argjson companion "$companion" \
  '{hyprlandAvailable:$hyprlandAvailable,runtime:{version:$runtimeVersion,abi:$runtimeAbi},backend:"hyprland-layer-rule",layerRulesAvailable:$layerRulesAvailable,livePreviewAvailable:false,livePreviewBackend:"quickshell-screencopy",livePreviewProtocol:"hyprland-toplevel-export-v1",livePreviewReason:"waiting for Quickshell ScreencopyView hasContent runtime probe",plugins:{omanomeHyprLoaded:$omanomeLoaded,desktopCubeLoaded:$desktopCubeLoaded},external:{desktopCube:$desktopCubeLoaded,desktopCubeBackend:(if $desktopCubeLoaded then "omarchy-desktop-cube" else "none" end)},companion:$companion}'
