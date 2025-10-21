#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
# shellcheck disable=SC2059
info() { printf "[$(date -Iseconds)]${1}\n" "${@:2}" >&2; }
info STARTING
trap 'info FINISHED' EXIT

host="${1}"
pool="${2:-"${host}-main"}"

./disks-umount.sh "${host}" "${pool}"
./disko-build-scripts.sh "${host}"
./disko-"${host}"-recreate