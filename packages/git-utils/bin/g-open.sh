#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

IDE="${IDE:-"${GIT_UTILS_KDN_IDE:-"idea-ultimate"}"}"

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}/$1.sh" "${@:2}"
  else
    "$@"
  fi
}

for entry in "$@"; do
  dir="$(self g-dir "$entry")"

  if [ ! -d "$dir/.git" ]; then
    git clone "$entry" "$dir"
  fi

  "${IDE}" "${dir}"
done
