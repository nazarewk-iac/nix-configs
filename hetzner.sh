#!/usr/bin/env bash
set -xeEuo pipefail
#!/usr/bin/env bash
set -xeEuo pipefail

if [ "${APPLY:-}" = 1 ] ; then
  cmd () { "$@"; }
else
  cmd () { echo "$@"; }
  set +x
fi

to_file() {
  if [ "${APPLY:-}" = 1 ] ; then
    tee "$@"
  else
    tee
  fi
}

installer_update() {
  if [ ! -e /etc/nixos/configuration.bkp.nix ] ; then
    bash <(curl -L 'https://raw.githubusercontent.com/nazarewk-iac/nix-configs/main/installer-update.sh')
  fi
}

script=(
  mklabel msdos
  mkpart primary ext4 1MiB -1Mib
)

cmd installer_update
if mountpoint /mnt ; then
  cmd umount /mnt
fi
cmd parted -s /dev/sda -- "${script[@]}"
cmd partprobe
cmd mkfs.ext4 /dev/sda1
cmd mount /dev/sda1 /mnt

checkout_dir=/mnt/home/nazarewk/dev/github.com/nazarewk-iac
repo_dir="${checkout_dir}/nix-configs"
cmd mkdir -p "${checkout_dir}"
if [ -d "${repo_dir}" ] ; then
  cmd git pull "${repo_dir}"
else
  cmd git clone https://github.com/nazarewk-iac/nix-configs.git "${repo_dir}"
fi
cmd chown -R 1000:100 /mnt/home/nazarewk

cmd mkdir -p /mnt/etc/nixos
cmd ln -s "${repo_dir/"/mnt"/"../.."}/flake.nix" /mnt/etc/nixos/flake.nix
cmd nixos-install --impure --show-trace --root /mnt --flake "${repo_dir}#${HOST}"