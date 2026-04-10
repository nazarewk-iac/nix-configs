{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.toolset.ide = {
            enable = lib.mkEnableOption "IDEs utils";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.toolset.ide;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (lib.mkMerge [
            {
              kdn.programs.terminal-ide.enable = true;
            }
            (lib.mkIf config.kdn.desktop.enable {
              kdn.development.jetbrains.enable = true;
            })
          ])));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.toolset.ide;
        in {

          config = lib.mkIf cfg.enable (
              lib.mkMerge [
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.toolset.ide = lib.mkDefault cfg;}];})
{home-manager.sharedModules = [{kdn.toolset.ide.enable = cfg.enable;}];}
            ]
          );
        }
      )
    )
  ];
}
