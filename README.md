# nix-configs

Repository containing my personal Nix (NixOS, Home Manager etc.) configurations.

Basic structure:

- `modules/` - all modules live here, they MUST be turned off by default (side-effect free imports),
    - `modules/default.nix` - holds imports to all the modules and basic Nix package manager configuration,
    - `modules/profile/machine` - large NixOS configuration bundles
    - `modules/profile/user` - user specific profiles

Generally I aim to hide everything behind Options, but bulk of configuration still lives in `configurations/desktop`.

## Overview

This is incomplete list of incorporated software/systems worth noting:

- ZFS
- Sway WM
- ZSH
- Home Manager

# Notes

## Custom ISO installer

see https://bmcgee.ie/posts/2022/12/setting-up-my-new-laptop-nix-style/

```shell
# building the installer from packages/install-iso
sudo dd if="$(nom build '.#install-iso' --no-link --print-out-paths --print-build-logs)/iso/nixos.iso" of=/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_02000515031521144721-0:0 status=progress
# boot the machine and ssh into it
ssh -o StrictHostKeyChecking=no kdn@nixos
```

## Building fresh system from `nixos-installer` stable image

1. Add SSH keys from `curl https://api.github.com/users/nazarewk/keys` to `~/.ssh/authorized_keys`
2. Disable suspend on idle in power settings of Gnome
3. `ssh -o StrictHostKeyChecking=no nixos@<whatever-machine-ip-is>`
4. `APPLY=1 bash <(curl -L 'https://raw.githubusercontent.com/nazarewk-iac/nix-configs/main/installer-update.sh')`:
5. Set up your filesystem at `/mnt`, eg to mount:
   ```
   APPLY=1 bash <(curl -L 'https://github.com/nazarewk-iac/nix-configs/raw/main/machines/krul/mount.sh')
   ```
6. checkout the repo:
   ```
   mkdir -p /mnt/home/kdn/dev/github.com/nazarewk-iac
   git clone https://github.com/nazarewk-iac/nix-configs.git /mnt/home/kdn/dev/github.com/nazarewk-iac/nix-configs
   chown -R 1000:100 /mnt/home/kdn
   ```
7. set up the system-level `flake.nix`:
   ```
   mkdir -p /mnt/etc/nixos
   ln -s ../../home/kdn/dev/github.com/nazarewk-iac/nix-configs/flake.nix /mnt/etc/nixos/flake.nix
   ```
8. run the build, eg:
   ```
   nixos-install --show-trace --root /mnt --flake '/mnt/home/kdn/dev/github.com/nazarewk-iac/nix-configs#krul'
   ```

## Building on Hetzner Cloud from NixOS installer image

1. mount the NixOS installer image
2. run the build:
   ```
   APPLY=1 HOST="<HOST>" bash <(curl -L 'https://raw.githubusercontent.com/nazarewk-iac/nix-configs/main/hetzner.sh')
   ```

## Interaction between NixOS and Home Manager

- https://jdisaacs.com/blog/nixos-config/

## How to find out what uses the specific store path?

Find immediate parents/reverse dependencies: `nix-store --query --referrers <paths...>`.

Find the root using paths: `nix-store --query --roots <paths...>`.

## Fix nix store errors

Fix errors like `/nix/store/*-source not found`: `sudo nix-store --repair --verify --check-contents`.

## GitHub rate-limiting unauthenticated requests

see https://discourse.nixos.org/t/flakes-provide-github-api-token-for-rate-limiting/18609

add token to `~/.config/nix/nix.conf`:

```
access-tokens = github.com=github_pat_XXXX
```

## example of standalone Nix module

https://gist.github.com/nazarewk/8988facb6118f73d2db3d28b64463cba
