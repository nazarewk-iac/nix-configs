#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
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