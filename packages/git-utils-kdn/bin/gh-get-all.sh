#!/usr/bin/env bash
set -eEuo pipefail

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}$1.sh" "${@:2}"
  else
    "$@"
  fi
}

readarray -t repos <<<"$( self gh-repos "$@")"
self g-get "${repos[@]}"
