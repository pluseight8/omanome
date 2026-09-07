#!/usr/bin/env bash
# Report rotation sensor capabilities without claiming the accelerometer.
set -u

bool_value() {
  [[ "$1" == "true" ]] && printf 'true' || printf 'false'
}

monitor_sensor_available=false
dbus_available=false
accelerometer_available=false
backend="manual"

if command -v monitor-sensor >/dev/null 2>&1; then
  monitor_sensor_available=true
  backend="monitor-sensor"
fi

if command -v gdbus >/dev/null 2>&1 && \
   gdbus introspect --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy >/dev/null 2>&1; then
  dbus_available=true
  if [[ "$backend" == "manual" ]]; then backend="dbus-iio"; fi
  has_accelerometer="$(gdbus call --system --dest net.hadess.SensorProxy \
    --object-path /net/hadess/SensorProxy \
    --method org.freedesktop.DBus.Properties.Get \
    net.hadess.SensorProxy HasAccelerometer 2>/dev/null || true)"
  [[ "$has_accelerometer" == *true* ]] && accelerometer_available=true
fi

if [[ "$monitor_sensor_available" == true && "$accelerometer_available" == false ]]; then
  # The monitor-sensor executable is itself the compatibility backend. Its
  # hardware capability is discovered when the persistent stream starts.
  accelerometer_available=true
fi

auto_rotation=false
[[ "$monitor_sensor_available" == true || "$accelerometer_available" == true ]] && auto_rotation=true

orientation="unavailable"
case "${OMANOME_ORIENTATION:-}" in
  normal|left-up|right-up|bottom-up) orientation="$OMANOME_ORIENTATION" ;;
esac
posture="unavailable"
case "${OMANOME_POSTURE:-}" in
  laptop|tablet|tent|stand|closed|unknown) posture="$OMANOME_POSTURE" ;;
esac
orientation_available=false
posture_available=false
[[ "$orientation" != unavailable ]] && orientation_available=true
[[ "$posture" != unavailable ]] && posture_available=true

jq -cn \
  --arg backend "$backend" \
  --argjson monitorSensorAvailable "$(bool_value "$monitor_sensor_available")" \
  --argjson dbusAvailable "$(bool_value "$dbus_available")" \
  --argjson accelerometerAvailable "$(bool_value "$accelerometer_available")" \
  --argjson autoRotationSupported "$(bool_value "$auto_rotation")" \
  --arg orientation "$orientation" \
  --arg posture "$posture" \
  --argjson orientationAvailable "$(bool_value "$orientation_available")" \
  --argjson postureAvailable "$(bool_value "$posture_available")" \
  '{monitorSensorAvailable:$monitorSensorAvailable,dbusAvailable:$dbusAvailable,accelerometerAvailable:$accelerometerAvailable,autoRotationSupported:$autoRotationSupported,selectedBackend:$backend,orientation:{available:$orientationAvailable,state:$orientation,source:(if $orientationAvailable then "runtime-environment" else "unavailable" end)},posture:{available:$postureAvailable,state:$posture,source:(if $postureAvailable then "runtime-environment" else "unavailable" end)}}'
