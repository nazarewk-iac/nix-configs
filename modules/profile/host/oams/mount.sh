#!/usr/bin/env bash
set -xeEuo pipefail

target="${1:-"/mnt"}"
zfs_prefix="oams-main/fs"
luks_device="/dev/disk/by-id/ata-Samsung_Portable_SSD_T5_S49TNP0KC01288A"
  # see https://wiki.archlinux.org/title/Dm-crypt/Specialties#Using_systemd_hook
  # Replace XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX with the LUKS super block UUID. It can be acquired with `cryptsetup luksDump header.img` or `sudo blkid -s UUID -o value header.img`
root_uuid="c4b9bdbc-900f-482e-8fa6-6c6824c560e9"
header_dir="/nazarewk-iskaral/secrets/luks/oams"
header_name="main-header.img"
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

if ! zpool status "nazarewk-iskaral" ; then
  zpool import nazarewk-iskaral
fi

if ! mountpoint "/nazarewk-iskaral/secrets/luks"; then
  zfs load-key nazarewk-iskaral || :
  zfs mount nazarewk-iskaral/secrets/luks
fi

if [ ! -e "/dev/mapper/${zpool}" ]; then
  systemd-cryptsetup attach "${zpool}" "${luks_device}" - header="${header_dir}/${header_name}" fido2-device=auto
fi

zpool status "${zpool}" || cmd zpool import -N -R "${target}" "${zpool}"

altroot="$(zpool list -o altroot "${zpool}" | tail -n 1)"
if [ -n "${altroot}" ] && [ "${altroot}" != "${target}" ]; then
  echo "altroot=${altroot} does not equal target=${target}!"
  exit 1
fi

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
