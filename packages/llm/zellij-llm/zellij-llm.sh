#!/usr/bin/env nix-shell
#!nix-shell -i bash -p argc zellij jq
# Lets this script run standalone (./zellij-llm.sh spawn ...) without the nix package or a
# devenv shell on PATH — see packages/kdn-slug/kdn-slug.sh for the same pattern. The packaged
# version (packages/zellij-llm/default.nix) ignores these two lines: writeShellApplication
# wraps this file's contents in its own generated script with its own shebang/runtimeInputs
# ahead of them, so they end up as inert comments there, same as `set -eEuo pipefail` below
# duplicating writeShellApplication's own `set -euo pipefail` header.
set -eEuo pipefail

# Uses argc (https://github.com/sigoden/argc) for subcommand dispatch and --help generation
# instead of hand-rolled `case`-based parsing (the pattern this repo's other bash packages
# use, e.g. git-utils, kdn-gamingctl) — this script has enough per-subcommand flags that
# argc's declarative @option/@flag annotations pay for themselves in discoverability,
# without giving up bash's zero-build edit/test loop or near-instant startup latency.

# zellij's unix socket path is `$ZELLIJ_SOCKET_DIR/zellij-<uid>/<version>/<session-name>` —
# macOS caps unix socket paths at 103 bytes, and the real per-user temp dir
# (getconf DARWIN_USER_TEMP_DIR) is long enough that any non-trivial session name overflows
# it. Default to a short, fixed socket dir unless the caller already set one, rather than
# relying on session-name length limits as the primary defense (see .agents/skills/zellij/).
export ZELLIJ_SOCKET_DIR="${ZELLIJ_SOCKET_DIR:-/tmp/zellij}"
mkdir -p "$ZELLIJ_SOCKET_DIR"

# @cmd Create the session if missing and run a command from stdin in a new pane; returns immediately
# @option --session! Session name (see the zellij skill's `llm:<repo-slug>:<llm-session-id>[:tag...]` convention)
# @option --pane! Pane name/title
# @option --cwd Working directory for the pane (defaults to zellij's own default)
spawn() {
  _ensure_session "$argc_session"
  local encoded
  encoded="$(_stdin_to_b64)"
  local -a cwd_args=()
  [[ -n "${argc_cwd:-}" ]] && cwd_args=(--cwd "$argc_cwd")
  zellij --session "$argc_session" action new-pane --name "$argc_pane" "${cwd_args[@]}" \
    -- bash -c "$(_decode_and_run_cmd "$encoded")"
  _stack_with_existing "$argc_session"
  echo "spawned pane '${argc_pane}' in session '${argc_session}'"
}

# @cmd Like spawn, then follow the pane until the command exits
# @option --session! Session name
# @option --pane! Pane name/title
# @option --cwd Working directory for the pane
# @option --mode![stream|heartbeat] stream: forward live pane output; heartbeat: print periodic elapsed-time status lines only
# @option --interval=2 Heartbeat poll interval in seconds (--mode heartbeat only)
spawn-and-watch() {
  _ensure_session "$argc_session"
  local encoded marker
  encoded="$(_stdin_to_b64)"
  marker="$(mktemp -u /tmp/zellij-llm-exit.XXXXXX)"
  local -a cwd_args=()
  [[ -n "${argc_cwd:-}" ]] && cwd_args=(--cwd "$argc_cwd")
  # The pane's own exit status isn't reliably queryable while zellij still has it "held"
  # right after the command finishes (list-panes lags by a beat in practice) — a wrapper
  # that writes the code to a private temp file, outside the pane's rendered text, is a
  # more robust exit signal than scanning scrollback for a sentinel string.
  zellij --session "$argc_session" action new-pane --name "$argc_pane" "${cwd_args[@]}" \
    -- bash -c "$(_decode_and_run_cmd "$encoded"); rc=\$?; echo \"\$rc\" > '$marker'; exit \"\$rc\""
  _stack_with_existing "$argc_session"

  local pane_id
  pane_id="$(_pane_id_by_title "$argc_session" "$argc_pane")"

  case "$argc_mode" in
  stream)
    # `subscribe --format raw` redraws the ENTIRE viewport on every single update event (not
    # a delta) — confirmed live: a 3-line command produced "line-1", then "line-1\nline-2",
    # then "line-1\nline-2\nline-3" as three separate emissions, i.e. classic duplication.
    # `--format json`'s "viewport" field has the same full-redraw shape, but as a real array
    # we can diff against what's already been printed and emit only the new tail lines.
    # subscribe also never terminates on its own, even once the pane has exited (verified
    # empirically) — this loop stops it itself once done, rather than a separate watcher
    # process racing to kill it: an earlier version killed subscribe the instant the exit
    # marker appeared, which for fast-finishing commands could kill it before its final
    # pane_update event was even delivered through the FIFO (confirmed empirically — a
    # near-instant 3-line command sometimes produced zero output). Instead, `read -t` polls
    # the FIFO with a timeout and only stops once the marker exists AND a read attempt has
    # come up empty (i.e. no event was pending when we checked), giving any last in-flight
    # event a chance to land first.
    local fifo
    fifo="$(mktemp -u /tmp/zellij-llm-stream.XXXXXX)"
    mkfifo "$fifo"
    zellij --session "$argc_session" subscribe -p "$pane_id" --format json --scrollback >"$fifo" &
    local sub_pid=$!
    exec 3<"$fifo"

    local -a printed=()
    local json_line
    while true; do
      if IFS= read -r -t 0.3 json_line <&3; then
        local -a vp
        mapfile -t vp < <(printf '%s' "$json_line" | jq -r '.viewport[]?')
        local n="${#printed[@]}" total="${#vp[@]}" i
        if [[ "$total" -ge "$n" ]]; then
          for ((i = n; i < total; i++)); do
            printf '%s\n' "${vp[i]}"
          done
        else
          # viewport shrank (pane scrolled/cleared) — reprint fully rather than silently
          # drop lines; rare in practice for a short-lived command's output.
          printf '%s\n' "${vp[@]}"
        fi
        printed=("${vp[@]}")
      elif [[ -f "$marker" ]]; then
        # command has finished AND this read attempt found nothing pending — safe to stop.
        break
      fi
    done

    exec 3<&-
    kill "$sub_pid" 2>/dev/null || true
    wait "$sub_pid" 2>/dev/null || true
    rm -f "$fifo"
    ;;
  heartbeat)
    local start elapsed
    start="$(date +%s)"
    while [[ ! -f "$marker" ]]; do
      elapsed=$(($(date +%s) - start))
      echo "[$(date +%H:%M:%S)] still running (${elapsed}s elapsed): ${argc_session} / ${argc_pane}"
      sleep "$argc_interval"
    done
    ;;
  esac

  local rc
  rc="$(cat "$marker")"
  rm -f "$marker"
  echo "EXIT:${rc}"
  exit "$rc"
}

# @cmd Dump the current content of a pane in this session (viewport or full scrollback)
# @option --session! Session name (must be your own agent session, never the user's)
# @option --pane! Pane id (bare integer or terminal_<id>) or pane title/name to look up
# @flag --full Include full scrollback instead of just the viewport
peek() {
  local pane_id
  pane_id="$(_resolve_pane_ref "$argc_session" "$argc_pane")"
  local -a flags=()
  [[ "${argc_full:-0}" == 1 ]] && flags+=(-f)
  zellij --session "$argc_session" action dump-screen -p "$pane_id" "${flags[@]}"
}

# @cmd List panes (id, title, exited, command) in this session
# @option --session! Session name (must be your own agent session, never the user's)
list() {
  zellij --session "$argc_session" action list-panes --json --all -s -c \
    | jq '[.[] | select(.is_plugin==false) | {id, title, exited, exit_status, terminal_command}]'
}

_ensure_session() {
  # exits 1 with "Session already exists" on stderr when it's a no-op, rather than the
  # documented "safe to call every time" being a true no-op success (verified empirically) —
  # tolerate exactly that message and surface anything else.
  local out
  if out="$(zellij attach --create-background "$1" 2>&1)"; then
    return 0
  fi
  if [[ "$out" == "Session already exists" ]]; then
    return 0
  fi
  echo "$out" >&2
  return 1
}

# zellij's `new-pane -- <cmd...>` only ever runs an argv command, with no way to attach
# this script's stdin to the spawned process (confirmed: `zellij action pipe` only targets
# WASM plugins, not terminal panes) — base64-encoding stdin and decoding it back inside the
# pane avoids writing the command to a tempfile at all, at the cost of an argv-length limit
# (macOS ARG_MAX is ~1MB, comfortably enough for shell scripts).
_stdin_to_b64() {
  base64 -w0
}

_decode_and_run_cmd() {
  printf 'echo %s | base64 -d | bash -xeEuo pipefail' "$1"
}

# new-pane --stacked silently fails in a headless session with no attached client (creates
# a pane that never shows up in list-panes and returns empty on dump-screen — confirmed
# empirically). Plain new-pane works headless; folding it into the existing stack via
# `action stack-panes` afterward reproduces the intended stacked layout without that bug.
_stack_with_existing() {
  local session="$1"
  local -a ids
  mapfile -t ids < <(zellij --session "$session" action list-panes --json --all \
    | jq -r '[.[] | select(.is_plugin==false)] | .[].id')
  if [[ "${#ids[@]}" -gt 1 ]]; then
    zellij --session "$session" action stack-panes -- "${ids[@]}" >/dev/null
  fi
}

_pane_id_by_title() {
  local session="$1" title="$2"
  zellij --session "$session" action list-panes --json --all \
    | jq -r --arg t "$title" '[.[] | select(.is_plugin==false and .title==$t)] | .[-1].id'
}

_resolve_pane_ref() {
  local session="$1" ref="$2"
  if [[ "$ref" =~ ^[0-9]+$ || "$ref" == terminal_* ]]; then
    echo "$ref"
    return 0
  fi
  _pane_id_by_title "$session" "$ref"
}

eval "$(argc --argc-eval "$0" "$@")"
