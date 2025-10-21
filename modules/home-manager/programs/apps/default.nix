{
  lib,
  pkgs,
  config,
  ...
}:
let
  /*
     copy-pasteable:
    kdn.programs.apps."app" = {
      enable = true;
      #package.original = pkgs."app";
      dirs.cache = [ ];
      dirs.config = [ ];
      dirs.data = [ ];
      dirs.disposable = [ ];
      dirs.reproducible = [ ];
      dirs.state = [ ];
    };
  */
  mkPathsOption =
    prefix: extra:
    lib.mkOption {
      type = with lib.types; listOf str;
      apply = builtins.map (
        dir:
        if prefix == "" || lib.strings.hasPrefix "/" dir then
          lib.strings.removePrefix "/" dir
        else
          "${prefix}/${dir}"
      );
    }
    // extra;

  enabledAppsList = lib.pipe config.kdn.programs.apps [
    builtins.attrValues
    (builtins.filter (cfg: cfg.enable))
  ];
in
{
  options.kdn.programs.apps = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }@appAttrs:
        let
          cfg = appAttrs.config;
        in
        {
          options = {
            enable = lib.mkOption {
              type = with lib.types; bool;
              default = true;
            };
            name = lib.mkOption {
              type = with lib.types; str;
              default = name;
            };
            dirs.cache = mkPathsOption ".cache" { };
            dirs.config = mkPathsOption ".config" { };
            dirs.data = mkPathsOption ".local/share" { };
            dirs.disposable = mkPathsOption "" { };
            dirs.reproducible = mkPathsOption "" { };
            dirs.state = mkPathsOption ".local/state" { default = [ ]; };
            files.cache = mkPathsOption ".cache" { default = [ ]; };
            files.config = mkPathsOption ".config" { default = [ ]; };
            files.data = mkPathsOption ".local/share" { default = [ ]; };
            files.disposable = mkPathsOption "" { default = [ ]; };
            files.reproducible = mkPathsOption "" { default = [ ]; };
            files.state = mkPathsOption ".local/state" { default = [ ]; };

            package.original = lib.mkOption {
              type = with lib.types; nullOr package;
              default = pkgs."${cfg.name}";
            };
            package.overlays = lib.mkOption {
              type = with lib.types; listOf (functionTo (attrsOf anything));
              default = [ ];
            };
            package.final = lib.mkOption {
              type = with lib.types; package;
              default = cfg.package.original.override (
                prev: lib.lists.foldl (old: fn: fn old) prev cfg.package.overlays
              );
            };
            package.install = lib.mkOption {
              type = with lib.types; bool;
              default = true;
            };
          };
        }
      )
    );
  };

  config = lib.mkMerge [
    {
      home.packages = lib.pipe enabledAppsList [
        (builtins.map (cfg: lib.optional (cfg.package.install) cfg.package.final))
        builtins.concatLists
      ];
    }
    {
      kdn.hw.disks.persist."usr/cache".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.cache))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/config".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.config))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/data".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.data))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/state".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.state))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/reproducible".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.reproducible))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."disposable".directories = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.dirs.disposable))
        builtins.concatLists
      ];

      kdn.hw.disks.persist."usr/cache".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.cache))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/config".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.config))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/data".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.data))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/state".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.state))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."usr/reproducible".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.reproducible))
        builtins.concatLists
      ];
      kdn.hw.disks.persist."disposable".files = lib.pipe enabledAppsList [
        (builtins.map (cfg: cfg.files.disposable))
        builtins.concatLists
      ];
    }
  ];
}
