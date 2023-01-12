#!/usr/bin/env bash
set -xeEuo pipefail

# TODO: switch to disko
#   see https://bmcgee.ie/posts/2022/12/setting-up-my-new-laptop-nix-style/

target="${1:-"/mnt"}"
zfs_prefix="oams-main/fs"
luks_device="/dev/disk/by-id/ata-Samsung_Portable_SSD_T5_S49TNP0KC01288A"
# see https://wiki.archlinux.org/title/Dm-crypt/Specialties#Using_systemd_hook
# Replace XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX with the LUKS super block UUID. It can be acquired with `cryptsetup luksDump header.img` or `sudo blkid -s UUID -o value header.img`
root_uuid="c4b9bdbc-900f-482e-8fa6-6c6824c560e9"
header_dir="/nazarewk-iskaral/secrets/luks/oams"
header_name="main-header.img"
zpool="${zfs_prefix%%/*}"

# required legacy mountpoints due to using `mount -t zfs` instead of `zfs mount` or `zpool import -R`
# see https://github.com/NixOS/nixpkgs/blob/c07552f6f7d4eead7806645ec03f7f1eb71ba6bd/nixos/lib/utils.nix#L13-L13
legacy_pattern="^"
for mountpoint in "/" "/nix" "/nix/store" "/var" "/var/log" "/var/lib" "/var/lib/nixos" "/etc" "/usr" ; do
  legacy_pattern+="${mountpoint}\|"
done
legacy_pattern="${legacy_pattern%"\|"}"

if [ "${APPLY:-}" = 1 ]; then
  function cmd() { "$@"; }
else
  function cmd() { echo "$@"; }
  test -n "${DEBUG:-}" || set +x
fi

function mnt() {
  local new_mountpoint="${!#}"
  if mountpoint "${new_mountpoint}"; then
    return 0
  fi
  cmd mkdir -p "${new_mountpoint}"
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
  local new_mountpoint="${target%/}/${mountpoint#/}"
  new_mountpoint="${new_mountpoint%/}"
  local mount_at="${new_mountpoint}"
  local dataset="${zfs_prefix}${dataset_name%/}"
  local old_mountpoint
  old_mountpoint="$(zfs list -o mountpoint "${dataset}" | tail -n 1)"
  if grep "${legacy_pattern}" <<<"${new_mountpoint}" ; then
    new_mountpoint=legacy
  fi
  [ "${old_mountpoint}" != "none" ] || old_mountpoint=
  if [ "${new_mountpoint}" != "${old_mountpoint}" ]; then
    cmd zfs set "mountpoint=${mountpoint}" "${dataset}"
  fi
  if mountpoint "${mount_at}"; then
    return 0
  fi
  cmd mkdir -p "${mount_at}"
  cmd mount -t zfs "${dataset}" "${mount_at}"
}

if [ ! -e "/dev/mapper/${zpool}" ]; then
  systemd-cryptsetup attach "${zpool}" "${luks_device}" - header="${header_dir}/${header_name}" fido2-device=auto
  sleep 3
fi

if ! zpool status "nazarewk-iskaral"; then
  zpool import nazarewk-iskaral
fi

if ! mountpoint "/nazarewk-iskaral/secrets/luks"; then
  zfs load-key nazarewk-iskaral || :
  zfs mount nazarewk-iskaral/secrets/luks
fi

if ! mountpoint "/nazarewk-iskaral/secrets/gpg"; then
  zfs load-key nazarewk-iskaral || :
  zfs mount nazarewk-iskaral/secrets/gpg
fi

if [ ! -e "/dev/mapper/${zpool}" ]; then
  systemd-cryptsetup attach "${zpool}" "${luks_device}" - header="${header_dir}/${header_name}" fido2-device=auto
  sleep 3
fi

zpool status "${zpool}" || cmd zpool import -f -N -R "${target}" "${zpool}"

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
