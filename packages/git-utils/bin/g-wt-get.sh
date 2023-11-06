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
    if [ "${GIT_UTILS_KDN_UPDATE:-}" != 0 ]; then
      echo "$dir already exists, updating..." >&2
      git -C "$dir" fetch --all --prune
      git -C "$dir" reset --soft "origin/${branch}" || true
    else
      echo "$dir already exists, skipping..." >&2
    fi
    continue
  fi

  git -C "$repo_dir" worktree add "$dir" "origin/$branch"
done
