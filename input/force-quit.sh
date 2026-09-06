#!/usr/bin/env bash
set -Eeuo pipefail

# This helper accepts only a numeric PID selected from a real foreign-toplevel
# object. It never searches by app name and never kills a process group.
action="${1:-}"
pid="${2:-}"
timeout_ms="${3:-0}"

[[ "$pid" =~ ^[1-9][0-9]*$ ]] || { printf '%s\n' '{"ok":false,"reason":"invalid-pid"}'; exit 2; }
[[ "$action" == "term" || "$action" == "kill" ]] || { printf '%s\n' '{"ok":false,"reason":"invalid-action"}'; exit 2; }

proc_dir="/proc/$pid"
[[ -d "$proc_dir" ]] || { printf '{"ok":true,"pid":%s,"alive":false,"reason":"already-exited"}\n' "$pid"; exit 0; }

comm="$(<"$proc_dir/comm")"
cmdline="$(tr '\0' ' ' <"$proc_dir/cmdline" 2>/dev/null || true)"
lower="${comm,,} ${cmdline,,}"
if [[ "$lower" == *hyprland* || "$lower" == *omarchy-shell* || "$lower" == *omanome* || "$lower" == *quickshell* || "$lower" == *systemd* ]]; then
  printf '{"ok":false,"pid":%s,"protected":true,"reason":"protected-session-process"}\n' "$pid"
  exit 3
fi

if [[ "$action" == "term" ]]; then
  [[ "$timeout_ms" =~ ^[0-9]+$ ]] || timeout_ms=0
  kill -TERM -- "$pid" 2>/dev/null || true
  deadline=$(( $(date +%s%3N) + timeout_ms ))
  while kill -0 -- "$pid" 2>/dev/null; do
    now="$(date +%s%3N)"
    (( now >= deadline )) && break
    sleep 0.05
  done
  if kill -0 -- "$pid" 2>/dev/null; then
    printf '{"ok":true,"pid":%s,"alive":true,"signal":"TERM"}\n' "$pid"
  else
    printf '{"ok":true,"pid":%s,"alive":false,"signal":"TERM"}\n' "$pid"
  fi
  exit 0
fi

kill -KILL -- "$pid" 2>/dev/null || true
if kill -0 -- "$pid" 2>/dev/null; then
  printf '{"ok":false,"pid":%s,"alive":true,"signal":"KILL","reason":"signal-rejected"}\n' "$pid"
  exit 4
fi
printf '{"ok":true,"pid":%s,"alive":false,"signal":"KILL"}\n' "$pid"
