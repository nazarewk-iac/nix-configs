{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.disks;
  hostname = config.networking.hostName;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Basic /boot config
      fileSystems."/boot".neededForBoot = true;
      kdn.hardware.disks.devices."boot".type = "gpt";
      kdn.hardware.disks.devices."boot".partitions."ESP" = {
        num = 1;
        size = 4096;
        disko = {
          /* https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
             Name: EFI System Partition
             UUID: c12a7328-f81f-11d2-ba4b-00a0c93ec93b SD_GPT_ESP
             Filesystems: VFAT
             Explanation:
               The ESP used for the current boot is automatically mounted to /boot/ or /efi/,
               unless a different partition is mounted there (possibly via /etc/fstab) or
               the mount point directory is non-empty on the root disk.
               If both ESP and XBOOTLDR exist, the /efi/ mount point shall be used for ESP.
               This partition type is defined by the UEFI Specification.
           */
          type = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
          label = "ESP";
          content.type = "filesystem";
          content.format = "vfat";
          content.mountpoint = "/boot";
          content.mountOptions = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };
    }
    {
      # zpool config
      kdn.hardware.disks.zpools."${cfg.zpool-main.name}" = { };
    }
    {
      # system-wide disks
      disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
        "${hostname}/nix-system/nix-store" = {
          type = "zfs_fs";
          mountpoint = "/nix/store";
          options.mountpoint = "/nix/store";
        };
        "${hostname}/nix-system/nix-var" = {
          type = "zfs_fs";
          mountpoint = "/nix/var";
          options.mountpoint = "/nix/var";
        };
      };
    }
    {
      # impermanence config
      kdn.hardware.disks.impermanence = {
        "sys/config" = {
          snapshots = true;
          imp.directories = [
            "/var/db/sudo/lectured"
            "/var/lib/bluetooth"
            "/var/lib/nixos"
            "/var/lib/systemd/pstore"
            "/var/spool"
          ];
          imp.files = [
            "/etc/machine-id"
            "/etc/printcap" # CUPS printer config
            #"/etc/subgid" # this results in file already exists
            #"/etc/subuid" # this results in file already exists
          ];
        };
        "sys/cache" = {
          snapshots = false;
          imp.directories = [
            "/var/cache"
          ];
          imp.users.root.directories = [
            ".cache/nix"
          ];
        };
        "sys/data" = {
          snapshots = true;
        };
        "sys/state" = {
          snapshots = true;
          imp.directories = [
            "/var/lib/swtpm-localca"
          ];
          imp.files = [
            "/etc/ssh/ssh_host_ed25519_key"
            "/etc/ssh/ssh_host_ed25519_key.pub"
            "/etc/ssh/ssh_host_rsa_key"
            "/etc/ssh/ssh_host_rsa_key.pub"
          ];
        };
        "sys/log" = {
          snapshots = false;
          neededForBoot = [
            "/var/log/journal"
          ];
          imp.directories = [
            "/var/lib/systemd/coredump"
            "/var/log"
            "/var/log/journal"
          ];
        };
        "usr/config" = {
          snapshots = true;
          imp.files = [
            "/etc/nix/netrc" # TODO: move this out
            "/etc/nix/nix.sensitive.conf" # TODO: move this out
          ];
          imp.users.kdn = {
            # TODO: move this out
            directories = [
              ".config/syncthing"
            ];
            files = [
              { file = ".ssh/config.local"; parentDirectory.mode = "0700"; }
            ];
          };
        };
        "usr/cache" = {
          snapshots = false;
          # TODO: move this out
          imp.users.kdn.directories = [
            ".cache/appimage-run"
            ".cache/fontconfig"
          ];
        };
        "usr/data" = {
          snapshots = true;
          # TODO: move this out
          imp.directories = [
            "/var/lib/libvirt/images"
          ];
          /* TODO: implement automated atuin login:
               - store the data on a tmpfs mount under user's home (will require ~64MB+ space)
               - retrieve credentials from `sops-nix`
               - log in
               - run the first sync
           */
          imp.users.root.directories = [
            ".local/share/atuin"
          ];
          # TODO: move this out
          imp.users.kdn.directories = [
            ".local/share/syncthing"
            ".local/share/atuin"
            ".local/share/direnv"
            ".local/share/nix"
            ".local/share/containers"
            "dev"
          ];
        };
        "usr/state" = {
          snapshots = true;
          # TODO: move this out
          imp.directories = [
            "/var/lib/libvirt"
          ];
          # TODO: move this out
          imp.users.root.directories = [
            { directory = "wireguard-keys"; mode = "0700"; }
          ];
          # TODO: move this out
          imp.users.root.files = [
            { file = ".ssh/known_hosts"; parentDirectory.mode = "0700"; }
          ];
          # TODO: move this out
          imp.users.kdn.directories = [
            ".gnupg"
          ];
          # TODO: move this out
          imp.users.kdn.files = [
            { file = ".ssh/known_hosts"; parentDirectory.mode = "0700"; }
          ];
        };
        "usr/log" = {
          snapshots = false;
          # TODO: move this out
          imp.users.kdn.files = [
            ".local/share/fish/fish_history"
            ".ipython/profile_default/history.sqlite"
            ".bash_history"
            ".duckdb_history"
            ".python_history"
            ".usql_history"
            ".zsh_history"
          ];
        };
      };
    }
    {
      disko.devices.nodev = {
        "/" = {
          fsType = "tmpfs";
          mountOptions = [
            "size=${cfg.tmpfs.size}"
            "mode=755"
          ];
        };
        "/home" = {
          fsType = "tmpfs";
          mountOptions = [
            "size=${cfg.tmpfs.size}"
            "mode=755"
          ];
        };
      };

      # required for home.persistence.*.allowOther
      programs.fuse.userAllowOther = true;
    }
  ]);
}
