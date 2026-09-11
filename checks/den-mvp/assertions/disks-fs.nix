# Tier-1 assertions for the disks and filesystem aspects of layer C:
#
#   * `disks`         -- the whole impermanence and disko layout, `nixos` class.
#   * `disks-persist` -- the user half of impermanence, `homeManager` class.
#   * `fs-zfs`        -- ZFS support and the kernel choice, `nixos` class.
#   * `fs-watch`      -- one systemd service per filesystem watcher, `nixos` class.
#   * `fs-luks-zfs`   -- ZFS on LUKS for a host that writes its own disko layout, `nixos` class.
#
# Every value below comes from a measurement on 2026-09-11. A subject is a bare consumer: a plain
# `nixosSystem` or a plain `homeManagerConfiguration`, with no den entity, no `kdnConfig` and no
# overlay.
#
# ## Two consumer lines that a subject cannot drop
#
# 1. **`fileSystems."/".device = lib.mkForce "tmpfs";`** — the `disks` aspect generates
#    `disko.devices.nodev."/"`, and disko writes `device = "tmpfs"` from it. The bare harness writes
#    `device = "none"`. Two plain definitions of one scalar stop the evaluation, so the subject
#    picks one. A real host writes no `fileSystems."/"` of its own, so it never meets this.
# 2. **`networking.hostId`** — ZFS asserts on it. Every subject that reaches a ZFS dataset needs it.
#
# ## The cross-scope read
#
# den delivers `nixos` through a host aspect and `homeManager` through a user aspect, so the two
# halves of impermanence are two aspects. The host reads the user half back through
# `config.home-manager.users.<name>.kdn.disks.persist`. The `disksWithUser` subject below proves
# that route: it loads Home Manager as a NixOS module and gives one user two paths of its own.
{
  lib,
  inputs,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareHomeConfiguration;

  # Every subject that includes `disks` repeats these three lines. See the header.
  disksConsumer = {
    networking.hostId = "deadbeef";
    fileSystems."/".device = lib.mkForce "tmpfs";
    kdn.disks.devices."boot".path = "/dev/disk/by-id/probe-boot";
  };

  nixosModules =
    aspects:
    denLib.imports {
      class = "nixos";
      inherit aspects;
    };
  homeModules =
    aspects:
    denLib.imports {
      class = "homeManager";
      inherit aspects;
    };

  # ---- `disks` with no consumer data beyond the three mandatory lines
  disksPlain = (bareNixos (nixosModules [ "disks" ] ++ [ disksConsumer ])).config;

  # ---- `disks` and `fs-zfs` on one real layout: two whole-disk LUKS volumes, so a mirror
  disksHost =
    (bareNixos (
      nixosModules [
        "disks"
        "fs-zfs"
      ]
      ++ [
        disksConsumer
        {
          kdn.hostName = "probehost";
          kdn.disks.luks.volumes."one-probehost" = {
            targetSpec.path = "/dev/disk/by-id/probe-one";
            uuid = "00000000-0000-4000-8000-000000000001";
            headerSpec.partNum = 2;
          };
          kdn.disks.luks.volumes."two-probehost" = {
            targetSpec.path = "/dev/disk/by-id/probe-two";
            uuid = "00000000-0000-4000-8000-000000000002";
            headerSpec.partNum = 3;
          };
          kdn.disks.persist."sys/data".directories = [ "/var/lib/probe" ];
        }
      ]
    )).config;

  # ---- the kernel priority ladder. A hardware module uses `lib.mkDefault`, and it must win.
  zfsOverridden =
    (bareNixos (
      nixosModules [ "fs-zfs" ]
      ++ [
        { networking.hostId = "deadbeef"; }
        (
          { pkgs, lib, ... }:
          {
            boot.kernelPackages = lib.mkDefault pkgs.linuxKernel.packages.linux_6_6;
          }
        )
      ]
    )).config;

  # ---- the user half, beside the `apps` aspect
  homeWithApps =
    (bareHomeConfiguration (
      homeModules [
        "disks-persist"
        "apps"
      ]
      ++ [
        {
          kdn.apps.hello.enable = true;
          kdn.apps.hello.dirs.config = [ "hello" ];
          kdn.apps.hello.files.state = [ "hello/last-run" ];
          kdn.disks.persist."usr/config".directories = [ ".config/probe" ];
        }
      ]
    )).config;

  # ---- the user half alone, with no `apps` aspect at all
  homeAlone =
    (bareHomeConfiguration (
      homeModules [ "disks-persist" ] ++ [ { kdn.disks.persist."usr/data".files = [ ".probe-marker" ]; } ]
    )).config;

  # ---- the cross-scope read: the host collects the user's own paths
  disksWithUser =
    (bareNixos (
      nixosModules [ "disks" ]
      ++ [
        inputs.home-manager.nixosModules.home-manager
        disksConsumer
        {
          users.users.dev = {
            isNormalUser = true;
            home = "/home/dev";
            group = "users";
          };
          home-manager.users.dev = {
            imports = homeModules [ "disks-persist" ];
            home.stateVersion = "26.11";
            kdn.disks.persist."usr/config".directories = [ ".config/from-user" ];
            kdn.disks.persist."usr/data".files = [ ".user-marker" ];
          };
        }
      ]
    )).config;

  # ---- one filesystem watcher, and none
  watchHost =
    (bareNixos (
      nixosModules [ "fs-watch" ]
      ++ [
        {
          kdn.fs.watch.instances."probe" = {
            dirs = [ "/etc/probe" ];
            exec = [
              "true"
              "one arg"
            ];
          };
        }
      ]
    )).config;

  watchPlain = (bareNixos (nixosModules [ "fs-watch" ])).config;

  watcherUnits =
    cfg: lib.filter (lib.strings.hasPrefix "kdn-fs-watch-") (builtins.attrNames cfg.systemd.services);

  execLine = builtins.head watchHost.systemd.services."kdn-fs-watch-probe".serviceConfig.ExecStart;

  # ---- ZFS on LUKS, where the host writes its own disko layout, and the empty case
  luksHost =
    (bareNixos (
      nixosModules [
        "fs-luks-zfs"
        "fs-zfs"
      ]
      ++ [
        {
          kdn.hostName = "probehost";
          networking.hostId = "deadbeef";
          disko.devices.disk."main" = {
            type = "disk";
            device = "/dev/disk/by-id/probe-main";
            content.type = "luks";
            content.name = "main-crypted";
            content.content.type = "zfs";
            content.content.pool = "probehost-main";
          };
          disko.devices.zpool."probehost-main" = {
            type = "zpool";
            datasets."journal" = {
              type = "zfs_fs";
              mountpoint = "/var/log/journal";
            };
          };
          fileSystems."/boot" = {
            device = "/dev/disk/by-id/probe-boot-part1";
            fsType = "vfat";
          };
        }
      ]
    )).config;

  luksPlain = (bareNixos (nixosModules [ "fs-luks-zfs" ])).config;

  # ---- the mutual exclusion. `disks` and `fs-luks-zfs` both write `disko.devices`.
  bothCfg =
    (bareNixos (
      nixosModules [
        "disks"
        "fs-luks-zfs"
      ]
      ++ [ disksConsumer ]
    )).config;

  bothFailed = map (a: a.message) (lib.filter (a: !a.assertion) bothCfg.assertions);

  buckets = [
    "disposable"
    "sys/cache"
    "sys/config"
    "sys/data"
    "sys/reproducible"
    "sys/state"
    "usr/cache"
    "usr/config"
    "usr/data"
    "usr/reproducible"
    "usr/state"
  ];

  hasPackage = name: packages: lib.any (p: (lib.getName p) == name) packages;

  directoriesOf = entry: map (d: d.directory) entry.directories;
  filesOf = entry: map (f: f.file) entry.files;

  # Three assertions below read a list whose order comes from the module definition order, not from
  # a decision of the aspect. `denLib.imports` wraps each target module, so the aspect definition
  # lands after the consumer definition. Both sides sort, and the assertion then reads the content.
  sortStrings = names: builtins.sort builtins.lessThan names;
in
[
  # ---------------------------------------------------------------- `disks`, bare consumer
  {
    name = "the eleven persist buckets exist, and every one of them reaches preservation";
    expected = {
      base = buckets;
      persist = buckets;
      preserveAt = buckets;
    };
    actual = {
      base = builtins.attrNames disksPlain.kdn.disks.base;
      persist = builtins.attrNames disksPlain.kdn.disks.persist;
      preserveAt = builtins.attrNames disksPlain.preservation.preserveAt;
    };
  }
  {
    name = "a bare consumer gets the whole impermanence opinion of the aspect";
    expected = {
      preservation = true;
      userAllowOther = true;
      mountPrefix = "/nix/persist";
      bootDeviceName = "boot";
      nixBuildDir = "disposable";
      tmpfsSize = "16M";
      zpoolMain = "nixos-main";
      metaIsAttrs = true;
    };
    actual = {
      preservation = disksPlain.preservation.enable;
      userAllowOther = disksPlain.programs.fuse.userAllowOther;
      mountPrefix = disksPlain.kdn.disks.defaults.mountPrefix;
      bootDeviceName = disksPlain.kdn.disks.defaults.bootDeviceName;
      nixBuildDir = disksPlain.kdn.disks.nixBuildDir.type;
      tmpfsSize = disksPlain.kdn.disks.tmpfs.size;
      zpoolMain = disksPlain.kdn.disks.zpool-main.name;
      metaIsAttrs = builtins.isAttrs disksPlain.kdn.disks.disko.devices._meta;
    };
  }
  {
    name = "the user defaults keep the disposable home, the two modes and the three cache buckets";
    expected = {
      homeLocation = "disposable";
      homeDirMode = "0750";
      homeFileMode = "0640";
      persist = [
        "sys/cache"
        "usr/cache"
        "usr/data"
      ];
    };
    actual = {
      inherit (disksPlain.kdn.disks.userDefaults) homeLocation homeDirMode homeFileMode;
      persist = builtins.attrNames disksPlain.kdn.disks.userDefaults.persist;
    };
  }
  {
    name = "sys/data keeps the two systemd state directories, and no user exists until a host names one";
    expected = {
      sysData = [
        "/var/lib/systemd"
        "/var/lib/private"
      ];
      users = [ ];
    };
    actual = {
      sysData = directoriesOf disksPlain.preservation.preserveAt."sys/data";
      users = builtins.attrNames disksPlain.kdn.disks.users;
    };
  }

  # ---------------------------------------------------------------- `disks`, one real layout
  {
    name = "a whole-disk LUKS volume names its own unit, its key file, its target and its header";
    expected = {
      name = "one-probehost-crypted";
      keyFile = "/tmp/one-probehost.key";
      target = "/dev/disk/by-id/probe-one";
      header = "/dev/disk/by-id/probe-boot-part2";
      headerSize = 32;
    };
    actual = {
      inherit (disksHost.kdn.disks.luks.volumes."one-probehost") name keyFile;
      target = disksHost.kdn.disks.luks.volumes."one-probehost".target.path;
      header = disksHost.kdn.disks.luks.volumes."one-probehost".header.path;
      headerSize = disksHost.kdn.disks.luks.header.size;
    };
  }
  {
    name = "the pool waits for one escaped cryptsetup unit per volume";
    expected = [
      "systemd-cryptsetup@one\\x2dprobehost\\x2dcrypted"
      "systemd-cryptsetup@two\\x2dprobehost\\x2dcrypted"
    ];
    actual = disksHost.kdn.disks.zpools."probehost-main".cryptsetup.names;
  }
  {
    name = "two LUKS volumes generate three disks, three tmpfs nodevs, three boot partitions and a mirror";
    expected = {
      disks = [
        "boot"
        "one-probehost"
        "two-probehost"
      ];
      nodev = [
        "/"
        "/home"
        "/nix/var/nix/builds-tmpfs"
      ];
      bootPartitions = [
        "ESP"
        "one-probehost-header"
        "two-probehost-header"
      ];
      deviceType = "luks";
      mode = "mirror";
      enableConfig = true;
    };
    actual = {
      disks = builtins.attrNames disksHost.disko.devices.disk;
      nodev = builtins.attrNames disksHost.disko.devices.nodev;
      bootPartitions = builtins.attrNames disksHost.kdn.disks.devices."boot".partitions;
      deviceType = disksHost.kdn.disks.devices."one-probehost".type;
      mode = disksHost.disko.devices.zpool."probehost-main".mode;
      enableConfig = disksHost.disko.enableConfig;
    };
  }
  {
    name = "the pool carries the root dataset, eleven impermanence datasets and the three nix datasets";
    expected = [
      "__root"
      "probehost/impermanence/disposable"
      "probehost/impermanence/sys/cache"
      "probehost/impermanence/sys/config"
      "probehost/impermanence/sys/data"
      "probehost/impermanence/sys/reproducible"
      "probehost/impermanence/sys/state"
      "probehost/impermanence/usr/cache"
      "probehost/impermanence/usr/config"
      "probehost/impermanence/usr/data"
      "probehost/impermanence/usr/reproducible"
      "probehost/impermanence/usr/state"
      "probehost/nix-system/nix-builds"
      "probehost/nix-system/nix-store"
      "probehost/nix-system/nix-var"
    ];
    actual = builtins.attrNames disksHost.disko.devices.zpool."probehost-main".datasets;
  }
  {
    name = "every bucket mountpoint and /boot are needed for boot";
    expected = [
      "/boot"
      "/nix/persist/disposable"
      "/nix/persist/sys/cache"
      "/nix/persist/sys/config"
      "/nix/persist/sys/data"
      "/nix/persist/sys/reproducible"
      "/nix/persist/sys/state"
      "/nix/persist/usr/cache"
      "/nix/persist/usr/config"
      "/nix/persist/usr/data"
      "/nix/persist/usr/reproducible"
      "/nix/persist/usr/state"
    ];
    actual = lib.pipe disksHost.fileSystems [
      (lib.filterAttrs (_: v: v.neededForBoot))
      builtins.attrNames
      (names: builtins.sort builtins.lessThan names)
    ];
  }
  {
    name = "a host path appends to the bucket, and the two tmpfiles rule sets exist";
    expected = {
      # Sorted on both sides. A list of preserved paths carries no order, and `denLib.imports`
      # places the aspect definition after the consumer definition. See the note at the top of the
      # `let` block.
      sysData = [
        "/var/lib/private"
        "/var/lib/probe"
        "/var/lib/systemd"
      ];
      tmpfiles = [
        "preservation"
        "zzz-kdn-preservation-system"
      ];
      hasVarLib = true;
      rollback = "rollbacks `disposable` filesystem to empty state";
    };
    actual = {
      sysData = sortStrings (directoriesOf disksHost.preservation.preserveAt."sys/data");
      tmpfiles = builtins.attrNames disksHost.systemd.tmpfiles.settings;
      hasVarLib = disksHost.systemd.tmpfiles.settings.zzz-kdn-preservation-system ? "/var/lib";
      rollback = disksHost.boot.initrd.systemd.services."kdn-disks-disposable-rollback".description;
    };
  }

  # ---------------------------------------------------------------- `disks-persist`
  {
    name = "the user half wires the apps output and keeps a path the user adds itself";
    expected = {
      buckets = [
        "disposable"
        "usr/cache"
        "usr/config"
        "usr/data"
        "usr/reproducible"
        "usr/state"
      ];
      # Sorted on both sides, for the reason the `sys/data` assertion above states.
      configDirs = [
        ".config/hello"
        ".config/probe"
      ];
      stateFiles = [ ".local/state/hello/last-run" ];
    };
    actual = {
      buckets = builtins.attrNames homeWithApps.kdn.disks.persist;
      configDirs = sortStrings homeWithApps.kdn.disks.persist."usr/config".directories;
      stateFiles = homeWithApps.kdn.disks.persist."usr/state".files;
    };
  }
  {
    name = "the user half works with no apps aspect, and it then names the one bucket the user wrote";
    expected = {
      buckets = [ "usr/data" ];
      files = [ ".probe-marker" ];
    };
    actual = {
      buckets = builtins.attrNames homeAlone.kdn.disks.persist;
      files = homeAlone.kdn.disks.persist."usr/data".files;
    };
  }

  # ---------------------------------------------------------------- the cross-scope read
  {
    name = "the host finds the Home Manager user and gives it the default home location";
    expected = {
      users = [ "dev" ];
      homeLocation = "disposable";
    };
    actual = {
      users = builtins.attrNames disksWithUser.kdn.disks.users;
      homeLocation = disksWithUser.kdn.disks.users.dev.homeLocation;
    };
  }
  {
    name = "a user path from the home scope reaches the host preserveAt entry, with the two modes";
    expected = {
      configDirs = [
        "/home/dev/.config/from-user"
        "/home/dev/.config"
      ];
      dataFiles = [ "/home/dev/.user-marker" ];
      dataFileModes = [ "0640" ];
      firstConfigMode = "0750";
    };
    actual = {
      configDirs = directoriesOf disksWithUser.preservation.preserveAt."usr/config".users.dev;
      dataFiles = filesOf disksWithUser.preservation.preserveAt."usr/data".users.dev;
      dataFileModes = map (f: f.mode) disksWithUser.preservation.preserveAt."usr/data".users.dev.files;
      firstConfigMode =
        (builtins.head disksWithUser.preservation.preserveAt."usr/config".users.dev.directories).mode;
    };
  }
  {
    name = "the default user buckets carry the six home paths, and the home itself is disposable";
    expected = {
      dataDirs = [
        "/home/dev/Documents"
        "/home/dev/Desktop"
        "/home/dev/Pictures"
        "/home/dev/Videos"
        "/home/dev/.local/share/nix"
        "/home/dev/.local/share"
        "/home/dev/.local"
      ];
      cacheDirs = [
        "/home/dev/.cache/nix"
        "/home/dev/.cache"
      ];
      disposable = [
        "/home/dev"
        "/var/tmp"
        "/nix/var/nix/builds-disposable"
      ];
      # Sorted on both sides. A systemd `After=` list carries no order.
      hmAfter = [
        "nix-daemon.socket"
        "preservation.target"
      ];
      tmpfilesUsersRules = 8;
    };
    actual = {
      dataDirs = directoriesOf disksWithUser.preservation.preserveAt."usr/data".users.dev;
      cacheDirs = directoriesOf disksWithUser.preservation.preserveAt."sys/cache".users.dev;
      disposable = directoriesOf disksWithUser.preservation.preserveAt."disposable";
      hmAfter = sortStrings disksWithUser.systemd.services."home-manager-dev".after;
      tmpfilesUsersRules = builtins.length (
        builtins.attrNames disksWithUser.systemd.tmpfiles.settings.zzz-kdn-preservation-users
      );
    };
  }

  # ---------------------------------------------------------------- `fs-watch`
  {
    name = "one instance becomes one watchexec service, with the queue, debounce and postpone flags";
    expected = {
      units = [ "kdn-fs-watch-probe" ];
      wantedBy = [ "default.target" ];
      execParts = 1;
      queue = true;
      debounce = true;
      postpone = true;
      nonRecursive = true;
      watchFile = true;
      command = true;
    };
    actual = {
      units = watcherUnits watchHost;
      wantedBy = watchHost.systemd.services."kdn-fs-watch-probe".wantedBy;
      execParts = builtins.length watchHost.systemd.services."kdn-fs-watch-probe".serviceConfig.ExecStart;
      queue = lib.strings.hasInfix "'--on-busy-update=queue'" execLine;
      debounce = lib.strings.hasInfix "'--debounce=1sec'" execLine;
      postpone = lib.strings.hasInfix " --postpone " execLine;
      nonRecursive = lib.strings.hasInfix "'--watch-non-recursive=/etc/probe'" execLine;
      watchFile = lib.strings.hasInfix "'--watch-file=/nix/store/" execLine;
      command = lib.strings.hasSuffix "'true '\\''one arg'\\'''" execLine;
    };
  }
  {
    name = "the watcher aspect with no instance emits no unit at all";
    expected = {
      instances = [ ];
      units = [ ];
    };
    actual = {
      instances = builtins.attrNames watchPlain.kdn.fs.watch.instances;
      units = watcherUnits watchPlain;
    };
  }

  # ---------------------------------------------------------------- `fs-luks-zfs`
  {
    name = "a host-written ZFS-on-LUKS layout reaches the unlock order and the import timeout";
    expected = {
      poolName = "probehost-main";
      luksNames = [ "main-crypted" ];
      cryptsetupNames = [ "systemd-cryptsetup@main\\x2dcrypted" ];
      timeout = 15;
      extraPools = [ "probehost-main" ];
      importTimeout = 15;
      bootNeededForBoot = true;
      journalNeededForBoot = true;
      enableConfig = true;
    };
    actual = {
      inherit (luksHost.kdn.fs.disko.luks-zfs)
        poolName
        luksNames
        cryptsetupNames
        timeout
        ;
      extraPools = luksHost.boot.zfs.extraPools;
      importTimeout =
        luksHost.boot.initrd.systemd.services."zfs-import-probehost-main".serviceConfig.TimeoutSec;
      bootNeededForBoot = luksHost.fileSystems."/boot".neededForBoot;
      journalNeededForBoot = luksHost.fileSystems."/var/log/journal".neededForBoot;
      enableConfig = luksHost.disko.enableConfig;
    };
  }
  {
    name = "the same aspect emits nothing when the host writes no matching layout";
    expected = {
      luksNames = [ ];
      cryptsetupNames = [ ];
      extraPools = [ ];
      importServices = [ ];
    };
    actual = {
      inherit (luksPlain.kdn.fs.disko.luks-zfs) luksNames cryptsetupNames;
      extraPools = luksPlain.boot.zfs.extraPools;
      importServices = lib.filter (lib.strings.hasPrefix "zfs-import-") (
        builtins.attrNames luksPlain.boot.initrd.systemd.services
      );
    };
  }
  {
    name = "a host that includes both disks and fs-luks-zfs gets one failed assertion";
    expected = {
      failures = 1;
      mentionsBoth = true;
    };
    actual = {
      failures = builtins.length bothFailed;
      mentionsBoth = lib.any (m: lib.strings.hasInfix "not both" m) bothFailed;
    };
  }

  # ---------------------------------------------------------------- `fs-zfs`
  {
    name = "the ZFS aspect installs its two tools and keeps the whole snapshot and scrub opinion";
    expected = {
      sanoid = true;
      pruneSnapshots = true;
      filesystems = [
        "tmpfs"
        "vfat"
        "zfs"
      ];
      snapshotFlags = "-k -p --utc";
      trim = true;
      package = "zfs";
      dockerDriver = "zfs";
      containersFsname = "probehost-main/containerd/storage";
    };
    actual = {
      sanoid = hasPackage "sanoid" disksHost.environment.systemPackages;
      pruneSnapshots = hasPackage "zfs-prune-snapshots" disksHost.environment.systemPackages;
      filesystems = lib.pipe disksHost.boot.supportedFilesystems [
        (lib.filterAttrs (_: v: v))
        builtins.attrNames
      ];
      snapshotFlags = disksHost.services.zfs.autoSnapshot.flags;
      trim = disksHost.services.zfs.trim.enable;
      package = lib.getName disksHost.boot.zfs.package;
      dockerDriver = disksHost.virtualisation.docker.storageDriver;
      containersFsname = disksHost.kdn.fs.zfs.containers.fsname;
    };
  }
  {
    name = "a hardware module beats the ZFS kernel choice, because that choice sits at priority 1200";
    expected = {
      overrideWins = true;
    };
    actual = {
      overrideWins =
        zfsOverridden.boot.kernelPackages.kernel.version != disksHost.boot.kernelPackages.kernel.version;
    };
  }
]
