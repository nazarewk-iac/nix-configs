#!/usr/bin/env bash
set -xeEuo pipefail

target="${1:-"/mnt"}"
zfs_prefix="oams-main/fs"
zpool="${zfs_prefix%%/*}"

if [ "${APPLY:-}" = 1 ]; then
  function cmd() { "$@"; }
else
  function cmd() { echo "$@"; }
  test -n "${DEBUG:-}" || set +x
fi

function mnt() {
  local current_mountpoint="${!#}"
  if mountpoint "${current_mountpoint}"; then
    return 0
  fi
  cmd mkdir -p "${current_mountpoint}"
  cmd mount "$@"
}

function ensureZFS() {
  local dataset_name="${1}"
  local dataset="${zfs_prefix}${dataset_name%/}"
  if ! zfs list "${dataset}" &>/dev/null; then
    cmd zfs create "${dataset}"
  fi
}

function setupZFS() {
  local dataset_name="${1}"
  ensureZFS "${dataset_name}"
  local mountpoint="${dataset_name%/}"
  [[ -n "${mountpoint}" ]] || mountpoint=/
  local current_mountpoint="${target%/}/${mountpoint#/}"
  current_mountpoint="${current_mountpoint%/}"
  local dataset="${zfs_prefix}${dataset_name%/}"
  local old_mountpoint
  old_mountpoint="$(zfs list -o mountpoint "${dataset}" | tail -n 1)"
  [ "${old_mountpoint}" != "none" ] || old_mountpoint=
  if [ "${current_mountpoint}" != "${old_mountpoint}" ]; then
    cmd zfs set "mountpoint=${mountpoint}" "${dataset}"
  fi
  if mountpoint "${current_mountpoint}"; then
    return 0
  fi
  cmd mkdir -p "${current_mountpoint}"
  cmd zfs mount "${dataset}"
}

altroot="$(zpool list -o altroot "${zpool}" | tail -n 1)"
if [ -n "${altroot}" ] && [ "${altroot}" != "${target}" ]; then
  echo "altroot=${altroot} does not equal target=${target}!"
  exit 1
fi

zpool status "${zpool}" || cmd zpool import -N -R "${target}" "${zpool}"
cmd zfs load-key -a

ensureZFS ""
setupZFS "/"
mnt -t vfat "/dev/disk/by-uuid/1290-B5A3" "${target}/boot"
setupZFS "/etc"
setupZFS "/home"
setupZFS "/home/kdn"
setupZFS "/home/kdn/.cache"
setupZFS "/home/kdn/.config"
setupZFS "/home/kdn/.local"
setupZFS "/home/kdn/.local/share"
setupZFS "/home/kdn/.local/share/containers"
setupZFS "/home/kdn/Downloads"
setupZFS "/home/kdn/Nextcloud"
setupZFS "/home/kdn/dev"
setupZFS "/nix"
setupZFS "/nix/store"
setupZFS "/nix/var"
setupZFS "/var"
setupZFS "/var/lib"
setupZFS "/var/lib/libvirt"
setupZFS "/var/lib/microvms"
setupZFS "/var/log"
setupZFS "/var/log/journal"
setupZFS "/var/spool"
