#!/usr/bin/env bash
# Reject fork-specific content on an upstream-side change.
#
# It skips when:
#   - the directory is not a jj repo
#   - `@` has no description (an unnamed working copy scratch change)
#   - `@` is already in `fork-chain` (fork side, where the content belongs)
#
# SENSITIVE_FILE_PATTERNS and SENSITIVE_MESSAGE_PATTERNS are baked in via runtimeEnv.
#
# KNOWN LIMIT — `jj commit` fires no `.git/hooks/pre-commit` (measured), so this hook runs on a
# raw `git commit` only, which the repo mandate forbids. Treat it as a net for the rare direct
# git path. The real gates are `jj fork-audit` (content) and the pre-push hook (push path).
#
# It reads jj's own view of `@`, not `git diff --cached`. jj stages nothing, so the git index is
# empty in normal use and an index-based check sees no content at all.

set -eEuo pipefail

jj root &>/dev/null || exit 0

change_id="$(jj log -r @ --no-graph -T 'change_id' 2>/dev/null)"
description="$(jj log -r @ --no-graph -T 'description' 2>/dev/null)"

[ -n "$description" ] || exit 0

# Skip when `@` already belongs to the fork chain.
if [ -n "$(jj log -r "fork-chain & ${change_id}" --no-graph -T '"x"' 2>/dev/null)" ]; then
  exit 0
fi

# Read each whole pattern as one array element (newline-delimited), so a pattern that contains a
# space stays intact.
file_patterns=()
[ -n "$SENSITIVE_FILE_PATTERNS" ] && mapfile -t file_patterns <<< "$SENSITIVE_FILE_PATTERNS"
diff_patterns=()
[ -n "$SENSITIVE_MESSAGE_PATTERNS" ] && mapfile -t diff_patterns <<< "$SENSITIVE_MESSAGE_PATTERNS"
if [ -n "$SENSITIVE_FILE_PATTERNS" ]; then
  mapfile -t _fp <<< "$SENSITIVE_FILE_PATTERNS"
  diff_patterns+=("${_fp[@]}")
fi

# An empty list builds a grep with no `-e`, which passes in silence. The patterns come from the
# git-ignored `devenv.slots.local.nix`, so a missing local file would disable this check with no
# warning. Fail loudly instead.
if [ "${#file_patterns[@]}" -eq 0 ] || [ "${#diff_patterns[@]}" -eq 0 ]; then
  cat >&2 <<'MSG'
ERROR: the sensitive-pattern lists are empty, so this check cannot protect anything.
  Restore `devenv.slots.local.nix` and re-enter the devenv shell.
  Set KDN_JJ_PRE_PUSH_ALLOW_EMPTY=1 to commit anyway.
MSG
  [ "${KDN_JJ_PRE_PUSH_ALLOW_EMPTY:-}" = 1 ] || exit 1
fi

# Never pass `-q`: grep closes the pipe on the first match, the writer takes SIGPIPE, and
# `pipefail` turns the pipeline into a failure — so a match reads as "no match". Redirect to
# /dev/null instead, which keeps grep reading to the end.
file_grep_args=(-i)
for p in "${file_patterns[@]}"; do file_grep_args+=('-e' "$p"); done
diff_grep_args=(-i)
for p in "${diff_patterns[@]}"; do diff_grep_args+=('-e' "$p"); done

failed=0

# Report the matched path or line, never the pattern. A pattern is private configuration.
if jj diff -r @ --name-only | grep "${file_grep_args[@]}" >/dev/null; then
  echo "ERROR: a file path in @ matches a fork-sensitive pattern:" >&2
  jj diff -r @ --name-only | grep "${file_grep_args[@]}" | sed 's/^/  /' >&2 || true
  echo "  @ looks like an upstream-side change. Move the content to a fork-side commit." >&2
  failed=1
fi

if jj diff -r @ --git | grep -I "${diff_grep_args[@]}" >/dev/null; then
  echo "ERROR: a diff line in @ matches a fork-sensitive pattern:" >&2
  jj diff -r @ --git | grep -I -n "${diff_grep_args[@]}" | head -5 | sed 's/^/  /' >&2 || true
  echo "  @ looks like an upstream-side change. Move the content to a fork-side commit." >&2
  failed=1
fi

exit "$failed"
