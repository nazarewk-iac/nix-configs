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
  mkpart primary ext4 0 100%
)

cmd installer_update
cmd umount /mnt || true
cmd parted -s /dev/sda -- "${script[@]}"
cmd partprobe
cmd mkfs.ext4 /dev/sda1
cmd mount /dev/sda1 /mnt

checkout_dir=/mnt/home/nazarewk/dev/github.com/nazarewk-iac
cmd mkdir -p "${checkout_dir}"
cmd git clone https://github.com/nazarewk-iac/nix-configs.git "${checkout_dir}/nix-configs"
cmd chown -R 1000:100 /mnt/home/nazarewk

cmd mkdir -p /mnt/etc/nixos
cmd ln -s "${checkout_dir/"/mnt"/"../.."}/nix-configs/flake.nix" /mnt/etc/nixos/flake.nix
cmd nixos-install --show-trace --root /mnt --flake "${checkout_dir}/nix-configs#${HOST}"