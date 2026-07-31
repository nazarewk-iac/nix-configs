#!/usr/bin/env nix-shell
#!nix-shell -i bash -p argc jujutsu git
# These two lines let the script run standalone (./kdn-slug.sh ...) without the nix package or a
# devenv shell on PATH. zellij-llm.sh uses the same pattern. The packaged version (default.nix)
# ignores them: writeShellApplication prepends its own shebang and runtimeInputs, so both lines
# become inert comments there. The `set -eEuo pipefail` below is a duplicate of
# writeShellApplication's own header for the same reason.
set -eEuo pipefail

# argc (https://github.com/sigoden/argc) does subcommand dispatch and --help. Other bash
# packages here (git-utils, kdn-gamingctl) hand-roll a `case` parse. This script has several
# repeatable/optional flags per subcommand where argc's @option/@flag annotations stay more
# readable, and bash keeps a zero-build edit/test loop and fast startup.

# Built-in harness_name:env_var pairs, checked in order, first match wins. To extend without an
# edit to this file, append more pairs to KDN_SLUG_HARNESSES, e.g.
# KDN_SLUG_HARNESSES="my-harness:MY_HARNESS_SESSION_ID".
default_harnesses="claude-code:CLAUDE_CODE_SESSION_ID"
all_harnesses="${default_harnesses}${KDN_SLUG_HARNESSES:+,${KDN_SLUG_HARNESSES}}"

# @cmd Detect the current LLM/agent harness and its session id, if any
# @meta require-tools argc
harness() {
  local IFS=,
  for pair in $all_harnesses; do
    local name="${pair%%:*}" var="${pair#*:}"
    if [[ -n "${!var:-}" ]]; then
      echo "${name} ${!var}"
      return 0
    fi
  done
  echo "no harness detected (checked: ${all_harnesses})" >&2
  return 1
}

# @cmd Detect the current repository's host/org/name, most specific first
repo() {
  local root=""
  # Trust DEVENV_ROOT only when $PWD is inside it. devenv sets it once at shell entry and does
  # NOT track later `cd`s. A stale value from a different checkout (e.g. a sibling
  # `jj workspace add` dir) would point elsewhere without warning.
  if [[ -n "${DEVENV_ROOT:-}" && "$PWD/" == "${DEVENV_ROOT}/"* ]]; then
    root="$DEVENV_ROOT"
  elif root="$(jj root 2>/dev/null)"; then
    :
  elif root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    root="$PWD"
  fi

  local name host="" org=""
  name="$(basename "$root")"

  local remote_url=""
  # `jj git remote list` exits non-zero when $root has no .jj at all (a plain git repo). Under
  # `set -eEuo pipefail` that failure passes through the pipe to awk and kills the whole script.
  # So this must not be `cmd | awk ...` alone. The `|| true` on the jj call lets the git
  # fallback below run instead.
  remote_url="$(cd "$root" && { jj git remote list 2>/dev/null || true; } | awk 'NR==1{print $2}')"
  if [[ -z "$remote_url" ]]; then
    remote_url="$(cd "$root" && git remote get-url origin 2>/dev/null || true)"
  fi
  if [[ -n "$remote_url" ]]; then
    # git@host:org/repo.git or https://host/org/repo(.git)
    local rest="$remote_url"
    rest="${rest#*://}"
    rest="${rest#*@}"
    host="${rest%%[:/]*}"
    rest="${rest#*[:/]}"
    rest="${rest%.git}"
    org="${rest%/*}"
    if [[ "$org" == "$rest" ]]; then
      org=""
    fi
  fi

  echo "root=${root}"
  echo "name=${name}"
  echo "org=${org}"
  echo "host=${host}"
}

# available `--type` values for the `names` command; each maps to a component recipe below
type_choices="session,tab,pane"

# @cmd Print one name of the given --type; add --list to see every candidate tried
# @option --type![session|tab|pane] What the name is for (see list-types)
# @option --repo Override the detected repo name (skips discovery)
# @option --session-id Override the detected harness session id (skips discovery)
# @option --sep=: Top-level separator between components (llm / repo-slug / session-id / tags)
# @option --repo-sep=_ Secondary separator joining the repo path parts (host/org/repo); default is "_" because zellij rejects "/" in session names
# @option --max-len Pick the first candidate at-or-under this length (chars); falls back to a hard-truncated last candidate if none fit
# @option --tag* Extra trailing components, appended in the order given
# @flag --list Print every candidate considered (most detailed first), instead of picking one
names() {
  local sep="${argc_sep}"
  local repo_sep="${argc_repo_sep}"
  local tags=("${argc_tag[@]:-}")
  if [[ "${#tags[@]}" -eq 1 && -z "${tags[0]}" ]]; then
    tags=()
  fi

  local repo_name="" repo_org="" repo_host=""
  if [[ -n "${argc_repo:-}" ]]; then
    repo_name="$argc_repo"
  else
    local repo_info
    repo_info="$(repo)"
    repo_name="$(echo "$repo_info" | sed -n 's/^name=//p')"
    repo_org="$(echo "$repo_info" | sed -n 's/^org=//p')"
    repo_host="$(echo "$repo_info" | sed -n 's/^host=//p')"
  fi

  local session_id=""
  if [[ -n "${argc_session_id:-}" ]]; then
    session_id="$argc_session_id"
  else
    session_id="$(harness 2>/dev/null | awk '{print $2}' || true)"
  fi

  local -a candidates=()
  case "$argc_type" in
  session)
    # Repo path parts join on "$repo_sep" (default "_"), NOT a hardcoded "/". zellij session
    # names reject "/" (verified: "Session name cannot contain '/'."). A separate delimiter from
    # "$sep" keeps the full host/org/repo as one distinct slug inside the ":"-delimited name.
    local -a repo_forms=()
    [[ -n "$repo_host" && -n "$repo_org" ]] && repo_forms+=("${repo_host}${repo_sep}${repo_org}${repo_sep}${repo_name}")
    [[ -n "$repo_org" ]] && repo_forms+=("${repo_org}${repo_sep}${repo_name}")
    repo_forms+=("${repo_name}")

    local -a session_forms=()
    if [[ -n "$session_id" ]]; then
      session_forms+=("$session_id")
      [[ "${#session_id}" -gt 8 ]] && session_forms+=("${session_id:0:8}")
      [[ "${#session_id}" -gt 4 ]] && session_forms+=("${session_id:0:4}")
    fi

    local rf sf prefix="llm"
    [[ -z "$session_id" ]] && prefix=""
    for rf in "${repo_forms[@]}"; do
      if [[ "${#session_forms[@]}" -eq 0 ]]; then
        candidates+=("$(join_nonempty "$sep" "$prefix" "$rf" "${tags[@]}")")
      else
        for sf in "${session_forms[@]}"; do
          candidates+=("$(join_nonempty "$sep" "$prefix" "$rf" "$sf" "${tags[@]}")")
        done
      fi
    done
    ;;
  tab | pane)
    candidates+=("$(join_nonempty "$sep" "${tags[@]}")")
    ;;
  esac

  # Drop consecutive repeats. Component levels can collapse to the same string, e.g. when there
  # is no org/host to drop.
  local last="" c
  local -a printed=()
  for c in "${candidates[@]}"; do
    [[ "$c" == "$last" ]] && continue
    printed+=("$c")
    last="$c"
  done

  if [[ "${argc_list:-0}" == 1 ]]; then
    printf '%s\n' "${printed[@]}"
    return 0
  fi

  # Default: pick exactly one winner — the most detailed candidate that fits --max-len (or the
  # first/most-detailed one when no limit is given).
  if [[ -z "${argc_max_len:-}" ]]; then
    echo "${printed[0]}"
    return 0
  fi
  for c in "${printed[@]}"; do
    if [[ "${#c}" -le "$argc_max_len" ]]; then
      echo "$c"
      return 0
    fi
  done
  # Nothing fit. Hard-truncate the least detailed candidate so a caller with a strict length
  # limit (e.g. a Unix socket path budget) always gets a usable single line.
  echo "${last:0:$argc_max_len}"
}

# @cmd List the built-in `--type` values accepted by `names`
list-types() {
  local IFS=,
  for t in $type_choices; do
    echo "$t"
  done
}

join_nonempty() {
  local sep="$1"
  shift
  local out="" part
  for part in "$@"; do
    [[ -z "$part" ]] && continue
    out="${out:+${out}${sep}}${part}"
  done
  echo "$out"
}

eval "$(argc --argc-eval "$0" "$@")"
