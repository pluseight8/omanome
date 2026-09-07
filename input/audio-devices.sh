#!/usr/bin/env bash
# Print PipeWire/WirePlumber sinks and sources as JSON for device selection.
set -u

if ! command -v wpctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf '[]\n'
  exit 0
fi

wpctl status 2>/dev/null \
  | awk '
      /^Audio/ { area="audio"; next }
      /^Video/ { area=""; section=""; next }
      /^[[:space:]]*[├└]─ Sinks/ { if (area == "audio") section="sink"; next }
      /^[[:space:]]*[├└]─ Sources/ { if (area == "audio") section="source"; next }
      /^[[:space:]]*[├└]─ (Filters|Streams)/ { section=""; next }
      area == "audio" && section != "" && $0 ~ /^[[:space:]│]*\*?[[:space:]]*[0-9]+\.[[:space:]]/ {
        line = $0
        active = (line ~ /\*/)
        sub(/^[[:space:]│]*\*[[:space:]]*/, "", line)
        sub(/^[[:space:]│]*/, "", line)
        split(line, fields, /\.[[:space:]]+/)
        id = fields[1]
        name = fields[2]
        sub(/[[:space:]]+\[vol:.*$/, "", name)
        sub(/[[:space:]]+$/, "", name)
        if (id ~ /^[0-9]+$/ && name != "") print section "\t" id "\t" name "\t" (active ? "true" : "false")
      }' \
  | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({kind: .[0], id: (.[1] | tonumber), name: .[2], active: (.[3] == "true")})'
