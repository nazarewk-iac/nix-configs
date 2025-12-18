{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.fs.zfs;

  atLeastZFSVersion = lib.strings.versionAtLeast config.boot.zfs.package.version;

  kernelPackage =
    lib.pipe
    [
      {
        name = "2.3.1+";
        check = atLeastZFSVersion "2.3.1";
        pkg = pkgs.linuxKernel.packages.linux_6_17 or null;
      }
      {
        name = "default";
        check = true;
        pkg = pkgs.linuxKernel.packages.linux_6_6;
      }
    ]
    [
      (builtins.map (
        e:
          lib.optional e.check (
            lib.trivial.warnIf (
              e.pkg == null
            ) "kdn.fs.zfs: kernel package not found/removed for: ${e.name}"
            e.pkg
          )
      ))
      builtins.concatLists
      (builtins.filter (pkg: pkg != null))
      builtins.head
    ];
in {
  options.kdn.fs.zfs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = builtins.any (fs: fs.fsType == "zfs") (builtins.attrValues config.fileSystems);
    };
    package = lib.mkOption {
      type = with lib.types; package;
      default = builtins.any (fs: fs.fsType == "zfs") (builtins.attrValues config.fileSystems);
    };

    containers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    containers.fsname = lib.mkOption {
      type = lib.types.str;
      default = "${config.kdn.hostName}-main/${config.kdn.hostName}/containers/storage";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        boot.kernelPackages = lib.mkDefault kernelPackage;
        boot.loader.grub.copyKernels = true;
        boot.kernelParams = ["nohibernate"];
        boot.initrd.supportedFilesystems = ["zfs"];
        boot.supportedFilesystems = ["zfs"];
        boot.zfs.package = pkgs.zfs_unstable;

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

        environment.systemPackages = with pkgs; [
          zfs-prune-snapshots
          sanoid
        ];

        virtualisation.docker.storageDriver = "zfs";
        virtualisation.podman.extraPackages = [pkgs.zfs];
      }
      (lib.mkIf (config.kdn.virtualisation.containers.enable && cfg.containers.enable) {
        virtualisation.containers.storage.settings.storage.driver = lib.mkForce "zfs";
        virtualisation.containers.storage.settings.storage.options.zfs.fsname = cfg.containers.fsname;
      })
    ]
  );
}
