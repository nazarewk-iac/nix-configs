{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.web = {
            enable = lib.mkEnableOption "web development";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.web;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            kdn.development.nodejs.enable = true;
            programs.helix.extraPackages = with pkgs; [
              vscode-langservers-extracted
            ];
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.development.db;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.development.web.enable = true;}];
            kdn.development.nodejs.enable = true;
          };
        }
      )
    )
  ];
}
