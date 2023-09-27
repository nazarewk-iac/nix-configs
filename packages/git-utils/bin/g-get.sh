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
  remote="$entry"

  if [ -d "$dir/.git" ]; then
    echo "$dir already exists, updating..."
    git -C "$dir" fetch --all --prune
    git -C "$dir" pull --rebase || true
    continue
  fi

  git clone "$remote" "$dir"
done
