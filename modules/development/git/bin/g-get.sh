#!/usr/bin/env bash
set -eEuo pipefail

bin_suffix=""
if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
  bin_suffix=".sh"
  export PATH="${BASH_SOURCE[0]%/*}:${PATH}"
fi

for entry in "$@"; do
  dir="$("g-dir${bin_suffix}" "$entry")"
  remote="$("g-remote${bin_suffix}" "$entry")"

  if [ -d "$dir/.git" ]; then
    echo "$dir already exists, updating..."
    git -C "$dir" fetch --all --prune
    git -C "$dir" pull --rebase || true
    continue
  fi

  git clone "$remote" "$dir"
done
