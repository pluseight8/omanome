#!/usr/bin/env bash
# Emit one JSON clipboard entry without writing payloads to logs.
# Called by wl-paste --watch with a MIME type and payload on stdin.
set -o pipefail

mime="${1:-text}"
mime="${mime,,}"
if [[ "${CLIPBOARD_STATE:-}" == "sensitive" || "${CLIPBOARD_STATE:-}" == "private" ]]; then
  exit 0
fi

if [[ "$mime" == image/* ]]; then
  state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/omanome/clipboard-images"
  mkdir -p -- "$state_dir"
  temp_file="$(mktemp --tmpdir="$state_dir" omanome.XXXXXX)" || exit 0
  trap 'rm -f -- "$temp_file"' EXIT
  cat >"$temp_file"
  [[ -s "$temp_file" ]] || exit 0
  hash="$(sha256sum -- "$temp_file" | awk '{print $1}')"
  ext="${mime#image/}"
  [[ "$ext" == jpeg ]] && ext=jpg
  final_file="$state_dir/$hash.$ext"
  if [[ ! -e "$final_file" ]]; then
    mv -- "$temp_file" "$final_file"
  fi
  jq -cn --arg mime "$mime" --arg path "$final_file" --arg captured_at "$(date --iso-8601=seconds)" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
  exit 0
fi

# Password-manager MIME hints are deliberately not persisted. wl-paste passes
# the selected type as argv; callers may also set CLIPBOARD_STATE=sensitive.
if [[ "$mime" == *password* || "$mime" == *secret* || "$mime" == *credential* || "$mime" == *token* || "$mime" == *private-key* || "$mime" == *private_key* ]]; then
  exit 0
fi

python3 -c 'import json,sys; value=sys.stdin.read(); value=value.rstrip("\n"); print(json.dumps({"type":"text","text":value,"capturedAt":""}, ensure_ascii=False))' \
  || true
