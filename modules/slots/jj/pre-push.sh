#!/usr/bin/env bash
set -eEuo pipefail

# PRIVATE_REMOTE, SENSITIVE_FILE_PATTERNS, SENSITIVE_MESSAGE_PATTERNS,
# BLOCK_PUSH_MESSAGE_PATTERNS are baked in via runtimeEnv as space-separated strings.

# $1 is the remote name when called directly by git.
# When invoked via the pre-commit framework, git's argv is not forwarded but
# PRE_COMMIT_REMOTE_BRANCH is set instead — extract the remote name from it.
push_remote="${1:-${PRE_COMMIT_REMOTE_BRANCH%%/*}}"
if [ -z "$push_remote" ]; then
  echo "WARNING: push_remote is unset, skipping remote-specific checks" >&2
  # still run always-on checks below, but skip remote-specific ones
fi

ZERO_SHA="0000000000000000000000000000000000000000"

# shellcheck disable=SC2206
file_patterns=($SENSITIVE_FILE_PATTERNS)
# shellcheck disable=SC2206
message_patterns=($SENSITIVE_MESSAGE_PATTERNS)
# shellcheck disable=SC2206
block_patterns=($BLOCK_PUSH_MESSAGE_PATTERNS)

file_grep_args=(-q -i)
for p in "${file_patterns[@]}"; do
  file_grep_args+=('-e' "$p")
done

message_grep_args=(-q -i)
for p in "${message_patterns[@]}"; do
  message_grep_args+=('-e' "$p")
done

block_grep_args=(-q -i)
for p in "${block_patterns[@]}"; do
  block_grep_args+=('-e' "$p")
done

while read -r _local_ref local_sha remote_ref remote_sha; do
  if test "$local_sha" == "$ZERO_SHA"; then
    continue
  fi

  # For new branches with no remote history yet, check from root
  if [ "$remote_sha" = "$ZERO_SHA" ]; then
    range="main..$local_sha"
  else
    range="$remote_sha..$local_sha"
  fi

  # Always-on: block certain commit messages regardless of remote
  while read -r msg; do
    if echo "$msg" | grep "${block_grep_args[@]}"; then
      echo "ERROR: Commit message matches always-blocked pattern: ${block_patterns[*]}"
      echo "  $msg"
      echo "Refusing push to '${remote_ref}'."
      exit 1
    fi
  done < <(git log --format="%s" "$range")

  # Remote protection: only applies when pushing to the private fork remote
  if test "$push_remote" != "$PRIVATE_REMOTE"; then
    continue
  fi

  if git diff --name-only "$remote_sha" "$local_sha" | grep "${file_grep_args[@]}"; then
    echo "ERROR: Refusing push — sensitive file path found in commits."
    exit 1
  fi

  while read -r msg; do
    if echo "$msg" | grep "${message_grep_args[@]}"; then
      echo "ERROR: Commit message matches blocked pattern: ${message_patterns[*]}"
      echo "  $msg"
      echo "Refusing push to '${remote_ref}'."
      exit 1
    fi
  done < <(git log --format="%s" "$range")
done
