{ lib, pkgs, config, ... }:
let
  /* copy-pasteable:
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
  mkDirsOption = prefix: extra: lib.mkOption
    {
      type = with lib.types; listOf str;
      apply = builtins.map (dir:
        if prefix == "" || lib.strings.hasPrefix "/" dir
        then lib.strings.removePrefix "/" dir
        else "${prefix}/${dir}"
      );
    } // extra;

  enabledAppsList = lib.pipe config.kdn.programs.apps [
    builtins.attrValues
    (builtins.filter (cfg: cfg.enable))
  ];
in
{
  options.kdn.programs.apps = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@appAttrs:
      let cfg = appAttrs.config; in {
        options = {
          enable = lib.mkOption {
            type = with lib.types; bool;
            default = true;
          };
          name = lib.mkOption {
            type = with lib.types; str;
            default = name;
          };
          dirs.cache = mkDirsOption ".cache" { };
          dirs.config = mkDirsOption ".config" { };
          dirs.data = mkDirsOption ".local/share" { };
          dirs.disposable = mkDirsOption "" { };
          dirs.reproducible = mkDirsOption "" { };
          dirs.state = mkDirsOption ".local/state" { };

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
            default = cfg.package.original.override (prev: lib.lists.foldl (old: fn: fn old) prev cfg.package.overlays);
          };
          package.install = lib.mkOption {
            type = with lib.types; bool;
            default = true;
          };
        };
      }));
  };

  config = {
    home.packages = lib.pipe enabledAppsList [
      (builtins.map (cfg: lib.optional (cfg.package.install) cfg.package.final))
      builtins.concatLists
    ];
    home.persistence."usr/cache".directories = lib.pipe enabledAppsList [
      (builtins.map (cfg: cfg.dirs.cache))
      builtins.concatLists
    ];
    home.persistence."usr/config".directories = lib.pipe enabledAppsList [
      (builtins.map (cfg: cfg.dirs.config))
      builtins.concatLists
    ];
    home.persistence."usr/data".directories = lib.pipe enabledAppsList [
      (builtins.map (cfg: cfg.dirs.data))
      builtins.concatLists
    ];
    home.persistence."usr/state".directories = lib.pipe enabledAppsList [
      (builtins.map (cfg: cfg.dirs.state))
      builtins.concatLists
    ];
    home.persistence."usr/reproducible".directories = lib.pipe enabledAppsList [
      (builtins.map (cfg: cfg.dirs.reproducible))
      builtins.concatLists
    ];
    home.persistence."disposable".directories = lib.pipe enabledAppsList [
      (builtins.map (cfg: cfg.dirs.disposable))
      builtins.concatLists
    ];
  };
}
