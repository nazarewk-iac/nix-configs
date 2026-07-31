#!/usr/bin/env nix-shell
#!nix-shell -i bash -p argc zellij jq kdn-slug
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

# Do NOT set a private ZELLIJ_SOCKET_DIR here. The tool uses zellij's default socket location, so
# its sessions stay visible under the user's plain `zellij list-sessions`. A private socket dir
# would hide them. The 103-byte socket-path limit is handled by a short derived session name
# (see _socket_budget and _validate_socket_len). A test harness may still set ZELLIJ_SOCKET_DIR
# for isolation; the tool reads it but never sets a default.

# @describe Run and observe long commands in a dedicated background zellij session.
#
# The session name is derived from kdn-slug by default, so the common case is just
# `zellij-llm spawn --pane build`. Feed the command on stdin, ideally with a HEREDOC:
#
#   zellij-llm spawn --pane darwin-build <<'EOF'
#   nix run ".#darwin-rebuild" -- build
#   EOF
#
# Panes persist after the command exits so you can attach and review. Pass --ephemeral to close
# the pane on exit. Commands run under `bash -xeEuo pipefail`; the `-x` trace echoes each command
# into the pane, so a secret in a literal arg leaks into the scrollback (wrap such steps in
# `{ set +x; ...; set -x; } 2>/dev/null`).

# @cmd Create the session if missing and run a command from stdin in a new pane
# @option --session Session name; overrides the kdn-slug-derived default and is used verbatim
# @option --pane! Short kebab-case pane name/title (e.g. darwin-build)
# @option --cwd Working directory for the pane (defaults to zellij's own default)
# @flag --ephemeral Close the pane when its command exits (default: keep it open for review)
# @flag --wait Follow the pane until the command exits, then print EXIT:<code> (like spawn-and-watch)
# @option --mode[=stream|heartbeat] With --wait: stream forwards live output; heartbeat prints elapsed-time lines
# @option --interval=2 Heartbeat poll interval in seconds (--wait --mode heartbeat only)
# @option --sep Top-level name separator; forwarded to kdn-slug (default `:`)
# @option --repo-sep Repo-path separator; forwarded to kdn-slug (default `_`)
# @option --max-len Extra cap on the derived name length; never exceeds the socket budget
# @option --tag* Extra name components; forwarded to kdn-slug as repeatable --tag
spawn() {
  _run_spawn "${argc_wait:-0}"
}

# @cmd Like spawn --wait: run a command, then follow the pane until it exits
# @option --session Session name; overrides the kdn-slug-derived default and is used verbatim
# @option --pane! Short kebab-case pane name/title (e.g. darwin-build)
# @option --cwd Working directory for the pane
# @flag --ephemeral Close the pane when its command exits (default: keep it open for review)
# @option --mode![stream|heartbeat] stream: forward live pane output; heartbeat: print periodic elapsed-time lines only
# @option --interval=2 Heartbeat poll interval in seconds (--mode heartbeat only)
# @option --sep Top-level name separator; forwarded to kdn-slug (default `:`)
# @option --repo-sep Repo-path separator; forwarded to kdn-slug (default `_`)
# @option --max-len Extra cap on the derived name length; never exceeds the socket budget
# @option --tag* Extra name components; forwarded to kdn-slug as repeatable --tag
spawn-and-watch() {
  _run_spawn 1
}

# @cmd Follow an already-spawned pane until its command exits
# @option --session Session name; overrides the kdn-slug-derived default and is used verbatim
# @option --pane! Pane id (bare integer or terminal_<id>) or pane title/name to look up
# @option --mode[=stream|heartbeat] stream: forward live pane output; heartbeat: print periodic elapsed-time lines only
# @option --interval=2 Heartbeat poll interval in seconds (--mode heartbeat only)
# @option --sep Top-level name separator; forwarded to kdn-slug (default `:`)
# @option --repo-sep Repo-path separator; forwarded to kdn-slug (default `_`)
# @option --max-len Extra cap on the derived name length; never exceeds the socket budget
# @option --tag* Extra name components; forwarded to kdn-slug as repeatable --tag
watch() {
  local session pane_id
  session="$(_session_name)"
  pane_id="$(_resolve_pane_ref "$session" "$argc_pane")"
  if [[ -z "$pane_id" || "$pane_id" == null ]]; then
    echo "no pane '${argc_pane}' in session '${session}'" >&2
    return 1
  fi
  _watch_pane "$session" "$pane_id" "$argc_mode" "${argc_interval:-2}" ""
}

# @cmd Block until a pane's command exits; print EXIT:<code> and return that code (no streaming)
# @option --session Session name; overrides the kdn-slug-derived default and is used verbatim
# @option --pane! Pane id (bare integer or terminal_<id>) or pane title/name to look up
# @option --interval=1 Poll interval in seconds
# @option --sep Top-level name separator; forwarded to kdn-slug (default `:`)
# @option --repo-sep Repo-path separator; forwarded to kdn-slug (default `_`)
# @option --max-len Extra cap on the derived name length; never exceeds the socket budget
# @option --tag* Extra name components; forwarded to kdn-slug as repeatable --tag
wait() {
  local session pane_id
  session="$(_session_name)"
  pane_id="$(_resolve_pane_ref "$session" "$argc_pane")"
  if [[ -z "$pane_id" || "$pane_id" == null ]]; then
    echo "no pane '${argc_pane}' in session '${session}'" >&2
    return 1
  fi
  local rc=""
  while [[ -z "$rc" ]]; do
    rc="$(_pane_exit_status "$session" "$pane_id")"
    [[ -z "$rc" ]] && sleep "${argc_interval:-1}"
  done
  echo "EXIT:${rc}"
  exit "$rc"
}

# @cmd Dump the current content of a pane in this session (viewport or full scrollback)
# @option --session Session name; overrides the kdn-slug-derived default (must be your own session)
# @option --pane! Pane id (bare integer or terminal_<id>) or pane title/name to look up
# @flag --full Include full scrollback instead of just the viewport
# @option --sep Top-level name separator; forwarded to kdn-slug (default `:`)
# @option --repo-sep Repo-path separator; forwarded to kdn-slug (default `_`)
# @option --max-len Extra cap on the derived name length; never exceeds the socket budget
# @option --tag* Extra name components; forwarded to kdn-slug as repeatable --tag
peek() {
  local session pane_id
  session="$(_session_name)"
  pane_id="$(_resolve_pane_ref "$session" "$argc_pane")"
  local -a flags=()
  [[ "${argc_full:-0}" == 1 ]] && flags+=(-f)
  zellij --session "$session" action dump-screen -p "$pane_id" "${flags[@]}"
}

# @cmd List panes (id, title, exited, command) in this session
# @option --session Session name; overrides the kdn-slug-derived default (must be your own session)
# @option --sep Top-level name separator; forwarded to kdn-slug (default `:`)
# @option --repo-sep Repo-path separator; forwarded to kdn-slug (default `_`)
# @option --max-len Extra cap on the derived name length; never exceeds the socket budget
# @option --tag* Extra name components; forwarded to kdn-slug as repeatable --tag
list() {
  local session
  session="$(_session_name)"
  zellij --session "$session" action list-panes --json --all -s -c \
    | jq '[.[] | select(.is_plugin==false) | {id, title, exited, exit_status, terminal_command}]'
}

# Shared body for spawn and spawn-and-watch. $1 is 1 to follow the pane until exit, 0 to return.
_run_spawn() {
  local do_wait="$1"
  local session
  session="$(_session_name)"
  _validate_socket_len "$session"
  _check_slug "$argc_pane" "pane name"
  _ensure_session "$session"

  local encoded
  encoded="$(_stdin_to_b64)"
  local -a cwd_args=()
  [[ -n "${argc_cwd:-}" ]] && cwd_args=(--cwd "$argc_cwd")
  local -a life_args=()
  [[ "${argc_ephemeral:-0}" == 1 ]] && life_args=(--close-on-exit)

  if [[ "$do_wait" == 1 ]]; then
    # You cannot read the pane's exit status while zellij still holds the pane right after the
    # command ends (list-panes lags by a beat). A wrapper writes the code to a private temp file,
    # outside the pane's rendered text. This is a more robust exit signal than a scan of the
    # scrollback for a sentinel string.
    local marker
    marker="$(mktemp -u /tmp/zellij-llm-exit.XXXXXX)"
    zellij --session "$session" action new-pane --name "$argc_pane" "${cwd_args[@]}" "${life_args[@]}" \
      -- bash -c "$(_decode_and_run_cmd "$encoded"); rc=\$?; echo \"\$rc\" > '$marker'; exit \"\$rc\""
    _stack_with_existing "$session"
    local pane_id
    pane_id="$(_pane_id_by_title "$session" "$argc_pane")"
    _watch_pane "$session" "$pane_id" "$argc_mode" "${argc_interval:-2}" "$marker"
  else
    zellij --session "$session" action new-pane --name "$argc_pane" "${cwd_args[@]}" "${life_args[@]}" \
      -- bash -c "$(_decode_and_run_cmd "$encoded")"
    _stack_with_existing "$session"
    echo "spawned pane '${argc_pane}' in session '${session}'"
  fi
}

# Follow a pane until its command exits, then print EXIT:<code> and exit with that code.
# $5 (marker) is the exit-marker file when set (spawn --wait wraps the command with it). When
# empty, the loop polls list-panes for the pane's exited/exit_status fields instead.
_watch_pane() {
  local session="$1" pane_id="$2" mode="$3" interval="$4" marker="${5:-}"

  case "$mode" in
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
    # polls the FIFO with a timeout. It stops only once the pane is done AND a read attempt
    # returned nothing. This gives any last in-flight event a chance to land first.
    if [[ -z "$pane_id" || "$pane_id" == null ]]; then
      # An --ephemeral pane can close before we resolve its id. Fall back to a marker wait.
      while ! _pane_done "$marker" "$session" "$pane_id"; do sleep 0.3; done
    else
      local fifo
      fifo="$(mktemp -u /tmp/zellij-llm-stream.XXXXXX)"
      mkfifo "$fifo"
      zellij --session "$session" subscribe -p "$pane_id" --format json --scrollback >"$fifo" &
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
        elif _pane_done "$marker" "$session" "$pane_id"; then
          # command has finished AND this read attempt found nothing pending — safe to stop.
          break
        fi
      done

      exec 3<&-
      kill "$sub_pid" 2>/dev/null || true
      builtin wait "$sub_pid" 2>/dev/null || true
      rm -f "$fifo"
    fi
    ;;
  heartbeat)
    local start elapsed
    start="$(date +%s)"
    while ! _pane_done "$marker" "$session" "$pane_id"; do
      elapsed=$(($(date +%s) - start))
      echo "[$(date +%H:%M:%S)] still running (${elapsed}s elapsed): ${session} / ${pane_id}"
      sleep "$interval"
    done
    ;;
  esac

  local rc
  if [[ -n "$marker" ]]; then
    rc="$(cat "$marker")"
    rm -f "$marker"
  else
    rc="$(_pane_exit_status "$session" "$pane_id")"
    rc="${rc:-0}"
  fi
  echo "EXIT:${rc}"
  exit "$rc"
}

# True when the pane's command has finished. Uses the marker file when set, else list-panes.
_pane_done() {
  local marker="$1" session="$2" pane_id="$3"
  if [[ -n "$marker" ]]; then
    [[ -f "$marker" ]]
  else
    [[ -n "$(_pane_exit_status "$session" "$pane_id")" ]]
  fi
}

# Echo the pane's exit status when it has exited, else nothing. Reads list-panes, which exposes
# the exited/exit_status fields once the command ends.
_pane_exit_status() {
  local session="$1" pane_id="$2"
  zellij --session "$session" action list-panes --json --all \
    | jq -r --arg id "$pane_id" '
        [.[] | select(.is_plugin==false)
             | select((.id|tostring)==$id or ("terminal_"+(.id|tostring))==$id)]
        | .[-1] // {} | if .exited then (.exit_status // 0) else empty end'
}

# Resolve the session name. An explicit --session wins verbatim. Otherwise derive it from
# kdn-slug, capped to the socket budget so the IPC socket path fits (see _socket_budget).
_session_name() {
  if [[ -n "${argc_session:-}" ]]; then
    printf '%s' "$argc_session"
    return 0
  fi

  local budget cap
  budget="$(_socket_budget)"
  cap="$budget"
  if [[ -n "${argc_max_len:-}" && "$argc_max_len" -lt "$budget" ]]; then
    cap="$argc_max_len"
  fi

  local -a args=(names --type session --max-len "$cap")
  [[ -n "${argc_sep:-}" ]] && args+=(--sep "$argc_sep")
  [[ -n "${argc_repo_sep:-}" ]] && args+=(--repo-sep "$argc_repo_sep")
  local t
  for t in "${argc_tag[@]:-}"; do
    [[ -n "$t" ]] && args+=(--tag "$t")
  done
  kdn-slug "${args[@]}"
}

# The max session-name length that keeps the IPC socket path at or under 103 bytes. The full path
# is <socket-dir>/contract_version_1/<session>. macOS caps a unix socket path at 104 bytes; 103
# is the tighter cross-platform ceiling.
_socket_budget() {
  local dir suffix="/contract_version_1/" max=103 used budget
  dir="$(_socket_dir)"
  used=$((${#dir} + ${#suffix}))
  budget=$((max - used))
  ((budget < 1)) && budget=1
  printf '%s' "$budget"
}

# The socket directory that zellij uses. Matches zellij's own default (an explicit
# ZELLIJ_SOCKET_DIR wins; else Linux prefers the XDG runtime dir; else <temp>/zellij-<uid>).
# <temp> matches Rust's std::env::temp_dir, which zellij uses: $TMPDIR when set, else on macOS
# the confstr(_CS_DARWIN_USER_TEMP_DIR) value (the long /var/folders/.../T path, NOT /tmp),
# else /tmp. Getting <temp> right matters: an underestimate derives a too-long name that zellij
# then rejects. _validate_socket_len is still the real gate against the actual path.
_socket_dir() {
  if [[ -n "${ZELLIJ_SOCKET_DIR:-}" ]]; then
    printf '%s' "${ZELLIJ_SOCKET_DIR%/}"
    return 0
  fi
  if [[ "${OSTYPE:-}" != darwin* && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    printf '%s/zellij' "${XDG_RUNTIME_DIR%/}"
    return 0
  fi
  local tmp="${TMPDIR:-}"
  if [[ -z "$tmp" ]]; then
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      tmp="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
    fi
    tmp="${tmp:-/tmp}"
  fi
  printf '%s/zellij-%s' "${tmp%/}" "$(id -u)"
}

# Fail early with a clear message when the derived/passed session name overflows the socket path.
# Without this the failure surfaces deep in `spawn` as a cryptic zellij error.
_validate_socket_len() {
  local session="$1" dir path len max=103
  dir="$(_socket_dir)"
  path="${dir}/contract_version_1/${session}"
  len="${#path}"
  if [[ "$len" -gt "$max" ]]; then
    {
      echo "Error: the zellij IPC socket path is too long (${len} bytes, max ${max}):"
      echo "  ${path}"
      echo "The --session name does not fit. Use a shorter --session, add a lower --max-len,"
      echo "or pass fewer --tag components."
    } >&2
    return 1
  fi
}

# Warn (do not fail) when a pane name is not a short kebab-case slug. A long, sentence-like name
# reads poorly in list/peek output and in the pane title bar.
_check_slug() {
  local val="$1" what="$2"
  if [[ "${#val}" -gt 40 || "$val" == *" "* ]]; then
    echo "warning: ${what} '${val}' is not a short slug (e.g. darwin-build); it reads poorly in list/peek output" >&2
  fi
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
