{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.programs.kdeconnect = {
            enable = lib.mkEnableOption "kdeconnect setup";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.programs.kdeconnect;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
            lib.mkMerge [
              {
                services.kdeconnect.enable = true;
                services.kdeconnect.indicator = true;
                services.kdeconnect.package = config.kdn.apps.kdeconnect.package.final;
                kdn.apps.kdeconnect = {
                  enable = true;
                  package.original = pkgs.kdePackages.kdeconnect-kde;
                  dirs.cache = [];
                  dirs.config = ["kdeconnect"];
                  dirs.data = [];
                  dirs.disposable = [];
                  dirs.reproducible = [];
                  dirs.state = [];
                };
              }
            ]
          )));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.programs.kdeconnect;
        in {

          config = lib.mkIf cfg.enable (
              lib.mkMerge [
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.kdeconnect = lib.mkDefault cfg;}];})
{home-manager.sharedModules = [{kdn.programs.kdeconnect.enable = true;}];}
              {
                # takes care of firewall
                programs.kdeconnect.enable = true;
              }
            ]
          );
        }
      )
    )
  ];
}
