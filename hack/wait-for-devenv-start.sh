#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|MultiEdit|Write, or similar file-modifying tools): after a file
# write, briefly poll (up to ~1s) for devenv's status line to flip to "devenv building" — closing
# the gap where devenv's file watcher hasn't noticed the change yet. Does NOT wait for the
# rebuild to finish; that's zellij-wait-for-devenv's (PreToolUse) job. Always proceeds afterward,
# whether or not "building" ever appeared — a change that doesn't trigger a rebuild (e.g. a file
# outside `files.` watch, or one whose content hash didn't change) is not an error here.
#
# Rationale: without this, a fast-firing Bash tool call right after Write/Edit can slip in during
# the window before devenv's watcher has even started building, so the PreToolUse hook sees
# "devenv ready" (stale) and doesn't wait at all — even though a rebuild is about to start.
set -eEuo pipefail

[[ -n "${ZELLIJ_PANE_ID:-}" ]] || exit 0
[[ -n "${DEVENV_ROOT:-}" ]] || exit 0
command -v zellij >/dev/null 2>&1 || exit 0

readonly POLL_INTERVAL="0.1"
readonly MAX_ITERATIONS=10 # ~1s cap

last_line() {
  zellij action dump-screen -p "$ZELLIJ_PANE_ID" 2>/dev/null | tail -n 1
}

report() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $reason
    }
  }'
  exit 0
}

i=0
line="$(last_line)"
while [[ "$line" != *"devenv building"* && "$i" -lt "$MAX_ITERATIONS" ]]; do
  sleep "$POLL_INTERVAL"
  line="$(last_line)"
  i=$((i + 1))
done

waited_seconds="$(awk -v n="$i" -v s="$POLL_INTERVAL" 'BEGIN { printf "%.1f", n * s }')"
if [[ "$line" == *"devenv building"* ]]; then
  report "devenv started rebuilding after ${waited_seconds}s in pane $ZELLIJ_PANE_ID (a subsequent Bash call will wait for it to finish). Status line: $line"
else
  exit 0
fi
