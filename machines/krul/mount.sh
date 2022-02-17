#!/usr/bin/env bash
set -xeEuo pipefail

target="${1:-"/mnt"}"
zpool="nazarewk-krul-primary"
zfs_prefix="${zpool}/nazarewk-krul"
if [ "${APPLY:-}" = 1 ] ; then
  cmd () { "$@"; }
else
  cmd () { echo "$@"; }
  set +x
fi

mnt() {
  cmd mount "$@"
}

mntZFS() {
  local dataset="${1}"
  local prefix="${2:-}"
  local path="${3:-"${dataset}"}"
  path="${path%/}"
  mnt -t zfs "${zfs_prefix}${prefix}${dataset}" "${target}${path}"
}

zpool status "${zpool}" || cmd zpool import "${zpool}"
cmd zfs load-key "${zpool}" || true

mntZFS "/root" "/nixos" "/"
mnt -t vfat "/dev/disk/by-uuid/2BFB-6A81" "${target}/boot"
mntZFS "/etc" "/nixos"
mntZFS "/nix" "/nixos"
mntZFS "/var" "/nixos"
mntZFS "/var/log" "/nixos"
mntZFS "/var/log/journal" "/nixos"
mntZFS "/var/spool" "/nixos"

mntZFS "/home"
mntZFS "/home/nazarewk"
mntZFS "/home/nazarewk/.cache"
mntZFS "/home/nazarewk/Downloads"
mntZFS "/home/nazarewk/Nextcloud"