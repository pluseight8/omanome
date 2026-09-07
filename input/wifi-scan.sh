#!/usr/bin/env bash
# Print nearby Wi-Fi networks as a small JSON array without exposing secrets.
set -u

if ! command -v nmcli >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

nmcli -t --escape no --separator $'\t' \
  -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null \
  | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map(select(length >= 2) | {
          active: (.[0] == "*"),
          ssid: .[1],
          signal: ((.[2] // "") | tonumber? // -1),
          security: (.[3] // "")
        })
      | map(select(.ssid != ""))
      | unique_by(.ssid)
      | .[:32]'
