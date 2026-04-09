{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.toolset.mikrotik = {
            enable = lib.mkEnableOption "mikrotik/RouterOS utils";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.toolset.mikrotik;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (lib.mkMerge [
            {
              kdn.emulation.wine.enable = true;
              home.packages = with pkgs; [
                (lib.lowPrio winbox)
              ];
              kdn.apps.winbox4 = {
                enable = true;
                dirs.cache = [];
                dirs.config = [];
                dirs.data = ["MikroTik/WinBox"];
                dirs.disposable = [];
                dirs.reproducible = [];
                dirs.state = [];
              };
            }
          ])));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.toolset.mikrotik;
        in {

          config = lib.mkIf cfg.enable (
              lib.mkMerge [
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.toolset.mikrotik = lib.mkDefault cfg;}];})
{home-manager.sharedModules = [{kdn.toolset.mikrotik.enable = cfg.enable;}];}
            ]
          );
        }
      )
    )
  ];
}
