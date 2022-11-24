#!/usr/bin/env bash
set -eEuo pipefail

IDE="${IDE:-"idea-ultimate"}"

for entry in "$@"; do
  dir="$(g-dir "$entry")"

  if [ ! -d "$dir/.git" ]; then
    git clone "$(g-remote "$entry")" "$dir"
  fi

  "${IDE}" "${dir}"
done
