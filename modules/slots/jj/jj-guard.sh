#!/usr/bin/env bash
# PreToolUse hook: block raw `git` Bash commands in this jj-managed repo, except `git push*`
# and read-only git. Not a shell parser — best-effort word-boundary matching on each
# `&&`/`||`/`;`/`|`-separated segment. See the jujutsu-vcs skill/rule: this hook is not the sole
# safeguard (it can't intercept Claude Code's built-in /commit slash command, for example).
set -eEuo pipefail

deny() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
  exit 1
}

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"

[[ -z "$command" ]] && exit 0
[[ -d .jj ]] || exit 0

ALLOWED_READONLY="log diff show status remote rev-parse ls-files"

# split on &&, ||, ;, | into segments (best-effort, not a full shell parser)
segments="$(printf '%s' "$command" | tr '&|;' '\n')"

while IFS= read -r segment; do
  # shellcheck disable=SC2206
  words=($segment)
  ((${#words[@]} == 0)) && continue
  [[ "${words[0]}" != "git" ]] && continue

  subcommand="${words[1]:-}"

  case "$subcommand" in
  push*) continue ;;
  esac

  for allowed in $ALLOWED_READONLY; do
    [[ "$subcommand" == "$allowed" ]] && continue 2
  done

  deny "BLOCKED: this is a jj-managed repo. Use jj instead of raw git '$subcommand'.

Equivalents:
  git status          -> jj status
  git log              -> jj log
  git diff / show      -> jj diff / jj show
  git add + commit     -> jj split -m 'msg' -- <files>  (no staging area; content auto-snapshots)
  git commit --amend   -> edit @ or the target commit directly, then jj squash
  git checkout <rev>   -> jj new <rev> / jj edit <rev>
  git reset --hard     -> jj new <rev>  (old work recoverable via jj undo / jj op log)
  git rebase           -> jj rebase
  git merge            -> jj new <a> <b>
  git stash            -> not needed; leave changes in @ or jj split them off
  git fetch            -> jj git fetch
  git cherry-pick      -> jj duplicate <rev>
  git branch/tag -f/-d -> jj bookmark set/delete <name>

Allowed without jj: 'git push*' and read-only git ($ALLOWED_READONLY).
See the jujutsu-vcs skill/rule, or the jj-expert subagent for deep troubleshooting."
done <<<"$segments"

exit 0
