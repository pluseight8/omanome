#!/usr/bin/env bash
# Stream orientation changes from the optional iio-sensor-proxy client.
# The absence of monitor-sensor is a supported capability result.
set -u

if ! command -v monitor-sensor >/dev/null 2>&1; then
  exit 127
fi

exec monitor-sensor --accel
