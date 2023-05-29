#!/usr/bin/env bash
set -eEuo pipefail

IDE="${IDE:-"idea-ultimate"}"

bin_suffix=""
if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
  bin_suffix=".sh"
  export PATH="${BASH_SOURCE[0]%/*}:${PATH}"
fi

for entry in "$@"; do
  dir="$("g-dir${bin_suffix}" "$entry")"

  if [ ! -d "$dir/.git" ]; then
    git clone "$("g-remote${bin_suffix}" "$entry")" "$dir"
  fi

  "${IDE}" "${dir}"
done
