#!/usr/bin/env bash
set -eEuo pipefail

# PRIVATE_REMOTE, SENSITIVE_FILE_PATTERNS, SENSITIVE_MESSAGE_PATTERNS,
# BLOCK_PUSH_MESSAGE_PATTERNS are baked in via runtimeEnv as newline-separated strings.
#
# The guard direction: private content must NOT reach a public remote. So the sensitive-content
# checks run on every remote EXCEPT the private fork remote. The always-blocked message check
# runs on every remote.
#
# KNOWN LIMIT — jj never fires this hook. `jj git push` runs no `.git/hooks/pre-push`
# (measured). The hook runs only on a real `git push`, which `jj sync-upstream` does use for the
# public push. Treat the hook as one net, not the gate. `jj fork-audit` is the content gate.
#
# KNOWN LIMIT — prek hands a pre-push hook no stdin (measured: argc=0, empty stdin). With no
# ref lines the hook cannot know what is pushed. See the no-stdin block near the end: it fails
# closed for a public remote and passes for the private one.

# The remote name. git passes it as $1. The pre-commit framework does not forward git's argv,
# so fall back to its own variables.
#   Do NOT read PRE_COMMIT_REMOTE_BRANCH here: it holds a ref name such as `refs/heads/main`,
#   so `${VAR%%/*}` returns the literal string `refs`, never a remote name (measured).
push_remote="${1:-${PRE_COMMIT_REMOTE_NAME:-}}"
if [ -z "$push_remote" ] && [ -n "${PRE_COMMIT_REMOTE_URL:-}" ]; then
  # Last resort: match the URL back to a remote name.
  while read -r name url _; do
    if [ "$url" = "$PRE_COMMIT_REMOTE_URL" ]; then
      push_remote="$name"
      break
    fi
  done < <(git remote -v)
fi

ZERO_SHA="0000000000000000000000000000000000000000"

# Read each whole pattern as one array element (newline-delimited), so a pattern
# that contains a space stays intact.
file_patterns=()
[ -n "$SENSITIVE_FILE_PATTERNS" ] && mapfile -t file_patterns <<< "$SENSITIVE_FILE_PATTERNS"
message_patterns=()
[ -n "$SENSITIVE_MESSAGE_PATTERNS" ] && mapfile -t message_patterns <<< "$SENSITIVE_MESSAGE_PATTERNS"
block_patterns=()
[ -n "$BLOCK_PUSH_MESSAGE_PATTERNS" ] && mapfile -t block_patterns <<< "$BLOCK_PUSH_MESSAGE_PATTERNS"

# An empty list builds `grep -i` with no `-e`, which reads the next argument as the pattern and
# matches almost nothing, or exits 2. `if` then reads that as "no match" and the check passes in
# silence. The patterns come from the git-ignored `devenv.slots.local.nix`, so a missing local
# file would disable the guard with no warning. Fail loudly instead.
if [ "${#file_patterns[@]}" -eq 0 ] || [ "${#message_patterns[@]}" -eq 0 ]; then
  cat >&2 <<'MSG'
ERROR: the sensitive-pattern lists are empty, so this hook cannot protect anything.
  Restore `devenv.slots.local.nix` and re-enter the devenv shell:
    ls devenv.slots.local.*.example.nix
    cp devenv.slots.local.<name>.example.nix devenv.slots.local.nix
  Set KDN_JJ_PRE_PUSH_ALLOW_EMPTY=1 to push anyway.
MSG
  [ "${KDN_JJ_PRE_PUSH_ALLOW_EMPTY:-}" = 1 ] || exit 1
fi

# Build the grep arguments. Never pass `-q`: grep closes the pipe on the first match, the writer
# takes SIGPIPE, and `pipefail` turns the whole pipeline into a failure — so a match would read
# as "no match". Redirect to /dev/null instead, which keeps grep reading to the end.
file_grep_args=(-i)
for p in "${file_patterns[@]}"; do file_grep_args+=('-e' "$p"); done
message_grep_args=(-i)
for p in "${message_patterns[@]}"; do message_grep_args+=('-e' "$p"); done
block_grep_args=(-i)
for p in "${block_patterns[@]}"; do block_grep_args+=('-e' "$p"); done

# Report a match without a print of the pattern itself. A pattern is private configuration.
report_files() {
  echo "ERROR: refusing push to '$1' — a path matches a sensitive pattern:" >&2
  printf '%s\n' "$2" | grep "${file_grep_args[@]}" | sed 's/^/  /' >&2 || true
  echo "  (${#file_patterns[@]} patterns in the list; run \`jj fork-audit\` for the detail)" >&2
}

check_range() {
  # $1 = the target ref, for the message. $2... = revision arguments for `git log`.
  local ref="$1"
  shift
  local msgs files
  msgs=$(git log --format='%s' "$@")
  files=$(git log --format= --name-only "$@" | sort -u)

  # Block certain commit messages on every remote. The list may legitimately be empty — the
  # option default is `[ ]` — and an empty list builds `grep -i` with no `-e`, which exits 2.
  # `if` reads exit 2 as "no match", so the check would pass in silence. Test the count first,
  # so an empty list is an explicit no-op and never a silent pass.
  if [ "${#block_patterns[@]}" -gt 0 ] \
    && printf '%s\n' "$msgs" | grep "${block_grep_args[@]}" >/dev/null; then
    echo "ERROR: a commit message matches an always-blocked pattern. Refusing push to '$ref'." >&2
    printf '%s\n' "$msgs" | grep "${block_grep_args[@]}" | sed 's/^/  /' >&2 || true
    return 1
  fi

  # The private fork remote may receive private content. Every other remote may not.
  if [ -n "$push_remote" ] && [ "$push_remote" = "$PRIVATE_REMOTE" ]; then
    return 0
  fi

  if printf '%s\n' "$files" | grep "${file_grep_args[@]}" >/dev/null; then
    report_files "$ref" "$files"
    return 1
  fi
  if printf '%s\n' "$msgs" | grep "${message_grep_args[@]}" >/dev/null; then
    echo "ERROR: a commit message matches a sensitive pattern. Refusing push to '$ref'." >&2
    printf '%s\n' "$msgs" | grep "${message_grep_args[@]}" | sed 's/^/  /' >&2 || true
    return 1
  fi

  # Content, not only the path. A file with a public name can still hold a private string, and a
  # path check cannot see that. Pipe the diff instead of a capture: a range diff gets large.
  if git log --format= -p "$@" | grep -I "${file_grep_args[@]}" >/dev/null; then
    echo "ERROR: a diff line matches a sensitive pattern. Refusing push to '$ref'." >&2
    git log --format= -p "$@" | grep -I -n "${file_grep_args[@]}" | head -5 | sed 's/^/  /' >&2 || true
    echo "  (run \`jj fork-audit\` for the full verdict)" >&2
    return 1
  fi
  return 0
}

saw_ref=0
while read -r _local_ref local_sha remote_ref remote_sha; do
  # A zero local sha means a delete. There is no new content to check.
  if [ "$local_sha" = "$ZERO_SHA" ]; then
    continue
  fi
  saw_ref=1

  if [ "$remote_sha" != "$ZERO_SHA" ]; then
    # The remote already holds this ref, so check the new commits only.
    check_range "$remote_ref" "$remote_sha..$local_sha"
  else
    # A new ref. `main..$local_sha` would be empty when the pushed branch IS main, so ask git
    # for the commits that the target remote does not hold yet.
    check_range "$remote_ref" "$local_sha" --not --remotes="${push_remote:-*}"
  fi
done

if [ "$saw_ref" = 0 ]; then
  if [ -n "${KDN_JJ_PRE_PUSH_RANGE:-}" ]; then
    check_range "${push_remote:-<unknown remote>}" "$KDN_JJ_PRE_PUSH_RANGE"
  elif [ -n "$push_remote" ] && [ "$push_remote" = "$PRIVATE_REMOTE" ]; then
    echo "WARNING: no ref lines on stdin; the private remote needs no content check." >&2
  else
    cat >&2 <<MSG
ERROR: this hook received no ref lines on stdin, so it cannot tell what you push.
  Target remote: ${push_remote:-<unknown>} (not the private remote, so the content checks matter).
  The pre-commit framework hands a pre-push hook no stdin. Either push with plain git, or name
  the range yourself and retry:
    KDN_JJ_PRE_PUSH_RANGE='main@${PRIVATE_REMOTE}..upstream-tip' git push ...
  Run \`jj fork-audit\` first to see the content verdict.
MSG
    exit 1
  fi
fi
