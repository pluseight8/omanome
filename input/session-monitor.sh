#!/usr/bin/env bash
set -Eeuo pipefail

# Event-driven session lifecycle observer. It never polls and never forwards
# usernames, window titles, clipboard data, or other session payloads.
if ! command -v dbus-monitor >/dev/null 2>&1; then
  exit 127
fi

dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null |
while IFS= read -r line; do
  case "${line,,}" in
    *"boolean true"*) printf '%s\n' '{"type":"session.event","event":"suspend"}' ;;
    *"boolean false"*) printf '%s\n' '{"type":"session.event","event":"resume"}' ;;
  esac
done
