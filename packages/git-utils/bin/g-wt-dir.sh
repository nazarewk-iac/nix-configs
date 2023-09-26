#!/usr/bin/env bash
set -eEuo pipefail
# unifed location of git worktrees

GIT_UTILS_KDN_WORKTREES_DIR="${GIT_UTILS_KDN_WORKTREES_DIR:-".worktrees"}"

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}$1.sh" "${@:2}"
  else
    "$@"
  fi
}

repo="$1"
shift 1
repo_dir="$(self g-dir "$repo")"

for branch in "$@"; do
  echo "${repo_dir}/${GIT_UTILS_KDN_WORKTREES_DIR}/${branch}"
done
