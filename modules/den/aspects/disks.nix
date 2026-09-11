# Impermanence on ZFS on LUKS, as a den aspect. It ports `modules/universal/disks/`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# The root filesystem is a tmpfs, so every boot starts clean. A ZFS pool on a LUKS volume with a
# detached header holds what the machine keeps, and `preservation` bind-mounts each kept path back.
# The aspect generates the whole disko layout from a short device description.
#
# ## Why the `nixos` class alone
#
# Every effect is a NixOS effect: disko devices, initrd services, `preservation` and tmpfiles. The
# old module declares its options in every context, but its whole `config` half sits behind
# `ifTypes [ "nixos" ]`.
#
# The user half arrives from the other side. `../common/persist.nix` declares `kdn.disks.persist`
# for a Home Manager scope too, and this aspect reads it back through
# `config.home-manager.users.<name>`. See `../aspects/disks-persist.nix`.
#
# ## What the port changes
#
# 1. **`kdn.disks.enable` is gone.** Inclusion is the switch. The whole `config` half now runs
#    unconditionally, so a host includes this aspect only when it wants impermanence.
# 2. **The `enable` mutual-exclusion assertion moves.** The old `enable` carried an `apply` that
#    refused `kdn.fs.disko.luks-zfs.enable` at the same time. `fs-luks-zfs` of ../aspects/fs.nix now
#    holds the reverse assertion, and it reads `options.kdn.disks ? base`.
# 3. **The Home Manager forward is gone.** The old module pushed `kdn.disks.enable` into
#    `home-manager.sharedModules`. den partitions an aspect by scope, so a user reaches its own half
#    through `disks-persist` instead.
# 4. **The per-user path defaults become an option.** The old module wrote `.cache/nix`,
#    `.local/share/nix`, `Downloads` and the four media directories into
#    `home-manager.sharedModules`. They now live in `kdn.disks.userDefaults.persist`, and every user
#    of `kdn.disks.users` gets them.
# 5. **Two forward writes are gone.** The old module set `kdn.fs.zfs.enable` and
#    `kdn.security.disk-encryption.enable` with `lib.mkDefault`. Neither option exists unless its own
#    aspect is included, so a host now includes `fs-zfs` beside this aspect. See "Open questions" of
#    the plan.
# 6. **`kdn.disks.disko.debug` is gone.** It was `readOnly`, it had no reader, and its default needed
#    the repository's own `pkgs.lib.disko` overlay. A drop-in consumer has no such overlay.
# 7. **The `kdn.hw.disks` rename shim is gone.** It served the old loader's migration only.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch. An `enable` inside an
#    `attrsOf submodule` is out of reach, so it is permitted.
# 3. **No custom module argument.** The target module below takes `config`, `lib`, `pkgs` and
#    `options` only. It builds NixOS `utils` from `inputs.nixpkgs` instead of taking the `utils`
#    argument, so it also resolves in a plain `lib.evalModules`.
{ inputs, ... }:
{
  kdn.disks.nixos =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.kdn.disks;
      hostname = config.kdn.hostName;

      # `utils.escapeSystemdPath` names a systemd unit for a LUKS volume. A NixOS evaluation passes
      # `utils` as a module argument, but a plain `lib.evalModules` does not. So build it here from
      # the same source file, and keep the target module free of a custom argument.
      utils = import (inputs.nixpkgs + "/nixos/lib/utils.nix") { inherit lib config pkgs; };

      # Home Manager reaches this host only when a user aspect wires it. A bare consumer has no
      # `home-manager` option at all, so `or { }` keeps the aspect standalone.
      hmUsers = config.home-manager.users or { };

      # The layout gate. The ESP block below always writes `kdn.disks.devices.<bootDeviceName>`, so
      # an empty attribute set cannot be the test. A device with no `path` is the test.
      #
      # A consumer that includes the aspect and names no device path still gets the whole
      # `kdn.disks` model, the eleven persist buckets and preservation. It gets no disko layout and
      # no `fileSystems` entry, so it evaluates. `den-eval-instantiate` in
      # ../../../checks/den-mvp/tests.nix forces every class of every registry aspect with no
      # consumer data at all, and this gate is what lets that force pass.
      #
      # A consumer that names one path and forgets another gets the assertion below. The old module
      # stopped with `The option 'kdn.disks.devices.boot.path' was accessed but has no value
      # defined` instead. Measured 2026-09-11.
      pathless = builtins.attrNames (lib.filterAttrs (_: device: device.path == null) cfg.devices);
      hasLayout = cfg.devices != { } && pathless == [ ];

      partSizeType =
        with lib.types;
        oneOf [
          str
          ints.positive
        ];

      deviceType = lib.types.submodule (
        { name, ... }@disk:
        {
          options.type = lib.mkOption {
            type = lib.types.enum [
              "gpt"
              "luks"
            ];
            default = "gpt";
          };
          options.path = lib.mkOption {
            type = with lib.types; nullOr path;
            default = null;
            description = ''
              The device path. `null` means the consumer named no device yet, so this aspect writes
              no disko layout at all. See the layout gate in the header.
            '';
          };
          options.disko = lib.mkOption {
            default = { };
          };
          options.partitions = lib.mkOption {
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }@part:
                {
                  options.num = lib.mkOption {
                    type = lib.types.ints.between 1 128;
                  };
                  options.path = lib.mkOption {
                    internal = true;
                    type = lib.types.path;
                    default =
                      let
                        _path = disk.config.path;
                        partNum = toString part.config.num;
                      in
                      if lib.strings.hasPrefix "/dev/disk/" _path then
                        "${_path}-part${partNum}"
                      else if (builtins.match "/dev/[^/]+" _path) != null then
                        "${_path}${partNum}"
                      else
                        throw "Don't know how to generate partition number for disk ${_path}";
                  };
                  options.size = lib.mkOption {
                    type = partSizeType;
                  };
                  options.disko = lib.mkOption {
                    default = { };
                  };
                }
              )
            );
          };
        }
      );

      deviceSelectorType = lib.types.submodule (
        {
          name,
          config,
          ...
        }@partSel:
        {
          options.deviceKey = lib.mkOption {
            type = with lib.types; nullOr str;
          };
          options.partitionKey = lib.mkOption {
            type = with lib.types; nullOr str;
            default = null;
          };
          options.device = lib.mkOption {
            type = deviceType;
            internal = true;
            default =
              let
                key = partSel.config.deviceKey;
              in
              cfg.devices."${key}";
          };
          options.partition = lib.mkOption {
            type = with lib.types; anything;
            default =
              with partSel.config;
              if partitionKey == null then { } else device.partitions."${partitionKey}";
          };
          options.path = lib.mkOption {
            internal = true;
            type = lib.types.path;
            default =
              if partSel.config.partition == { } then
                partSel.config.device.path
              else
                partSel.config.partition.path;
          };
        }
      );

      # One per-user path list, from three sources: this aspect's own defaults, the user's own Home
      # Manager config, and a per-user entry the host wrote by hand.
      userPathType = lib.types.listOf (
        lib.types.either lib.types.str (
          lib.types.submodule { freeformType = (pkgs.formats.json { }).type; }
        )
      );
    in
    {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.preservation.nixosModules.preservation
        ../common/host-name.nix
        ../common/persist.nix
      ];

      options.kdn.disks.nixBuildDir.type = lib.mkOption {
        type = lib.types.enum [
          "disposable"
          "tmpfs"
          "zfs-dataset"
        ];
        default = "disposable";
        description = "Where the Nix build directory lives.";
      };
      options.kdn.disks.nixBuildDir.tmpfs.size = lib.mkOption {
        type = lib.types.str;
        default = "2G";
        description = "Size of the build tmpfs, when `nixBuildDir.type` is `tmpfs`.";
      };

      options.kdn.disks.users = lib.mkOption {
        default = { };
        description = ''
          One entry per user whose home directory this machine manages. The old tree filled this
          from `home-manager.users`, and this aspect still does that. Add an entry to reach a user
          with no Home Manager config.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@userArgs:
            {
              options.homeLocation = lib.mkOption {
                type = lib.types.enum (builtins.attrNames cfg.base);
                default = cfg.userDefaults.homeLocation;
                description = "Which `kdn.disks.base` bucket holds this user's home directory.";
              };
              options.homeDirMode = lib.mkOption {
                type = with lib.types; str;
                default = cfg.userDefaults.homeDirMode;
                description = "Mode of every directory this aspect creates under the home directory.";
              };
              options.homeFileMode = lib.mkOption {
                type = with lib.types; str;
                default = cfg.userDefaults.homeFileMode;
                description = "Mode of every file this aspect preserves under the home directory.";
              };
            }
          )
        );
      };

      options.kdn.disks.userDefaults.homeLocation = lib.mkOption {
        type = lib.types.enum (builtins.attrNames cfg.base);
        description = "Which `kdn.disks.base` bucket a user's home directory comes from.";
      };
      options.kdn.disks.userDefaults.homeFileMode = lib.mkOption {
        type = with lib.types; str;
        default = "0640";
        description = "Default mode of a preserved file under a home directory.";
      };
      options.kdn.disks.userDefaults.homeDirMode = lib.mkOption {
        type = with lib.types; str;
        default = "0750";
        description = "Default mode of a created directory under a home directory.";
      };

      options.kdn.disks.userDefaults.persist = lib.mkOption {
        default = { };
        description = ''
          Paths every user of `kdn.disks.users` keeps, grouped by bucket and relative to the home
          directory. The old tree wrote these through `home-manager.sharedModules`, which den has
          no route for.
        '';
        example = lib.literalExpression ''
          {
            "usr/data".directories = [ "Documents" ];
          }
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.directories = lib.mkOption {
              type = userPathType;
              default = [ ];
              description = "Directories every user keeps, relative to the home directory.";
            };
            options.files = lib.mkOption {
              type = userPathType;
              default = [ ];
              description = "Single files every user keeps, relative to the home directory.";
            };
          }
        );
      };

      options.kdn.disks.defaults.mountPrefix = lib.mkOption {
        type = with lib.types; path;
        default = "/nix/persist";
        description = "Where every `kdn.disks.base` bucket mounts.";
      };
      options.kdn.disks.defaults.bootDeviceName = lib.mkOption {
        type = with lib.types; str;
        default = "boot";
        description = "The `kdn.disks.devices` key that holds the ESP and the LUKS headers.";
      };

      options.kdn.disks.disposable.zfsName = lib.mkOption {
        type = with lib.types; str;
        default = "disposable";
        description = "ZFS dataset name of the bucket that rolls back on every boot.";
      };

      options.kdn.disks.luks.header.size = lib.mkOption {
        type = partSizeType;
        # https://wiki.archlinux.org/title/Dm-crypt/Device_encryption#Encrypt_an_existing_unencrypted_file_system
        # suggests 32 MiB, which is twice the 16 MiB header size.
        default = 32;
        description = "Size of a detached LUKS header partition, in MiB when it is a number.";
      };

      options.kdn.disks.tmpfs.size = lib.mkOption {
        type = lib.types.str;
        default = "16M";
        description = "Size of the `/` and `/home` tmpfs mounts.";
      };

      options.kdn.disks.zpool-main.name = lib.mkOption {
        type = lib.types.str;
        default = "${config.kdn.hostName}-main";
        defaultText = lib.literalExpression ''"''${config.kdn.hostName}-main"'';
        description = "Name of the pool that holds every bucket by default.";
      };
      options.kdn.disks.initrd.failureTarget = lib.mkOption {
        type = lib.types.str;
        default = "emergency.target";
        description = "Where the initrd goes when a pool import or an unlock fails.";
      };

      options.kdn.disks.devices = lib.mkOption {
        type = lib.types.attrsOf deviceType;
        default = { };
        description = "The physical devices and the partitions this aspect writes to disko.";
      };

      options.kdn.disks.luks.volumes = lib.mkOption {
        default = { };
        description = "One entry per LUKS volume, each with a detached header.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@luksVol:
            {
              options.target = lib.mkOption {
                type = deviceSelectorType;
              };
              options.targetSpec.path = lib.mkOption {
                type = with lib.types; nullOr path;
                default = luksVol.config.target.partition.path;
              };
              options.targetSpec.partNum = lib.mkOption {
                type = lib.types.ints.between 1 128;
              };
              options.targetSpec.size = lib.mkOption {
                type = partSizeType;
              };
              options.uuid = lib.mkOption {
                type = lib.types.str;
              };
              options.keyFile = lib.mkOption {
                type = with lib.types; nullOr str;
                # A `settings.keyFile` of disko lands in the systemd unit, which stops TPM2 and
                # YubiKey unlock from working. So this value stays out of `settings`.
                default = "/tmp/${luksVol.name}.key";
              };
              options.header = lib.mkOption {
                type = deviceSelectorType;
              };
              options.headerSpec.partNum = lib.mkOption {
                type = lib.types.ints.between 1 128;
              };
              options.name = lib.mkOption {
                type = lib.types.str;
                default = "${luksVol.name}-crypted";
              };
              options.disko = lib.mkOption {
                default = { };
              };
              options.zpool.name = lib.mkOption {
                type = with lib.types; nullOr str;
                default = cfg.zpool-main.name;
              };
              config = {
                target.deviceKey = lib.mkDefault luksVol.name;
                target.partitionKey = lib.mkDefault null;
                header.deviceKey = lib.mkDefault cfg.defaults.bootDeviceName;
                header.partitionKey = lib.mkDefault "${luksVol.name}-header";
              };
            }
          )
        );
      };

      options.kdn.disks.zpools = lib.mkOption {
        default = { };
        description = "One entry per ZFS pool this aspect writes to disko.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@zpool:
            {
              options.disko = lib.mkOption {
                default = { };
              };
              options.import.timeout = lib.mkOption {
                type = with lib.types; int;
                default = 15;
              };
              options.cryptsetup.requires = lib.mkOption {
                type = with lib.types; listOf str;
                default = [ ];
              };
              options.cryptsetup.names = lib.mkOption {
                type = with lib.types; listOf str;
                default = lib.trivial.pipe cfg.luks.volumes [
                  (lib.filterAttrs (luksVolName: luksVol: luksVol.zpool.name == zpool.name))
                  (builtins.mapAttrs (luksVolName: luksVol: luksVol.name))
                  builtins.attrValues
                  (map (luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}"))
                ];
              };
              options.cryptsetup.services = lib.mkOption {
                type = with lib.types; listOf str;
                default = map (name: "${name}.service") zpool.config.cryptsetup.names;
              };
              options.initrd.failureTarget = lib.mkOption {
                type = with lib.types; str;
                default = cfg.initrd.failureTarget;
              };
            }
          )
        );
      };

      options.kdn.disks.base = lib.mkOption {
        default = { };
        description = "One entry per persistence bucket. Each one is a ZFS dataset with a mountpoint.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@baseArgs:
            let
              baseCfg = baseArgs.config;
            in
            {
              options.neededForBoot = lib.mkOption {
                type = with lib.types; listOf path;
                default = [ ];
                apply = ls: [ "${baseCfg.mountpoint}" ] ++ ls;
              };
              options.mountpoint = lib.mkOption {
                type = with lib.types; str;
                default = "${baseCfg.mountPrefix}/${baseArgs.name}";
              };
              options.mountPrefix = lib.mkOption {
                type = with lib.types; str;
                default = cfg.defaults.mountPrefix;
              };
              options.zfsName = lib.mkOption {
                type = with lib.types; str;
                default = baseArgs.name;
              };
              options.zfsPrefix = lib.mkOption {
                type = with lib.types; str;
                default = "${config.kdn.hostName}/impermanence";
              };
              options.zfsPath = lib.mkOption {
                type = with lib.types; str;
                default = "${baseCfg.zfsPrefix}/${baseCfg.zfsName}";
              };
              options.zpool.name = lib.mkOption {
                type = with lib.types; nullOr str;
                default = cfg.zpool-main.name;
              };
              options.snapshots = lib.mkOption {
                type = with lib.types; bool;
              };
              options.disko = lib.mkOption {
                default = { };
              };
            }
          )
        );
      };

      options.kdn.disks.disko.devices._meta = lib.mkOption {
        type = (pkgs.formats.json { }).type;
        default = { };
        description = "The disko `_meta` block this aspect forwards to `disko.devices._meta`.";
      };

      config = lib.mkMerge [
        {
          kdn.disks.base."sys/cache".snapshots = false;
          kdn.disks.base."sys/config".snapshots = true;
          kdn.disks.base."sys/data".snapshots = true;
          kdn.disks.base."sys/reproducible".snapshots = false;
          kdn.disks.base."sys/state".snapshots = false;
          kdn.disks.base."usr/cache".snapshots = false;
          kdn.disks.base."usr/config".snapshots = true;
          kdn.disks.base."usr/data".snapshots = true;
          kdn.disks.base."usr/reproducible".snapshots = false;
          kdn.disks.base."usr/state".snapshots = false;
          kdn.disks.userDefaults.homeLocation = lib.mkDefault "disposable";
        }
        {
          assertions = [
            {
              assertion = pathless == [ ] || pathless == builtins.attrNames cfg.devices;
              message = ''
                den: the `disks` aspect needs a path for every device of `kdn.disks.devices`.

                These devices hold none: ${builtins.concatStringsSep ", " pathless}.

                Name a path for every device, or name no path at all. With no path at all the aspect
                writes no disko layout.
              '';
            }
          ];
        }
        {
          # Basic /boot config
          fileSystems = lib.mkIf hasLayout { "/boot".neededForBoot = true; };
          kdn.disks.devices."${cfg.defaults.bootDeviceName}" = {
            type = "gpt";
            partitions."ESP" = {
              num = 1;
              size = 4096;
              disko = {
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
          };
        }
        {
          kdn.disks.zpools."${cfg.zpool-main.name}" = { };
        }
        {
          disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
            "${hostname}/nix-system/nix-store" = {
              type = "zfs_fs";
              mountpoint = "/nix/store";
              options.mountpoint = "/nix/store";
              options.atime = "off";
            };
            "${hostname}/nix-system/nix-var" = {
              type = "zfs_fs";
              mountpoint = "/nix/var";
              options.mountpoint = "/nix/var";
            };
          };
        }
        {
          kdn.disks.persist."sys/data" = {
            directories = [
              "/var/lib/systemd"
              {
                directory = "/var/lib/private";
                mode = "0700";
              }
            ];
            files = [
              {
                file = "/etc/ssh/ssh_host_ed25519_key";
                how = "symlink";
                mode = "0600";
                inInitrd = true;
              }
              {
                file = "/etc/ssh/ssh_host_rsa_key";
                how = "symlink";
                mode = "0600";
                inInitrd = true;
              }
            ];
          };
          kdn.disks.persist."sys/config" = {
            directories = [
              "/var/db/sudo/lectured"
              "/var/lib/nixos"
              "/var/lib/systemd/pstore"
              "/var/spool"
            ];
            files = [
              "/etc/printcap"
            ];
          };
        }
        {
          kdn.disks.persist."sys/config".files = [
            {
              file = "/etc/machine-id";
              inInitrd = true;
              configureParent = true;
            }
          ];
          systemd.services.systemd-machine-id-commit.unitConfig.ConditionFirstBoot = true;
        }
        {
          boot.initrd.systemd.services.systemd-journal-flush.serviceConfig.TimeoutSec = "10s";
        }
        {
          kdn.disks.persist."sys/cache".directories = [
            "/var/cache"
          ];
          kdn.disks.userDefaults.persist."sys/cache".directories = [ ".cache/nix" ];
        }
        {
          kdn.disks.persist."sys/state".directories = [
            "/var/lib/systemd/coredump"
            "/var/log"
            {
              directory = "/var/log/journal";
              inInitrd = true;
            }
          ];
        }
        {
          kdn.disks.persist."usr/config".files = [
            "/etc/nix/netrc"
            "/etc/nix/nix.sensitive.conf"
          ];
          kdn.disks.userDefaults.persist."usr/data".directories = [ ".local/share/nix" ];
        }
        {
          kdn.disks.userDefaults.persist."usr/cache".directories = [
            "Downloads"
          ];
          kdn.disks.userDefaults.persist."usr/data".directories = [
            "Documents"
            "Desktop"
            "Pictures"
            "Videos"
          ];
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
        }
        # WARNING: keep the build directory in step with the `nix-config` aspect.
        {
          systemd.tmpfiles.rules = [
            "L+ /nix/var/nix/builds           - - - - /nix/var/nix/builds-${cfg.nixBuildDir.type}"
          ];
          kdn.disks.persist."disposable".directories = [
            {
              directory = "/nix/var/nix/builds-disposable";
              mode = "0755";
            }
          ];
          disko.devices.nodev."/nix/var/nix/builds-tmpfs" = {
            fsType = "tmpfs";
            mountOptions = [
              "size=${cfg.nixBuildDir.tmpfs.size}"
              "mode=755"
            ];
          };
          disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
            "${hostname}/nix-system/nix-builds" = {
              type = "zfs_fs";
              mountpoint = "/nix/var/nix/builds-zfs-dataset";
              options.mountpoint = "/nix/var/nix/builds-zfs-dataset";
              options."com.sun:auto-snapshot" = "false";
              options.compression = "off";
              options.atime = "off";
              options.redundant_metadata = "none";
              options.sync = "disabled";
            };
          };
        }
        {
          # required for kdn.disks.base.*.allowOther
          programs.fuse.userAllowOther = true;
        }
        {
          kdn.disks.disko.devices._meta = options.disko.devices.valueMeta.configuration.options._meta.default;
          disko.devices._meta = config.kdn.disks.disko.devices._meta;
        }

        # ------------------------------------------------------------ preservation
        {
          preservation.enable = lib.mkDefault true;
          kdn.disks.persist = lib.pipe cfg.base [
            (builtins.mapAttrs (_: _: { }))
          ];
          preservation.preserveAt = lib.pipe cfg.base [
            (builtins.mapAttrs (
              persistName: baseCfg:
              let
                persists = cfg.persist."${persistName}";
              in
              {
                commonMountOptions = [
                  "x-gvfs-hide" # hide the mounts by default
                  "x-gdu.hide" # hide the mounts by default
                ];
                persistentStoragePath = baseCfg.mountpoint;
                inherit (persists) directories files;
                users = builtins.mapAttrs (
                  username: hmConfig:
                  let
                    homeDirMode = (cfg.users."${username}" or cfg.userDefaults).homeDirMode;
                    homeFileMode = (cfg.users."${username}" or cfg.userDefaults).homeFileMode;
                    process =
                      topName: childName: mode:
                      lib.pipe
                        [
                          (cfg.userDefaults.persist."${persistName}" or { })
                          (hmConfig.kdn.disks.persist."${persistName}" or { })
                          (persists.users."${username}" or { })
                        ]
                        [
                          (builtins.catAttrs topName)
                          builtins.concatLists
                          (map (
                            c:
                            let
                              d = if builtins.typeOf c == "string" then { "${childName}" = c; } else c;
                            in
                            {
                              inherit mode;
                            }
                            // d
                            // {
                              parent = {
                                mode = homeDirMode;
                              }
                              // (d.parent or { });
                            }
                          ))
                        ];
                  in
                  {
                    files = process "files" "file" homeFileMode;
                    directories = process "directories" "directory" homeDirMode;
                  }
                ) hmUsers;
              }
            ))
          ];
        }

        # ------------------------------------------------------------ LUKS device generation
        {
          # whole-disk LUKS handling
          kdn.disks.devices = lib.pipe cfg.luks.volumes [
            builtins.attrValues
            (builtins.filter (luksVol: luksVol.target.partitionKey == null))
            (map (luksVol: {
              "${luksVol.target.deviceKey}" = {
                type = "luks";
                path = lib.mkDefault luksVol.targetSpec.path;
              };
            }))
            lib.mkMerge
          ];
        }
        {
          # partition-based LUKS handling
          kdn.disks.devices = lib.pipe cfg.luks.volumes [
            builtins.attrValues
            (builtins.filter (luksVol: luksVol.target.partitionKey != null))
            (map (luksVol: {
              "${luksVol.target.deviceKey}".partitions."${luksVol.target.partitionKey}" = {
                num = luksVol.targetSpec.partNum;
                size = luksVol.targetSpec.size;
                disko.type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
                disko.label = luksVol.target.partitionKey;
              };
            }))
            lib.mkMerge
          ];
        }
        {
          # LUKS header partitions
          kdn.disks.devices = lib.pipe cfg.luks.volumes [
            builtins.attrValues
            (builtins.filter (luksVol: luksVol.header.deviceKey != null && luksVol.header.partitionKey != null))
            (map (luksVol: {
              "${luksVol.header.deviceKey}".partitions."${luksVol.header.partitionKey}" = {
                num = luksVol.headerSpec.partNum;
                inherit (cfg.luks.header) size;
                # https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
                # names `0fc63daf-8483-4772-8e79-3d69d8477de4` the generic Linux data partition. It
                # carries any native filesystem, and it takes no automatic mount.
                disko.type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
                disko.label = luksVol.header.partitionKey;
              };
            }))
            lib.mkMerge
          ];
        }

        # ------------------------------------------------------------ users
        {
          kdn.disks.users = builtins.mapAttrs (_: _: { }) hmUsers;
          systemd.services = lib.pipe hmUsers [
            # see https://github.com/nix-community/home-manager/blob/master/nixos/default.nix
            (lib.attrsets.mapAttrs' (
              _: hmConfig: {
                name = "home-manager-${hmConfig.home.username}";
                value.after = [ "preservation.target" ];
                value.requires = [ "preservation.target" ];
              }
            ))
          ];
        }

        # ------------------------------------------------------------ the disposable bucket
        (
          let
            baseCfg = cfg.base."disposable";
            snapshotName = "${baseCfg.zpool.name}/${baseCfg.zfsPath}@empty";
            scriptDeps = [ config.boot.zfs.package ];
          in
          {
            # To migrate a live system, rename the dataset, create a fresh one at the same
            # mountpoint, run `nixos-rebuild boot`, reboot, then destroy the old dataset.
            kdn.disks.base."disposable".snapshots = false;
            kdn.disks.base."disposable".zfsName = cfg.disposable.zfsName;
            # this does not always work
            kdn.disks.base."disposable".disko.postCreateHook = ''
              if ! zfs get type "${snapshotName}" >/dev/null 2>&1; then
                zfs snapshot "${snapshotName}"
              fi
            '';
            kdn.disks.persist."disposable".directories = [
              {
                directory = "/var/tmp";
                mode = "0777";
              }
            ];
            boot.initrd.systemd.initrdBin = scriptDeps;
            boot.initrd.systemd.services."kdn-disks-disposable-rollback" = {
              description = "rollbacks `disposable` filesystem to empty state";
              after = [ "zfs-import-${baseCfg.zpool.name}.service" ];
              requiredBy = [ "zfs-import-${baseCfg.zpool.name}.service" ];
              wantedBy = [ "sysroot-nix-persist-disposable.mount" ];
              before = [ "sysroot-nix-persist-disposable.mount" ];
              onFailure = [ "rescue.target" ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                RestartSec = "3";
                Restart = "on-failure";
              };
              unitConfig.DefaultDependencies = false;
              unitConfig.StartLimitInterval = 60;
              unitConfig.StartLimitBurst = 3;
              script = ''
                if ! zfs rollback -r "${snapshotName}"; then
                  test -d /sysroot/nix/persist/disposable
                  rm -rf /sysroot/nix/persist/disposable/*
                  zfs snapshot "${snapshotName}"
                fi
              '';
            };
          }
        )

        # ------------------------------------------------------------ tmpfiles
        { systemd.tmpfiles.settings.preservation = { }; }
        {
          # $HOME directories creation
          preservation.preserveAt = lib.pipe cfg.users [
            (lib.attrsets.mapAttrsToList (
              username: userCfg:
              let
                sysUser = config.users.users."${username}";
              in
              {
                "${userCfg.homeLocation}".directories = [
                  {
                    directory = sysUser.home;
                    user = sysUser.name;
                    group = sysUser.group;
                    # `preservation` emits a rule for this exact path as well. Its
                    # `intermediateHomeRules` reads the readOnly `homeMode`, which follows
                    # `users.users.<name>.homeMode`. That rule appears for every user with a
                    # non-empty preserved entry at this same location. Two values of one tmpfiles
                    # `d.mode` stop the evaluation with `conflicting definition values`. So this
                    # entry reads the same source, and one value governs the home directory.
                    #
                    # Measured 2026-09-10: a user with a home bucket that also holds a preserved
                    # entry meets both rules. A user whose home sits in `disposable` with no
                    # preserved entry there never showed the conflict.
                    #
                    # `homeMode` is "700" -- the nixpkgs default. `userCfg.homeDirMode` is "0750".
                    # TODO: decide which mode a home directory takes. To make "0750" the one value,
                    # set `users.users.<name>.homeMode` from `homeDirMode` instead. That loosens
                    # every real home directory, so it needs a decision, not a silent change.
                    mode = sysUser.homeMode;
                  }
                ];
              }
            ))
            lib.mkMerge
          ];

          # fixup all in-between home subdirectory permissions
          # feature request: https://github.com/nix-community/preservation/issues/9
          systemd.tmpfiles.settings.zzz-kdn-preservation-users = lib.pipe config.preservation.preserveAt [
            (lib.attrsets.mapAttrsToList (
              _: preserveAtCfg:
              lib.pipe preserveAtCfg.users [
                (lib.attrsets.mapAttrsToList (
                  _: preserveAtUserCfg:
                  let
                    inherit (preserveAtUserCfg) username;
                    persistUserCfg = cfg.users."${username}";
                    splitHome = lib.strings.splitString "/" preserveAtUserCfg.home;
                    splitHomeLen = builtins.length splitHome;

                    parentDirs =
                      lib.pipe preserveAtUserCfg.files [
                        (map (f: builtins.dirOf f.file))
                      ]
                      ++ lib.pipe preserveAtUserCfg.directories [
                        (map (f: builtins.dirOf f.directory))
                      ];

                    missingDirs = lib.pipe parentDirs [
                      (map (
                        dir:
                        lib.pipe dir [
                          (lib.strings.splitString "/")
                          (
                            pieces:
                            builtins.genList (
                              i:
                              lib.pipe pieces [
                                (lib.lists.sublist 0 (splitHomeLen + i + 1))
                                (builtins.concatStringsSep "/")
                              ]
                            ) (builtins.length pieces - splitHomeLen)
                          )
                        ]
                      ))
                      lib.lists.flatten
                      (map (
                        dir:
                        let
                          conf = {
                            mode = persistUserCfg.homeDirMode;
                            user = username;
                            group = config.users.users."${username}".group;
                          };
                        in
                        {
                          "${preserveAtCfg.persistentStoragePath}${dir}".d = conf;
                          "${dir}".d = conf;
                        }
                      ))
                    ];
                  in
                  missingDirs
                ))
              ]
            ))
            lib.lists.flatten
            lib.lists.unique
            lib.mkMerge
          ];
        }
        {
          # fix up missing mkdirs on non-user parents
          systemd.tmpfiles.settings.zzz-kdn-preservation-system = lib.pipe config.preservation.preserveAt [
            (lib.attrsets.mapAttrsToList (
              _: preserveAtCfg:
              let
                parentDirs =
                  lib.pipe preserveAtCfg.files [
                    (map (f: {
                      path = builtins.dirOf f.file;
                      conf = f.parent;
                    }))
                  ]
                  ++ lib.pipe preserveAtCfg.directories [
                    (map (f: {
                      path = builtins.dirOf f.directory;
                      conf = f.parent;
                    }))
                  ];

                # TODO: drop the entries `systemd.tmpfiles.settings.preservation` already holds.
                missingDirs = lib.pipe parentDirs [
                  (builtins.filter (entry: entry.path != "" && entry.path != "/"))
                  (map (
                    entry:
                    lib.flip builtins.map
                      [
                        "${preserveAtCfg.persistentStoragePath}${entry.path}"
                        "${entry.path}"
                      ]
                      (key: {
                        "${key}".d = entry.conf;
                      })
                  ))
                ];
              in
              missingDirs
            ))
            lib.lists.flatten
            lib.lists.unique
            lib.mkMerge
          ];
        }

        # ------------------------------------------------------------ disko generation
        {
          # prepare LUKS volumes
          disko.devices.disk = lib.pipe cfg.luks.volumes [
            (builtins.mapAttrs (
              name: luksVol: {
                type = "disk";
                device = luksVol.target.path;
                content = lib.mkMerge [
                  {
                    type = "luks";
                    name = luksVol.name;
                    settings.header = luksVol.header.path;
                    askPassword = lib.mkDefault luksVol.keyFile == null;
                    extraFormatArgs = [
                      "--uuid=${luksVol.uuid}"
                      "--header=${luksVol.header.path}"
                    ]
                    ++ lib.lists.optional (luksVol.keyFile != null) "--key-file=${luksVol.keyFile}";
                    extraOpenArgs = [
                      "--header=${luksVol.header.path}"
                    ]
                    ++ lib.lists.optional (luksVol.keyFile != null) "--key-file=${luksVol.keyFile}";
                    content = lib.mkIf (luksVol.zpool.name != null) {
                      type = "zfs";
                      pool = luksVol.zpool.name;
                    };
                  }
                  luksVol.disko
                ];
              }
            ))
          ];
        }
        {
          # prepare GPT disks
          disko.devices.disk = lib.pipe cfg.devices [
            (lib.attrsets.filterAttrs (name: disk: disk.type == "gpt"))
            (builtins.mapAttrs (
              name: disk:
              lib.mkMerge [
                {
                  type = "disk";
                  device = disk.path;
                  content.type = "gpt";
                  content.partitions = lib.pipe disk.partitions [
                    (builtins.mapAttrs (
                      name: part:
                      lib.mkMerge [
                        {
                          priority = part.num;
                          device = part.path;
                          alignment =
                            1
                            * 1024 # MiB
                            * 1024 # KiB
                            / 2048
                          # sgdisk sector size
                          ;
                          # `M` equals `MiB` in sgdisk and in disko, and disko validates `M`.
                          size = if builtins.isString part.size then part.size else "${toString part.size}M";
                        }
                        part.disko
                      ]
                    ))
                  ];
                }
                disk.disko
              ]
            ))
          ];
        }
        {
          disko.devices.zpool = lib.pipe cfg.zpools [
            (builtins.mapAttrs (
              name: zpool:
              lib.mkMerge [
                {
                  type = "zpool";
                  name = name;
                  mode =
                    let
                      volCount = lib.pipe cfg.luks.volumes [
                        builtins.attrValues
                        (builtins.filter (luksVol: luksVol.zpool.name == name))
                        builtins.length
                      ];
                    in
                    if volCount > 1 then "mirror" else "";
                  rootFsOptions = lib.attrsets.mapAttrs (_: lib.mkDefault) {
                    acltype = "posixacl";
                    relatime = "on";
                    xattr = "sa";
                    dnodesize = "auto";
                    normalization = "formD";
                    mountpoint = "none";
                    canmount = "off";
                    devices = "off";
                    compression = "lz4";
                    "com.sun:auto-snapshot" = "false";
                  };
                  options = lib.attrsets.mapAttrs (_: lib.mkDefault) {
                    ashift = "12";
                    autotrim = "on";
                    "feature@large_dnode" = "enabled"; # required by dnodesize!=legacy
                  };
                }
                zpool.disko
              ]
            ))
          ];
        }
        {
          fileSystems = lib.mkIf hasLayout (
            lib.pipe cfg.base [
              builtins.attrValues
              (map (imp: imp.neededForBoot))
              lib.lists.flatten
              lib.unique
              (map (path: {
                name = path;
                value = {
                  neededForBoot = true;
                };
              }))
              builtins.listToAttrs
            ]
          );
          disko.devices.zpool = lib.pipe cfg.base [
            (builtins.mapAttrs (
              name: imp: {
                "${imp.zpool.name}".datasets."${imp.zfsPath}" = lib.mkMerge [
                  {
                    type = "zfs_fs";
                    inherit (imp) mountpoint;
                    options = {
                      inherit (imp) mountpoint;
                      "com.sun:auto-snapshot" = builtins.toJSON imp.snapshots;
                    };
                  }
                  imp.disko
                ];
              }
            ))
            builtins.attrValues
            lib.mkMerge
          ];
        }
        {
          # unlocking zpools in proper order
          boot.zfs.forceImportRoot = false;
          boot.zfs.extraPools = builtins.attrNames cfg.zpools;
          boot.initrd.systemd.services = lib.pipe cfg.zpools [
            (lib.attrsets.mapAttrsToList (
              name: zpool:
              let
                isRootPool = fs: fs.neededForBoot && fs.fsType == "zfs" && lib.strings.hasPrefix name fs.device;
                hasInitrdImport = builtins.any isRootPool config.system.build.fileSystems;
              in
              (lib.optional hasInitrdImport {
                "zfs-import-${name}" = {
                  requires = zpool.cryptsetup.services;
                  after = zpool.cryptsetup.services;
                  requiredBy = [ "initrd-fs.target" ];
                  onFailure = [ zpool.initrd.failureTarget ];
                  serviceConfig.TimeoutSec = zpool.import.timeout;
                };
              })
              ++ lib.pipe zpool.cryptsetup.names [
                (map (cryptsetupName: {
                  "${cryptsetupName}" = {
                    overrideStrategy = "asDropin";
                    requires = zpool.cryptsetup.requires;
                    after = zpool.cryptsetup.requires;
                    # TODO: replace `systemd-udev-settle.service` with a device unit dependency.
                    wants = [ "systemd-udev-settle.service" ];
                    onFailure = [ zpool.initrd.failureTarget ];
                    serviceConfig.TimeoutSec = zpool.import.timeout;
                  };
                }))
              ]
            ))
            lib.lists.flatten
            lib.mkMerge
          ];
        }
        {
          # enables systemd-cryptsetup-generator
          # see the `forceLuksSupportInInitrd` block of nixpkgs' luksroot.nix
          boot.initrd.luks.forceLuksSupportInInitrd = true;
          boot.initrd.systemd.enable = true;

          # `false` keeps disko quiet: it then writes no `fileSystems` and no `boot` entry. See the
          # layout gate at the top of this target module.
          disko.enableConfig = hasLayout;
          boot.zfs.requestEncryptionCredentials = false;
        }
      ];
    };
}
