# Filesystem aspects. This file ports the three modules of the old `fs` area:
#
#   * `fs-zfs`       -- ZFS support, the kernel choice, the scrub and the snapshot timers.
#   * `fs-watch`     -- one systemd service per filesystem watcher.
#   * `fs-luks-zfs`  -- the small ZFS-on-LUKS wiring for a host that writes its own disko layout.
#
# The old modules stay in place and keep working. This file is the parallel den implementation.
#
# One file holds three aspects. den reads each `kdn.<name>.<class>` key of the returned attribute
# set, so a file may carry as many aspects as it wants. `../lib.nix` maps all three names to this
# one path.
#
# ## Why the `nixos` class alone
#
# Every effect is a NixOS effect: a kernel package, a systemd service, a disko flag. The old modules
# declare their options in every context, and every `config` half sits behind `ifTypes [ "nixos" ]`.
#
# ## What the port changes
#
# 1. **Every `enable` option is gone.** Inclusion is the switch:
#    - `kdn.fs.zfs.enable` counted the ZFS entries of `fileSystems`. A host now includes `fs-zfs`.
#    - `kdn.fs.watch.enable` followed `instances != { }`. The list of instances is now the gate, so
#      an included aspect with no instance emits nothing.
#    - `kdn.fs.disko.luks-zfs.enable` was a plain `mkEnableOption`. `luksNames != [ ]` is now the
#      gate, which is the same test the old hard `assert` made.
#    The per-instance `kdn.fs.watch.instances.<name>.enable` stays. `checks/standalone.nix` stops at
#    an `attrsOf submodule`, so that flag is out of reach, and it is the point of the option.
# 2. **`kdn.env.packages` does not survive.** A den target names its class, so `fs-zfs` writes
#    `environment.systemPackages` directly.
# 3. **`fs-luks-zfs` no longer asserts inside an option default.** The old `luksNames` default ended
#    with `assert lib.assertMsg (v != [ ])`, so a host with no matching disko layout stopped the
#    evaluation. An aspect must stay quiet when a consumer includes it and writes nothing, so the
#    empty list is now legal and it turns the config half off.
# 4. **`fs-luks-zfs` no longer writes `kdn.fs.zfs.enable`.** That option does not exist unless
#    `fs-zfs` is included, so a host includes both.
# 5. **`fs-luks-zfs` builds NixOS `utils` from `inputs.nixpkgs`.** The old module took a `utils ?
#    null` module argument. Rule 3 below permits no custom argument.
# 6. **The mutual exclusion moves here.** The old `kdn.disks.enable` carried an `apply` that refused
#    `kdn.fs.disko.luks-zfs.enable` at the same time. `fs-luks-zfs` now holds the reverse assertion,
#    and it tests whether the `disks` aspect declared `kdn.disks.base`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch. See point 1 above.
# 3. **No custom module argument.** Every target module below takes `config`, `lib`, `pkgs` and
#    `options` only.
{ inputs, ... }:
{
  kdn.fs-zfs.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.fs.zfs;

      atLeastZFSVersion = lib.strings.versionAtLeast config.boot.zfs.package.version;

      kernelPackage =
        lib.pipe
          [
            {
              name = "2.3.1+";
              check = atLeastZFSVersion "2.3.1";
              pkg = pkgs.linuxKernel.packages.linux_6_18 or null;
            }
            {
              name = "default";
              check = true;
              pkg = pkgs.linuxKernel.packages.linux_6_6;
            }
          ]
          [
            (map (
              e:
              lib.optional e.check (
                lib.trivial.warnIf (
                  e.pkg == null
                ) "kdn.fs.zfs: kernel package not found/removed for: ${e.name}" e.pkg
              )
            ))
            builtins.concatLists
            (builtins.filter (pkg: pkg != null))
            builtins.head
          ];
    in
    {
      imports = [
        ../common/host-name.nix
      ];

      options.kdn.fs.zfs.package = lib.mkOption {
        type = with lib.types; package;
        default = pkgs.zfs_unstable;
        defaultText = lib.literalExpression "pkgs.zfs_unstable";
        description = "The ZFS package this host builds and runs.";
      };

      options.kdn.fs.zfs.containers.fsname = lib.mkOption {
        type = lib.types.str;
        default = "${config.kdn.hostName}-main/containerd/storage";
        defaultText = lib.literalExpression ''"''${config.kdn.hostName}-main/containerd/storage"'';
        description = "The ZFS dataset containerd uses for its own storage.";
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = with pkgs; [
            zfs-prune-snapshots
            sanoid
          ];
          # An out-of-tree ZFS module needs a kernel that the ZFS version supports, so this
          # aspect picks one. A hardware module picks a kernel too, and it also uses
          # `lib.mkDefault`. Equal priority stops the evaluation with
          # `The option `boot.kernelPackages' is defined multiple times`. Measured 2026-09-10
          # on the rpi4 host: `nixos-hardware`'s `raspberry-pi/4/default.nix:31` sets the
          # vendor kernel, which the Pi needs for its own hardware.
          #
          # `lib.mkOverride 1200` sits between two standard priorities, so a hardware
          # module now wins and this value stays the fallback:
          #
          #   1000 = `lib.mkDefault`      -- what a hardware module uses. It must win.
          #   1200 = this value           -- stronger than the option default, weaker than 1000.
          #   1500 = `lib.mkOptionDefault` -- the `default` of the option declaration.
          #
          # 1500 is not free: an option `default` is itself a definition at 1500, and nixpkgs
          # declares one at `<nixpkgs>/nixos/modules/system/boot/kernel.nix:69`. A value of
          # 1500 here ties with it and stops every ZFS host. Measured 2026-09-10 on brys.
          boot.kernelPackages = lib.mkOverride 1200 kernelPackage;
          boot.loader.grub.copyKernels = true;
          boot.kernelParams = [ "nohibernate" ];
          boot.initrd.supportedFilesystems = [ "zfs" ];
          boot.supportedFilesystems = [ "zfs" ];
          boot.zfs.package = cfg.package;

          services.zfs.autoScrub.enable = true;
          services.zfs.autoSnapshot.enable = true;
          services.zfs.autoSnapshot.flags = "-k -p --utc";
          services.zfs.autoSnapshot.frequent = 12;
          services.zfs.autoSnapshot.daily = 7;
          services.zfs.autoSnapshot.weekly = 6;
          services.zfs.autoSnapshot.monthly = 1;
          services.zfs.trim.enable = true;

          virtualisation.docker.storageDriver = "zfs";
          virtualisation.podman.extraPackages = [ pkgs.zfs ];
        }
        (lib.mkIf (config.virtualisation.containerd.enable) {
          virtualisation.containers.storage.settings.storage.driver = lib.mkForce "zfs";
          virtualisation.containers.storage.settings.storage.options.zfs.fsname = cfg.containers.fsname;
        })
      ];
    };

  kdn.fs-watch.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.fs.watch;

      watcherModule = lib.types.submodule (
        { name, ... }@args:
        {
          options.enable = lib.mkOption {
            type = with lib.types; bool;
            default = true;
            description = "Run this watcher. A disabled instance emits no systemd service.";
          };
          options.name = lib.mkOption {
            type = with lib.types; str;
            default = name;
            defaultText = lib.literalExpression "the attribute name";
            description = "The watcher name. It reaches the systemd unit name.";
          };
          options.debounce = lib.mkOption {
            type = with lib.types; str;
            default = "1sec";
            description = "How long the watcher waits after the last event.";
          };
          options.delay = lib.mkOption {
            type = with lib.types; nullOr str;
            default = null;
            description = "How long the watcher waits before it runs the command.";
          };
          options.initialRun = lib.mkOption {
            type = with lib.types; bool;
            default = false;
            description = "Run the command once at start, before any event arrives.";
          };
          options.extraArgs = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
            description = "More arguments for `watchexec`.";
          };
          options.dirs = lib.mkOption {
            type = with lib.types; listOf path;
            default = [ ];
            description = "Directories the watcher reads, without recursion.";
          };
          options.recursive = lib.mkOption {
            type = with lib.types; listOf path;
            default = [ ];
            description = "Directories the watcher reads, with recursion.";
          };
          options.files = lib.mkOption {
            type = with lib.types; listOf path;
            default = [ ];
            description = "Single files the watcher reads.";
          };
          options.exec = lib.mkOption {
            type = with lib.types; listOf str;
            apply = lib.strings.escapeShellArgs;
            description = "The command the watcher runs, as an argument list.";
          };
          options.systemdName = lib.mkOption {
            type = with lib.types; str;
            default = "kdn-fs-watch-${args.config.name}";
            defaultText = lib.literalExpression ''"kdn-fs-watch-''${config.name}"'';
            description = "The systemd unit name of this watcher.";
          };
        }
      );
    in
    {
      options.kdn.fs.watch.instances = lib.mkOption {
        default = { };
        type = with lib.types; attrsOf watcherModule;
        example = lib.literalExpression ''
          {
            my-watch.dirs = [ "/etc/my-service" ];
            my-watch.exec = [ "systemctl" "restart" "my-service" ];
          }
        '';
        description = ''
          One entry per filesystem watcher. Each entry becomes one systemd service that runs
          `watchexec`.

          An empty set emits nothing, so a host includes this aspect and adds an instance later.
        '';
      };

      config.systemd.services = lib.pipe cfg.instances [
        (lib.attrsets.filterAttrs (_: fsWatchCfg: fsWatchCfg.enable))
        (lib.attrsets.mapAttrs' (
          name: fsWatchCfg:
          lib.attrsets.nameValuePair fsWatchCfg.systemdName {
            description = "${name} filesystem watcher";
            serviceConfig = {
              RuntimeDirectory = "kdn-fs-watch-${name}";
              WorkingDirectory = "/run/kdn-fs-watch-${name}";
              ExecStart =
                lib.pipe
                  [
                    (lib.getExe pkgs.watchexec)
                    "--on-busy-update=queue"
                    "--debounce=${fsWatchCfg.debounce}"
                    (lib.lists.optional (!fsWatchCfg.initialRun) "--postpone")
                    (lib.lists.optional (fsWatchCfg.delay != null) "--delay-run=${fsWatchCfg.delay}")
                    (map (dir: "--watch-non-recursive=${dir}") fsWatchCfg.dirs)
                    (lib.pipe (fsWatchCfg.recursive ++ fsWatchCfg.files) [
                      (builtins.concatStringsSep "\n")
                      (
                        text:
                        pkgs.writeTextFile {
                          name = "kdn-fs-watch-${name}-watch-file";
                          inherit text;
                        }
                      )
                      (path: "--watch-file=${path}")
                    ])
                    fsWatchCfg.extraArgs
                    fsWatchCfg.exec
                  ]
                  [
                    lib.lists.flatten
                    lib.escapeShellArgs
                    lib.lists.toList
                  ];
            };
            wantedBy = [ "default.target" ];
          }
        ))
      ];
    };

  kdn.fs-luks-zfs.nixos =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.kdn.fs.disko.luks-zfs;

      # `utils.escapeSystemdPath` names a systemd unit for a LUKS volume. A NixOS evaluation passes
      # `utils` as a module argument, but a plain `lib.evalModules` does not. So build it here from
      # the same source file, and keep the target module free of a custom argument.
      utils = import (inputs.nixpkgs + "/nixos/lib/utils.nix") { inherit lib config pkgs; };

      # True when the `disks` aspect is present too. It declares `kdn.disks.base`, and
      # `../common/persist.nix` declares only `kdn.disks.persist`, so `base` is the right test.
      hasDisksAspect = ((options.kdn or { }).disks or { }) ? base;
    in
    {
      imports = [
        inputs.disko.nixosModules.disko
        ../common/host-name.nix
      ];

      options.kdn.fs.disko.luks-zfs.timeout = lib.mkOption {
        type = with lib.types; int;
        default = 15;
        description = "How many seconds the initrd waits for an unlock and for the pool import.";
      };

      options.kdn.fs.disko.luks-zfs.poolName = lib.mkOption {
        type = lib.types.str;
        default = "${config.kdn.hostName}-main";
        defaultText = lib.literalExpression ''"''${config.kdn.hostName}-main"'';
        description = "The ZFS pool the LUKS volumes carry.";
      };

      options.kdn.fs.disko.luks-zfs.decryptRequiresUnits = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "Units each cryptsetup unit waits for, for example a TPM2 or a YubiKey unit.";
      };

      options.kdn.fs.disko.luks-zfs.luksNames = lib.mkOption {
        type = with lib.types; listOf str;
        description = ''
          The LUKS volume names this aspect unlocks. The default reads them from the host's own
          `disko.devices`: an entry with `type == "luks"`, a `name`, and a ZFS content that names
          `poolName`.

          An empty list turns this aspect off. So a host that writes no matching disko layout
          includes the aspect and emits nothing.
        '';
        default = lib.trivial.pipe ((config.disko or { }).devices or { }) [
          (lib.attrsets.filterAttrsRecursive (n: v: !(lib.strings.hasPrefix "_" n)))
          (lib.collect (
            v:
            (v.type or "") == "luks"
            && (v ? name)
            && (v.content.type or "") == "zfs"
            && (v.content.pool or "") == cfg.poolName
          ))
          (map (v: v.name))
        ];
        defaultText = lib.literalExpression "every ZFS-on-LUKS volume of `disko.devices`";
      };

      options.kdn.fs.disko.luks-zfs.cryptsetupNames = lib.mkOption {
        type = with lib.types; listOf str;
        default = map (luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}") cfg.luksNames;
        defaultText = lib.literalExpression "one `systemd-cryptsetup@` unit name per `luksNames` entry";
        description = "The cryptsetup unit names, without the `.service` suffix.";
      };

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = !hasDisksAspect;
              message = ''
                den: include either the `disks` aspect or the `fs-luks-zfs` aspect, not both.

                Both of them write `disko.devices` and the initrd unlock order. `disks` generates the
                whole layout from `kdn.disks.devices`. `fs-luks-zfs` expects the host to write its own
                `disko.devices`.
              '';
            }
          ];
        }
        (lib.mkIf (cfg.luksNames != [ ]) (
          lib.mkMerge [
            {
              boot.zfs.forceImportRoot = false;
              boot.zfs.extraPools = [ cfg.poolName ];
              boot.zfs.requestEncryptionCredentials = false;

              boot.initrd.luks.forceLuksSupportInInitrd = true;
              boot.initrd.systemd.enable = true;

              disko.enableConfig = true;

              boot.initrd.systemd.services."zfs-import-${cfg.poolName}" = {
                requires = map (name: "${name}.service") cfg.cryptsetupNames;
                after = map (name: "${name}.service") cfg.cryptsetupNames;
                requiredBy = [ "initrd-fs.target" ];
                onFailure = [ "emergency.target" ];
                serviceConfig.TimeoutSec = cfg.timeout;
              };

              fileSystems."/boot".neededForBoot = true;
              fileSystems."/var/log/journal".neededForBoot = true;
            }
            {
              boot.initrd.systemd.services = lib.pipe cfg.cryptsetupNames [
                (map (name: {
                  inherit name;
                  value = {
                    overrideStrategy = "asDropin";
                    requires = cfg.decryptRequiresUnits;
                    after = cfg.decryptRequiresUnits;
                    # TODO: replace `systemd-udev-settle.service` with a device unit dependency.
                    wants = [ "systemd-udev-settle.service" ];
                    onFailure = [ "emergency.target" ];
                    serviceConfig.TimeoutSec = cfg.timeout;
                  };
                }))
                builtins.listToAttrs
              ];
            }
          ]
        ))
      ];
    };
}
