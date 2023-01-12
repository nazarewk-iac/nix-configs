#!/usr/bin/env bash
set -xeEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

host="${1}"
pool="${2:-"${host}-main"}"

./disks-umount.sh "${host}" "${pool}"
./disko-build-scripts.sh "${host}"
./disko-"${host}"-recreate