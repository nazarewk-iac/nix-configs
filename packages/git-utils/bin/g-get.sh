#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}/$1.sh" "${@:2}"
  else
    "$@"
  fi
}

for entry in "$@"; do
  dir="$(self g-dir "$entry")"
  remote="$(self g-remote "$entry")"

  if [ -d "$dir/.git" ]; then
    if [ "${GIT_UTILS_KDN_UPDATE:-}" != 0 ]; then
      echo "$dir already exists, updating..." >&2
      git -C "$dir" fetch --all --prune
      git -C "$dir" pull --rebase || true
    else
      echo "$dir already exists, skipping..." >&2
    fi
    continue
  fi

  git clone "$remote" "$dir"
done
