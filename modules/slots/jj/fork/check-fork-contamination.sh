#!/usr/bin/env bash
# Pre-commit hook: reject fork-specific content staged on a kdn/upstream-side commit.
#
# Skips if:
#   - not in a jj repo
#   - current jj change has no description (unnamed working copy scratch change)
#   - current jj change is in fork-candidates (fork-side, content is expected there)
#
# SENSITIVE_FILE_PATTERNS and SENSITIVE_MESSAGE_PATTERNS are baked in via runtimeEnv.

set -eEuo pipefail

# Skip if not in a jj repo
jj root &>/dev/null || exit 0

change_id="$(jj log -r @ --no-graph -T 'change_id' 2>/dev/null)"
description="$(jj log -r @ --no-graph -T 'description' 2>/dev/null)"

# Skip if unnamed working copy
[ -n "$description" ] || exit 0

# Skip if this change is already in fork-candidates (fork-side commit)
if jj log -r "fork-candidates & ${change_id}" --no-graph -T 'change_id' 2>/dev/null | grep -q .; then
  exit 0
fi

# On upstream-candidates side: check staged content for fork-sensitive patterns
# shellcheck disable=SC2206
file_patterns=($SENSITIVE_FILE_PATTERNS)
# shellcheck disable=SC2206
diff_patterns=($SENSITIVE_MESSAGE_PATTERNS $SENSITIVE_FILE_PATTERNS)

failed=0

for p in "${file_patterns[@]}"; do
  if git diff --cached --name-only | grep -qi "$p"; then
    echo "ERROR: staged file path matches fork-sensitive pattern '$p'" >&2
    echo "  This appears to be a kdn/upstream-side commit." >&2
    echo "  Move fork-specific content to a fork-side commit instead." >&2
    failed=1
  fi
done

for p in "${diff_patterns[@]}"; do
  if git diff --cached | grep -qi "$p"; then
    echo "ERROR: staged diff content matches fork-sensitive pattern '$p'" >&2
    echo "  This appears to be a kdn/upstream-side commit." >&2
    echo "  Move fork-specific content to a fork-side commit instead." >&2
    failed=1
  fi
done

exit "$failed"
