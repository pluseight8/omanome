#!/usr/bin/env bash
# Print discovered Bluetooth devices as JSON; pairing remains a user action.
set -u

if ! command -v bluetoothctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

bluetoothctl --timeout 5 scan on >/dev/null 2>&1 || true

while IFS= read -r line; do
  mac="$(awk '{ print $2 }' <<<"$line")"
  name="$(cut -d' ' -f3- <<<"$line")"
  [[ "$mac" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || continue
  connected=false
  if bluetoothctl info "$mac" 2>/dev/null | grep -q '^\s*Connected: yes'; then
    connected=true
  fi
  printf '%s\t%s\t%s\n' "$mac" "$name" "$connected"
done < <(bluetoothctl devices 2>/dev/null) \
  | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map(select(length >= 2) | {
          address: .[0],
          name: (.[1] // .[0]),
          connected: (.[2] == "true")
        })
      | unique_by(.address)'
