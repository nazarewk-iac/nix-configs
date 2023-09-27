#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x
# creates/updates git worktrees (aka branches)

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
self g-get "$repo"

for branch in "$@"; do
  dir="$(self g-wt-dir "$repo" "$branch")"
  mkdir -p "${dir%/*}"

  if [ -d "$dir" ]; then
    echo "$dir already exists, updating..."
    git -C "$dir" fetch --all --prune
    git -C "$dir" pull --rebase || :
    continue
  fi

  git -C "$repo_dir" worktree add "$dir" "origin/$branch"
done
