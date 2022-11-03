#!/usr/bin/env bash
set -xeEuo pipefail

target="${1:-"/mnt"}"
zpool="oams-primary"
zfs_prefix="${zpool}/oams"
if [ "${APPLY:-}" = 1 ]; then
  cmd() { "$@"; }
else
  cmd() { echo "$@"; }
  test -n "${DEBUG:-}" || set +x
fi

mnt() {
  local mountpoint="${!#}"
  if mountpoint "${mountpoint}"; then
    return 0
  fi
  cmd mkdir -p "${mountpoint}"
  cmd mount "$@"
}

mntZFS() {
  local dataset_name="${1}"
  local prefix="${2:-}"
  local path="${3:-"${dataset_name}"}"
  path="${path%/}"
  local mountpoint="${target%/}/${path#/}"
  local dataset="${zfs_prefix}${prefix}${dataset_name}"
  mnt -t zfs "${dataset}" "${mountpoint}"
}

zpool status "${zpool}" || cmd zpool import "${zpool}"
cmd zfs load-key -a

mntZFS "/root" "/nixos" "/"
mnt -t vfat "/dev/disk/by-uuid/2BFB-6A81" "${target}/boot"
mntZFS "/etc" "/nixos"
mntZFS "/nix" "/nixos"
mntZFS "/var" "/nixos"
mntZFS "/var/lib/libvirt" "/nixos"
mntZFS "/var/lib/rook" "/nixos"
mntZFS "/var/lib/microvms" "/nixos"
mntZFS "/var/log" "/nixos"
mntZFS "/var/log/journal" "/nixos"
mntZFS "/var/spool" "/nixos"

mntZFS "/home"
mntZFS "/home/kdn"
mntZFS "/home/kdn/.cache"
mntZFS "/home/kdn/Downloads"
mntZFS "/home/kdn/Nextcloud"
mntZFS "/home/kdn/.local"
mntZFS "/home/kdn/.local/share"
mntZFS "/home/kdn/.local/share/containers"
