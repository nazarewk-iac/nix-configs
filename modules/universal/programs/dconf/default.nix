{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.dconf;
in
{
  options.kdn.programs.dconf = {
    enable = lib.mkOption {
      default = false;
    };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        programs.dconf.enable = true;
        home-manager.sharedModules = [ { kdn.programs.dconf.enable = true; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        dconf.enable = true;
        kdn.apps.dconf = {
          enable = true;
          package.install = false;
          dirs.cache = [ ];
          dirs.config = [ "dconf" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ))
  ];
}
