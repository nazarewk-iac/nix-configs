{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.toolset.logs-processing = {
            enable = lib.mkEnableOption "logs processing tooling";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.toolset.logs-processing;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            kdn.apps.lnav = {
              # https://lnav.org/
              enable = true;
              package.original = pkgs.lnav;
              dirs.cache = [];
              dirs.config = ["lnav"];
              dirs.data = [];
              dirs.disposable = [];
              dirs.reproducible = [];
              dirs.state = [];
            };
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.toolset.logs-processing;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.toolset.logs-processing.enable = true;}];
            environment.systemPackages =
              (with pkgs; [
                # https://github.com/trungdq88/logmine
                # https://github.com/ynqa/logu
                # https://github.com/logpai/logparser
                angle-grinder # https://github.com/rcoh/angle-grinder
                # https://github.com/dloss/klp
              ])
              ++ [];
          };
        }
      )
    )
  ];
}
