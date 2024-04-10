#!/usr/bin/env bash
set -xeEuo pipefail
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT

target=/mnt
host="${1}"
pool="${2:-"${host}-main"}"

umount -R "${target}" || :
for p in "${pool}" "${@:3}" ; do
  zpool export "${p}" || :
  cryptsetup close "${p}-crypted" || :
done