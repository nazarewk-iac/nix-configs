#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x
# removes git worktrees (aka branches)

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}/$1.sh" "${@:2}"
  else
    "$@"
  fi
}

repo="$1"
shift 1
repo_dir="$(self g-dir "$repo")"

for branch in "$@"; do
  dir="$(self g-wt-dir "$repo" "$branch")"
  if [ -d "$dir" ]; then
    git -C "$repo_dir" worktree remove "$dir" || :
  else
    git -C "$repo_dir" worktree prune || :
  fi
done
