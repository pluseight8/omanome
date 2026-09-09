#!/usr/bin/env bash
# Event-driven UPower boundary.  A signal causes one bounded snapshot refresh
# in the service; this process never polls UPower or emits object paths.
set -Eeuo pipefail

command -v gdbus >/dev/null 2>&1 || exit 127

gdbus monitor --system --dest org.freedesktop.UPower 2>/dev/null | awk '
  /PropertiesChanged|DeviceAdded|DeviceRemoved|DeviceChanged/ {
    print "{\"schemaVersion\":1,\"type\":\"power.event\",\"source\":\"upower\",\"category\":\"battery\",\"action\":\"change\"}"
    fflush()
  }
'
