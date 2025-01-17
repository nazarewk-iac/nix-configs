{
  lib,
  pkgs,
  config,
  ...
}: let
  enabledAppsList = lib.pipe config.kdn.programs.apps [
    builtins.attrValues
    (builtins.filter (cfg: cfg.enable))
  ];
in {
  config = lib.mkMerge [
    {
      kdn.hardware.disks.persist."usr/cache".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.cache))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/config".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.config))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/data".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.data))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/state".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.state))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/reproducible".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.reproducible))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."disposable".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.disposable))
        builtins.concatLists
      ];

      kdn.hardware.disks.persist."usr/cache".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.cache))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/config".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.config))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/data".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.data))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/state".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.state))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."usr/reproducible".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.reproducible))
        builtins.concatLists
      ];
      kdn.hardware.disks.persist."disposable".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.disposable))
        builtins.concatLists
      ];
    }
  ];
}
