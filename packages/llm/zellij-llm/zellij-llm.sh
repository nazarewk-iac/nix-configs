#!/usr/bin/env nix-shell
#!nix-shell -i bash -p argc zellij jq
# These two lines let the script run standalone (./zellij-llm.sh spawn ...) without the nix
# package or a devenv shell on PATH. kdn-slug.sh uses the same pattern. The packaged version
# (default.nix) ignores them: writeShellApplication prepends its own shebang and runtimeInputs,
# so both lines become inert comments there. The `set -eEuo pipefail` below is a duplicate of
# writeShellApplication's own header for the same reason.
set -eEuo pipefail

# argc (https://github.com/sigoden/argc) does subcommand dispatch and --help. This is different
# from the hand-rolled `case` parse in other bash packages here (git-utils, kdn-gamingctl). This
# script has enough per-subcommand flags that argc's @option/@flag annotations aid discovery,
# and bash keeps a zero-build edit/test loop and fast startup.

# zellij's unix socket path is `$ZELLIJ_SOCKET_DIR/zellij-<uid>/<version>/<session-name>`.
# macOS caps a unix socket path at 103 bytes. The real per-user temp dir
# (getconf DARWIN_USER_TEMP_DIR) is long enough that any real session name overflows the cap.
# Default to a short, fixed socket dir unless the caller sets one. Do not rely on session-name
# length as the main defense (see .agents/skills/zellij/).
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
  # You cannot read the pane's exit status while zellij still holds the pane right after the
  # command ends (list-panes lags by a beat). A wrapper writes the code to a private temp file,
  # outside the pane's rendered text. This is a more robust exit signal than a scan of the
  # scrollback for a sentinel string.
  zellij --session "$argc_session" action new-pane --name "$argc_pane" "${cwd_args[@]}" \
    -- bash -c "$(_decode_and_run_cmd "$encoded"); rc=\$?; echo \"\$rc\" > '$marker'; exit \"\$rc\""
  _stack_with_existing "$argc_session"

  local pane_id
  pane_id="$(_pane_id_by_title "$argc_session" "$argc_pane")"

  case "$argc_mode" in
  stream)
    # `subscribe --format raw` redraws the WHOLE viewport on every update event, not a delta.
    # Confirmed live: a 3-line command emitted "line-1", then "line-1\nline-2", then
    # "line-1\nline-2\nline-3" as three separate events (duplication). `--format json`'s
    # "viewport" field has the same full-redraw shape, but as a real array. So this loop diffs
    # it against what it already printed and emits only the new tail lines.
    # subscribe also never stops on its own, even after the pane exits (verified). This loop
    # stops subscribe itself once done. A separate watcher process would race to kill it. An
    # earlier version killed subscribe the instant the exit marker appeared. For a fast command
    # that could kill subscribe before its last pane_update event arrived through the FIFO
    # (verified: a near-instant 3-line command sometimes produced no output). Instead `read -t`
    # polls the FIFO with a timeout. It stops only once the marker exists AND a read attempt
    # returned nothing. This gives any last in-flight event a chance to land first.
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
          # The viewport shrank (pane scrolled or cleared). Reprint it in full, do not drop
          # lines. This is rare for a short-lived command's output.
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
  # This exits 1 with "Session already exists" on stderr when the session is already present.
  # The docs call it "safe to call every time", but it is not a true no-op success (verified).
  # Tolerate exactly that message and surface anything else.
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

# zellij's `new-pane -- <cmd...>` runs only an argv command. It cannot attach this script's
# stdin to the spawned process (confirmed: `zellij action pipe` targets WASM plugins, not
# terminal panes). base64-encode stdin and decode it back inside the pane. This avoids a
# tempfile for the command, at the cost of an argv-length limit (macOS ARG_MAX is ~1MB, enough
# for shell scripts).
_stdin_to_b64() {
  base64 -w0
}

_decode_and_run_cmd() {
  printf 'echo %s | base64 -d | bash -xeEuo pipefail' "$1"
}

# new-pane --stacked fails without an error in a headless session with no attached client. It
# creates a pane that never appears in list-panes and returns empty on dump-screen (verified).
# Plain new-pane works headless. `action stack-panes` afterward folds it into the stack and
# reproduces the intended layout without that bug.
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
