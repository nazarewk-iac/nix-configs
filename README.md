# nix-configs

Repository containing my personal Nix (NixOS, Home Manager etc.) configurations.

Basic structure:

- `modules/` - all modules live here, they MUST be turned off by default (side-effect free imports),
    - `modules/nixos` - NixOS specific modules
    - `modules/home-manager` - Home Manager modules
    - `modules/nix-darwin` - nix-darwin modules
    - `modules/shared` - modules & configs shared by more than 1 "target"
        - `modules/shared/universal` - universal modules, often defining options to be handled elsewhere
- `packages/`, some personal/in-house/out-of-band tools

Generally I aim to hide as much as possible behind `*.enable` options.

## Overview

This is an incomplete list of incorporated software/systems:

- disks: ZFS on LUKS through `disko`
- desktop: Sway (Wayland), as much as possible through Home Manager
- shell: Fish
- users: Home Manager
- MISSING: development environment

# Notes

## Custom ISO installer

see https://bmcgee.ie/posts/2022/12/setting-up-my-new-laptop-nix-style/

```shell
# building the installer from packages/install-iso
set INSTALL_ISO_PATH "$(nom build '.#install-iso' --no-link --print-out-paths --print-build-logs)/iso/nixos.iso"
sudo dd if="$INSTALL_ISO_PATH" of=/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_02000515031521144721-0:0 status=progress
sudo dd if="$INSTALL_ISO_PATH" of=/dev/disk/by-id/usb-_Patriot_Memory_070133F17AC22052-0:0 status=progress
sudo dd if="$INSTALL_ISO_PATH" of=/dev/disk/by-id/usb-Samsung_Portable_SSD_T5_1234567D585A-0:0 status=progress
scp "$INSTALL_ISO_PATH" root@kvm-fa56.lan.etra.net.int.kdn.im:/data/nixos-amd64.iso
# boot the machine and ssh into it
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null kdn@nixos
```

## Golden path for bootstrapping new physical machine

1. build the `install-iso` and boot it
2. prepare a new config at `modules/nixos/profile/host/${HOSTNAME}/default.nix`
    - put `kdn.profile.machine.baseline.enable = true`
    - look through `kdn.hardware.{gpu,cpu}.{intel,amd}`
    - set up `zramSwap` & `boot.tmp.tmpfsSize`
    - figure out missing `boot.initrd.{availableK,k}ernelModules`
3. set up a disk configuration:
    ```nix
    (
      # hashtag comment denotes defaults
      # /* */ are just comments
      let
        cfg = config.kdn.hardware.disks;
        d1 = "<DISK_1_NAME>-${config.networking.hostName}";
        d1Cfg = cfg.luks.volumes."${d1}";
        d2 = "<DISK_2_NAME>-${config.networking.hostName}";
        d2Cfg = cfg.luks.volumes."${d2}";
      in
      {
        kdn.hardware.disks.enable = true;
        #kdn.hardware.disks.zpool-main.name = "<HOSTNAME>-main";
        #kdn.hardware.disks.devices."boot" = { type = "gpt"; content.partitions.ESP = { size = "4096M"; ... }; };
        #kdn.hardware.disks.zpools."${cfg.zpool-main.name}" = { };
        #disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
        # "${hostname}/nix-system/nix-store" = { mountpoint = "/nix/store"; ... };
        # "${hostname}/nix-system/nix-var" = { mountpoint = "/nix/var"; ... };
        #}
   
        /* point it at the right detached `/boot` disk (USB flash drive) */
        kdn.hardware.disks.devices."boot".path = "/dev/disk/by-id/usb-<CORRECT_IDENTIFIER>";
        #disko.devices.disk.boot = { content.type = "gpt"; content.partitions = { ... }; ... };
        #kdn.hardware.disks.devices."${d1}" = { type = "luks"; path = d1Cfg.targetSpec.path; };
        #disko.devices.disk."${d1}" = { type = "luks"; name = "${d1}-crypted"; ... };
        #kdn.hardware.disks.devices."${d2}" = { type = "luks"; path = d2Cfg.targetSpec.path; };
        #disko.devices.disk."${d1}" = { type = "luks"; name = "${d1}-crypted"; ... };
   
        kdn.hardware.disks.luks.volumes."${d1}" = {
          #target.deviceKey = d1;
          targetSpec.path = "/dev/disk/by-id/<DISK_PATH>";
          uuid = "<uuidgen result>";
          #keyFile = "/tmp/${d1}.key";
          #header.deviceKey = "boot";
          #header.partitionKey = d1;
          headerSpec.num = 2;
          #zpool.name = cfg.zpool-main.name;
        };

        kdn.hardware.disks.luks.volumes."${d2}" = {
          #target.deviceKey = d2;
          targetSpec.path = "/dev/disk/by-id/<DISK_PATH>";
          uuid = "<uuidgen result>";
          #keyFile = "/tmp/${d1}.key";
          #header.deviceKey = "boot";
          #header.partitionKey = d2;
          headerSpec.num = 3;
          #zpool.name = cfg.zpool-main.name;
        };
   
        #kdn.hardware.disks.impermanence."sys/config".snapshots = true;
        #kdn.hardware.disks.impermanence."sys/cache".snapshots = false;
        #kdn.hardware.disks.impermanence."sys/data".snapshots = true;
        #kdn.hardware.disks.impermanence."sys/state".snapshots = false;
        #kdn.hardware.disks.impermanence."usr/config".snapshots = true;
        #kdn.hardware.disks.impermanence."usr/cache".snapshots = false;
        #kdn.hardware.disks.impermanence."usr/data".snapshots = true;
        #kdn.hardware.disks.impermanence."usr/state".snapshots = false;
        
        /* just a single impermanence example goes below */
        #kdn.hardware.disks.impermanence."usr/data" = {
        #  #zpool.name = cfg.zpool-main.name;
        #  #zfsPrefix = "${config.networking.hostName}/impermanence";
        #  #zfsPath = "${zfsPrefix}/${"usr/data"}";
        #  imp.directories = [
        #    "/var/lib/libvirt/images"
        #  ];
        #  imp.users.root.directories = [
        #    # ...
        #  ];
        #  imp.users.kdn.directories = [
        #    ".local/share/atuin"
        #    ".local/share/nix"
        #    ".local/share/containers"
        #    "dev"
        #  ];
        #};
        #environment.persistence."/nix/persist/usr/data" = {
        #  enable = true; 
        #  hideMounts = true; 
        #  users.root.home = "/root";
        #} // cfg.impermanence."usr/data".imp;
        #disko.devices.zpool."${cfg.zpool-main.name}".datasets."${cfg.impermanence."usr/data".zfsPath}" = { ... };
   
        #kdn.hardware.disks.tmpfs.size = "16M";
        #disko.devices.nodev."/" = { fsType = "tmpfs"; mountPoints = ["size=${cfg.tmpfs.size}" ... ]; };
        #disko.devices.nodev."/" = { fsType = "tmpfs"; mountPoints = ["size=${cfg.tmpfs.size}" ... ]; };
      }
    )
    ```
4. add all your required `environment.persistence` entries
5. set up keyfiles for each disk:
    ```shell
    # this is fish shell
    set HOST_NAME faro
    set DISK_NAME virtual
    dd if=/dev/random bs=1 count=2048 of=/dev/stdout | pass insert --force --multiline "luks/$DISK_NAME-$HOST_NAME/keyfile"
    ```

6. boot the `install-iso`
7. run `nixos-anywhere` to deploy
    ```shell
    # this is fish shell
    set HOST_NAME faro
    set DISK_NAME virtual
    set HOST_CONNECTION root@192.168.73.79
    # build locally
    nixos-anywhere --phases disko,install --disk-encryption-keys "/tmp/$DISK_NAME-$HOST_NAME.key" "$(pass show "luks/$DISK_NAME-$HOST_NAME/keyfile" | psub)" --flake ".#$HOST_NAME" "$HOST_CONNECTION"
    
    # build on the target machine
    nixos-anywhere --phases disko,install --build-on-remote --disk-encryption-keys "/tmp/$DISK_NAME-$HOST_NAME.key" "$(pass show "luks/$DISK_NAME-$HOST_NAME/keyfile" | psub)" --flake ".#$HOST_NAME" "$HOST_CONNECTION"
    ```
8. set up either of for each disk:
    - (unattended) TPM2 unlock:
        ```shell
        ssh o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_CONNECTION" sudo systemd-cryptenroll --unlock-key-file="/tmp/$DISK_NAME-$HOST_NAME.key" --tpm2-device=auto "/dev/disk/by-partlabel/$DISK_NAME-$HOST_NAME-header"
        ```
    - (attended) YubiKey FIDO2 (touch required, without PIN) unlock:
        ```shell
        ssh o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_CONNECTION" sudo systemd-cryptenroll --unlock-key-file="/tmp/$DISK_NAME-$HOST_NAME.key" --fido2-device=auto --fido2-with-client-pin=false --fido2-with-user-verification=false "/dev/disk/by-partlabel/$DISK_NAME-$HOST_NAME-header"
        ```

9. add SSH key to `/.sops.yaml`
    - `ssh-to-age </etc/ssh/ssh_host_ed25519_key.pub`
    - reboot

### partial recovery

decrypt volume using FIDO2:

```shell
set HOST_NAME faro
set DISK_NAME virtual
set HOST_CONNECTION root@192.168.73.79
set ENCRYPTED_DEVICE /dev/vdb
set ENCRYPTED_HEADER /dev/vda2
set ENCRYPTED_NEW_SLOT 3

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_CONNECTION" systemd-cryptsetup attach "$HOST_NAME-main-crypted" "$ENCRYPTED_DEVICE" - header="$ENCRYPTED_HEADER"
```

copying the keyfile to the machine:

```shell
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$(pass show "luks/$DISK_NAME-$HOST_NAME/keyfile" | psub)" "$HOST_CONNECTION:/tmp/$DISK_NAME-$HOST_NAME.key"
```

generate & register a passphrase:
```shell
pass generate "luks/$DISK_NAME-$HOST_NAME/passphrase" 32
# copy it to device
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$(pass show "luks/$DISK_NAME-$HOST_NAME/passphrase" | tr -d '\n' | psub)" "$HOST_CONNECTION:/tmp/$DISK_NAME-$HOST_NAME.passphrase"
# add it to the header
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_CONNECTION" cryptsetup luksAddKey --header="$ENCRYPTED_HEADER" --new-key-slot="$ENCRYPTED_NEW_SLOT" --key-file="/tmp/$DISK_NAME-$HOST_NAME.key" "$ENCRYPTED_DEVICE" "/tmp/$DISK_NAME-$HOST_NAME.passphrase"
# decrypt, paste the key into it
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_CONNECTION" cryptsetup open --header="$ENCRYPTED_HEADER" "$ENCRYPTED_DEVICE" "$HOST_NAME-main-crypted"
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

## systemd-cryptenroll --fido2-with-user-presence=false doesn't work with YubiKey

YubiKey's FIDO2 applet seems to ALWAYS require touch, so it cannot be used for unattended unlock of LUKS volume:

```shell
> systemd-cryptenroll --unlock-key-file=$(cat /tmp/emmc-etra.key | psub) --fido2-device=auto --fido2-with-client-pin=false --fido2-with-user-verification=false --fido2-with-user-presence=false /dev/disk/by-partlabel/disk-boot-emmc-etra-header
Initializing FIDO2 credential on security token.
👆 (Hint: This might require confirmation of user presence on security token.)
Generating secret key on FIDO2 security token.
👆 Locking without user presence test requested, but FIDO2 device /dev/hidraw1 requires it, enabling.
New FIDO2 token enrolled as key slot 1.
```

# Keeping nixpkgs fork with arbitrary patches up to date

Using my own [`.flake.patches/update.py`](.flake.patches/update.py) script:

1. Create required `nixpkgs` inputs:
    - `nixpkgs-upstream` - desired upstream nixpkgs branch
    - `nixpkgs` - the fork you have access to that will be managed by the updater
    - add entries to [`.flake.patches/config.toml`](.flake.patches/config.toml)
2. run `nix run '.#nixpkgs-update' g:patches`

Most of it is wrapped in [`/nixpkgs-update.sh`](nixpkgs-update.sh) and top entries of [`/flake.nix`](flake.nix).

# TODOs

- [ ] TODO: evaluate https://github.com/Mic92/nix-fast-build
- [ ] TODO: evaluate https://github.com/nix-community/nix-eval-jobs
- [ ] TODO: try to integrate lanzaboote?