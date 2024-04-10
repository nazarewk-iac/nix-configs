#!/usr/bin/env bash
set -xeEuo pipefail
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT

host="${1}"
pool="${2:-"${host}-main"}"

./disko-build-scripts.sh "${host}"
./disko-"${host}"-format