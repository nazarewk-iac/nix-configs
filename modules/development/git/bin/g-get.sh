#!/usr/bin/env bash
set -eEuo pipefail

for entry in "$@"; do
  dir="$(g-dir "$entry")"
  remote="$(g-remote "$entry")"

  if [ -d "$dir/.git" ]; then
    echo "$dir already exists, updating..."
    git -C "$dir" fetch --all --prune
    git -C "$dir" pull --rebase || true
    continue
  fi

  git clone "$remote" "$dir"
done
