#!/usr/bin/env bash
# Emit a compact snapshot of optional user-session backends for Quick Settings.
# Every probe is best-effort: a missing backend is reported as unavailable and
# never replaced with a guessed local boolean.
set -u

bool_value() {
  [[ "${1:-}" == "true" ]] && printf 'true' || printf 'false'
}

wifi_available=false
wifi_enabled=false
wifi_connected=false
wifi_ssid=""
wifi_signal=-1
airplane=false
if command -v nmcli >/dev/null 2>&1; then
  wifi_available=true
  radio="$(nmcli -t -f WIFI radio 2>/dev/null || true)"
  [[ "$radio" == enabled* ]] && wifi_enabled=true
  all_radio="$(nmcli -t radio 2>/dev/null || true)"
  [[ "$all_radio" == disabled:* ]] && airplane=true
  active="$(nmcli -t --separator $'\t' -f TYPE,STATE,CONNECTION,SIGNAL device status 2>/dev/null | awk -F '\t' '$1 == "wifi" { print; exit }' || true)"
  if [[ -n "$active" ]]; then
    IFS=$'\t' read -r type state connection signal _ <<<"$active"
    [[ "$state" == connected* ]] && wifi_connected=true
    wifi_ssid="$connection"
    [[ "${signal:-}" =~ ^[0-9]+$ ]] && wifi_signal="$signal"
  fi
fi

bluetooth_available=false
bluetooth_powered=false
if command -v bluetoothctl >/dev/null 2>&1; then
  bluetooth_available=true
  powered="$(bluetoothctl show 2>/dev/null | awk '$1 == "Powered:" { print $2; exit }' || true)"
  [[ "$powered" == "yes" ]] && bluetooth_powered=true
fi

volume_available=false
volume=0
volume_muted=false
if command -v wpctl >/dev/null 2>&1; then
  volume_available=true
  raw_volume="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
  volume="$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)?$/) { printf "%.0f", $i * 100; exit } }' <<<"$raw_volume")"
  [[ "$raw_volume" == *MUTED* ]] && volume_muted=true
fi

microphone_available=false
microphone_volume=0
microphone_muted=false
if command -v wpctl >/dev/null 2>&1; then
  microphone_available=true
  raw_microphone="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)"
  microphone_volume="$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)?$/) { printf "%.0f", $i * 100; exit } }' <<<"$raw_microphone")"
  [[ "$raw_microphone" == *MUTED* ]] && microphone_muted=true
fi

brightness_available=false
brightness=0
if command -v brightnessctl >/dev/null 2>&1; then
  brightness_available=true
  brightness="$(brightnessctl -m 2>/dev/null | awk -F, 'NR == 1 { gsub(/%/, "", $4); print $4; exit }' || true)"
fi

power_profile_available=false
power_profile="balanced"
if command -v powerprofilesctl >/dev/null 2>&1; then
  power_profile_available=true
  power_profile="$(powerprofilesctl get 2>/dev/null || printf 'balanced')"
fi

battery_available=false
battery_percent=-1
battery_state="unknown"
if command -v upower >/dev/null 2>&1; then
  battery_device="$(upower -e 2>/dev/null | awk '/battery/ { print; exit }' || true)"
  if [[ -n "$battery_device" ]]; then
    battery_available=true
    battery_percent="$(upower -i "$battery_device" 2>/dev/null | awk '/percentage:/ { gsub(/%/, "", $2); print $2; exit }' || true)"
    battery_state="$(upower -i "$battery_device" 2>/dev/null | awk '/state:/ { print $2; exit }' || printf 'unknown')"
  fi
fi

# Keep all numeric fields valid JSON numbers even when a backend returns an
# empty value or a localized/unexpected response.  A failed probe must make a
# feature unavailable, not break the complete snapshot.
[[ "$wifi_signal" =~ ^-?[0-9]+$ ]] || wifi_signal=-1
[[ "$volume" =~ ^-?[0-9]+$ ]] || volume=0
[[ "$microphone_volume" =~ ^-?[0-9]+$ ]] || microphone_volume=0
[[ "$brightness" =~ ^-?[0-9]+$ ]] || brightness=0
[[ "$battery_percent" =~ ^-?[0-9]+$ ]] || battery_percent=-1

night_light_available=false
night_light_enabled=false
command -v hyprsunset >/dev/null 2>&1 && night_light_available=true
if command -v pgrep >/dev/null 2>&1 && pgrep -x hyprsunset >/dev/null 2>&1; then
  night_light_enabled=true
fi

recording_available=false
command -v wf-recorder >/dev/null 2>&1 && recording_available=true

rotation_available=false
rotation_sensor_available=false
rotation_dbus_available=false
rotation_accelerometer_available=false
rotation_sensor_backend="manual"
touch_transform=0
tablet_transform=0
if command -v hyprctl >/dev/null 2>&1 && hyprctl getoption input:touchdevice:transform -j >/dev/null 2>&1; then
  rotation_available=true
  touch_transform="$(hyprctl getoption input:touchdevice:transform -j 2>/dev/null | jq -r '.int // 0' 2>/dev/null || printf '0')"
  tablet_transform="$(hyprctl getoption input:tablet:transform -j 2>/dev/null | jq -r '.int // 0' 2>/dev/null || printf '0')"
fi
[[ "$touch_transform" =~ ^[0-3]$ ]] || touch_transform=0
[[ "$tablet_transform" =~ ^[0-3]$ ]] || tablet_transform=0
if command -v monitor-sensor >/dev/null 2>&1; then
  rotation_sensor_available=true
  rotation_accelerometer_available=true
  rotation_sensor_backend="monitor-sensor"
fi
if command -v gdbus >/dev/null 2>&1 && \
   gdbus introspect --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy >/dev/null 2>&1; then
  rotation_dbus_available=true
  [[ "$rotation_sensor_backend" == "manual" ]] && rotation_sensor_backend="dbus-iio"
  has_accelerometer="$(gdbus call --system --dest net.hadess.SensorProxy \
    --object-path /net/hadess/SensorProxy \
    --method org.freedesktop.DBus.Properties.Get \
    net.hadess.SensorProxy HasAccelerometer 2>/dev/null || true)"
  if [[ "$has_accelerometer" == *true* ]]; then
    rotation_sensor_available=true
    rotation_accelerometer_available=true
  fi
fi

jq -cn \
  --argjson wifiAvailable "$(bool_value "$wifi_available")" \
  --argjson wifiEnabled "$(bool_value "$wifi_enabled")" \
  --argjson wifiConnected "$(bool_value "$wifi_connected")" \
  --argjson airplane "$(bool_value "$airplane")" \
  --arg wifiSsid "$wifi_ssid" \
  --argjson wifiSignal "${wifi_signal:--1}" \
  --argjson bluetoothAvailable "$(bool_value "$bluetooth_available")" \
  --argjson bluetoothPowered "$(bool_value "$bluetooth_powered")" \
  --argjson volumeAvailable "$(bool_value "$volume_available")" \
  --argjson volume "$volume" \
  --argjson volumeMuted "$(bool_value "$volume_muted")" \
  --argjson microphoneAvailable "$(bool_value "$microphone_available")" \
  --argjson microphoneVolume "$microphone_volume" \
  --argjson microphoneMuted "$(bool_value "$microphone_muted")" \
  --argjson brightnessAvailable "$(bool_value "$brightness_available")" \
  --argjson brightness "$brightness" \
  --argjson powerProfileAvailable "$(bool_value "$power_profile_available")" \
  --arg powerProfile "$power_profile" \
  --argjson batteryAvailable "$(bool_value "$battery_available")" \
  --argjson batteryPercent "$battery_percent" \
  --arg batteryState "$battery_state" \
  --argjson nightLightAvailable "$(bool_value "$night_light_available")" \
  --argjson nightLightEnabled "$(bool_value "$night_light_enabled")" \
  --argjson recordingAvailable "$(bool_value "$recording_available")" \
  --argjson rotationAvailable "$(bool_value "$rotation_available")" \
  --argjson rotationSensorAvailable "$(bool_value "$rotation_sensor_available")" \
  --argjson rotationDbusAvailable "$(bool_value "$rotation_dbus_available")" \
  --argjson rotationAccelerometerAvailable "$(bool_value "$rotation_accelerometer_available")" \
  --arg rotationSensorBackend "$rotation_sensor_backend" \
  --argjson touchTransform "$touch_transform" \
  --argjson tabletTransform "$tablet_transform" \
  '{wifiAvailable:$wifiAvailable,wifiEnabled:$wifiEnabled,wifiConnected:$wifiConnected,airplane:$airplane,wifiSsid:$wifiSsid,wifiSignal:$wifiSignal,bluetoothAvailable:$bluetoothAvailable,bluetoothPowered:$bluetoothPowered,volumeAvailable:$volumeAvailable,volume:$volume,volumeMuted:$volumeMuted,microphoneAvailable:$microphoneAvailable,microphoneVolume:$microphoneVolume,microphoneMuted:$microphoneMuted,brightnessAvailable:$brightnessAvailable,brightness:$brightness,powerProfileAvailable:$powerProfileAvailable,powerProfile:$powerProfile,batteryAvailable:$batteryAvailable,batteryPercent:$batteryPercent,batteryState:$batteryState,nightLightAvailable:$nightLightAvailable,nightLightEnabled:$nightLightEnabled,dndAvailable:false,rotationAvailable:$rotationAvailable,rotationSensorAvailable:$rotationSensorAvailable,rotationDbusAvailable:$rotationDbusAvailable,rotationAccelerometerAvailable:$rotationAccelerometerAvailable,rotationSensorBackend:$rotationSensorBackend,touchTransform:$touchTransform,tabletTransform:$tabletTransform,rotationLock:false,recordingAvailable:$recordingAvailable,recording:false}'
