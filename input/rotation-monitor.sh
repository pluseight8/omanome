#!/usr/bin/env bash
# Stream orientation changes from an event-driven sensor backend.
# Prefer monitor-sensor for compatibility, then use iio-sensor-proxy's D-Bus
# API directly. Both branches keep one long-lived process; no polling loop is
# used and no subprocess is started for each orientation event.
set -u

if command -v monitor-sensor >/dev/null 2>&1; then
  exec monitor-sensor --accel
fi

command -v gdbus >/dev/null 2>&1 || exit 127
gdbus introspect --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy >/dev/null 2>&1 || exit 127
gdbus call --system --dest net.hadess.SensorProxy \
  --object-path /net/hadess/SensorProxy \
  --method net.hadess.SensorProxy.ClaimAccelerometer >/dev/null 2>&1 || exit 127

release_accelerometer() {
  gdbus call --system --dest net.hadess.SensorProxy \
    --object-path /net/hadess/SensorProxy \
    --method net.hadess.SensorProxy.ReleaseAccelerometer >/dev/null 2>&1 || true
}
trap release_accelerometer EXIT INT TERM

emit_orientation() {
  local line="$1"
  if [[ "$line" =~ (normal|left-up|right-up|bottom-up) ]]; then
    printf '%s\n' "\${BASH_REMATCH[1]}"
  fi
}

initial="$(gdbus call --system --dest net.hadess.SensorProxy \
  --object-path /net/hadess/SensorProxy \
  --method org.freedesktop.DBus.Properties.Get \
  net.hadess.SensorProxy AccelerometerOrientation 2>/dev/null || true)"
emit_orientation "$initial"

gdbus monitor --system \
  --dest net.hadess.SensorProxy \
  --object-path /net/hadess/SensorProxy | while IFS= read -r line; do
  emit_orientation "$line"
done
