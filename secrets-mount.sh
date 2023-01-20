#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

pool="nazarewk-iskaral"

if ! zpool status "${pool}"; then
  sudo zpool import ${pool}
fi

# zfs list -o name,keystatus,keyformat,encryptionroot
if zfs list -o name,keystatus ${pool} | grep "^${pool} " | grep 'unavailable'; then
  pass show zpools/${pool}/encryption-key | sudo zfs load-key ${pool}
fi

mountpoints=(
  "/${pool}/secrets/luks"
  "/${pool}/secrets/gpg"
)

for mp in "${mountpoints[@]}"; do
  if ! mountpoint "${mp}"; then
    sudo zfs mount "${mp#/}"
  fi
done

