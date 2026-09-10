{

  lib,
  pkgs,
  config,
  kdnConfig,
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
  options.kdn.fs.zfs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default =
        if kdnConfig.moduleType == "nixos" then
          builtins.any (fs: fs.fsType == "zfs") (builtins.attrValues config.fileSystems)
        else
          false;
    };
    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.zfs_unstable;
    };

    containers.fsname = lib.mkOption {
      type = lib.types.str;
      default = "${config.kdn.hostName}-main/containerd/storage";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            kdn.env.packages = with pkgs; [
              zfs-prune-snapshots
              sanoid
            ];
            # An out-of-tree ZFS module needs a kernel that the ZFS version supports, so this
            # module picks one. A hardware module picks a kernel too, and it also uses
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
            #
            # This module holds the only `boot.kernelPackages` definition in the repository --
            # every other reference reads the option. So no host without a hardware kernel
            # changes.
            #
            # Verified 2026-09-10: no rpi4 host holds a ZFS filesystem. `fileSystems` of the
            # rpi4 host lists none, and `kdn.fs.zfs.enable` is true only because
            # `modules/universal/profile/machine/baseline/default.nix:295` sets
            # `lib.mkDefault true` for every baseline host.
            #
            # So this priority change is correct, and a second question stays open: should the
            # baseline profile enable ZFS on a host that mounts no ZFS filesystem? A `switch` on
            # the rpi4 host now compiles the ZFS modules against the vendor kernel. The
            # evaluation passes; the build is unproven.
            #
            # TODO: decide whether the baseline profile keeps `kdn.fs.zfs.enable` on a host with
            # no ZFS filesystem.
            boot.kernelPackages = lib.mkOverride 1200 kernelPackage;
            boot.loader.grub.copyKernels = true;
            boot.kernelParams = [ "nohibernate" ];
            boot.initrd.supportedFilesystems = [ "zfs" ];
            boot.supportedFilesystems = [ "zfs" ];
            boot.zfs.package = cfg.package;

            # for now trying rt kernel
            ## see https://github.com/NixOS/nixpkgs/issues/169457
            #boot.kernelPatches = [{
            #  name = "enable RT_FULL";
            #  patch = null;
            #  extraConfig = ''
            #    PREEMPT y
            #    PREEMPT_BUILD y
            #    PREEMPT_VOLUNTARY n
            #    PREEMPT_COUNT y
            #    PREEMPTION y
            #  '';
            #}];

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
        ]
      ))
    ]
  );
}
