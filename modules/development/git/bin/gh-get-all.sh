#!/usr/bin/env bash
set -eEuo pipefail

bin_suffix=""
if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
  bin_suffix=".sh"
  export PATH="${BASH_SOURCE[0]%/*}:${PATH}"
fi

readarray -t repos <<<"$("gh-repos${bin_suffix}" "$@")"
"g-get${bin_suffix}" "${repos[@]}"
