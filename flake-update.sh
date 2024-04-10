#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT

if test "$#" = 0 ; then
  nix flake update
else
  args=()
  for input in "${@}" ; do
    args+=(--update-input "${input}")
  done
  nix flake lock "${args[@]}"
fi
