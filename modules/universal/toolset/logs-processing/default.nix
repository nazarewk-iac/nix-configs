{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.logs-processing;
in
{
  options.kdn.toolset.logs-processing = {
    enable = lib.mkEnableOption "logs processing tooling";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.env.packages =
        (with pkgs; [
          # https://github.com/trungdq88/logmine
          # https://github.com/ynqa/logu
          # https://github.com/logpai/logparser
          angle-grinder # https://github.com/rcoh/angle-grinder
          # https://github.com/dloss/klp
        ])
        ++ [ ];
    })
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.toolset.logs-processing.enable = true; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        kdn.apps.lnav = {
          enable = true;
          package.original = pkgs.lnav;
          dirs.cache = [ ];
          dirs.config = [ "lnav" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ))
  ];
}
