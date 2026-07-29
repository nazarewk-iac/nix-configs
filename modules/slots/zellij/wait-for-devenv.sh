#!/usr/bin/env bash
# PreToolUse hook: if running inside a zellij pane with an active devenv shell, delay execution
# while devenv's own status line (rendered as the pane's last row — see devenv-shell's
# status_line.rs) shows "devenv building". Any other status (ready, failed, reloaded, watching,
# paused) or no recognizable devenv status line at all passes through instantly, no delay.
#
# Rationale: after editing devenv.nix/modules/*, devenv rebuilds and reloads the shell env in the
# background; a Bash tool call that races that reload can run against a half-applied environment.
#
# NOTE: hook stdout isn't shown live to the user (only after the hook exits, via the JSON output
# below), and devenv's own claude.code.hooks.<name> Nix abstraction has no `statusMessage` field
# (Claude Code's hook schema supports one — a live spinner label — but devenv's hookSubmodule
# doesn't expose it as of this writing; see modules/slots/zellij/README.md's "Future work"). So
# this can't show a live "waiting for devenv..." spinner today — instead it reports what it
# waited for and for how long via `additionalContext` once done, so at least that shows up in the
# transcript/model context after the fact.
set -eEuo pipefail

# Only applies inside a zellij pane with devenv active; anything else is an instant no-op.
[[ -n "${ZELLIJ_PANE_ID:-}" ]] || exit 0
[[ -n "${DEVENV_ROOT:-}" ]] || exit 0
command -v zellij >/dev/null 2>&1 || exit 0

readonly POLL_INTERVAL="0.5"
readonly MAX_ITERATIONS=120 # ~60s cap, so a stuck/slow build can't hang a tool call forever

last_line() {
  zellij action dump-screen -p "$ZELLIJ_PANE_ID" 2>/dev/null | tail -n 1
}

allow() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "additionalContext": $reason
    }
  }'
  exit 0
}

line="$(last_line)"
[[ "$line" == *"devenv building"* ]] || exit 0

i=0
while [[ "$line" == *"devenv building"* && "$i" -lt "$MAX_ITERATIONS" ]]; do
  sleep "$POLL_INTERVAL"
  line="$(last_line)"
  i=$((i + 1))
done

waited_seconds="$(awk -v n="$i" -v s="$POLL_INTERVAL" 'BEGIN { printf "%.1f", n * s }')"
if [[ "$line" == *"devenv building"* ]]; then
  allow "Waited ${waited_seconds}s for devenv rebuild in pane $ZELLIJ_PANE_ID, but it was still building when the wait cap was hit — proceeding anyway. Last status line: $line"
else
  allow "Waited ${waited_seconds}s for devenv rebuild in pane $ZELLIJ_PANE_ID to finish before running this command. Status line is now: $line"
fi
