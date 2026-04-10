{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.nodejs = {
            enable = lib.mkEnableOption "Node JS development";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.nodejs;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            programs.helix.extraPackages = with pkgs; [
              typescript-language-server
            ];
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.development.nodejs;
        in {

          config = lib.mkIf cfg.enable {
            environment.systemPackages = with pkgs; [
              # dev software
              nodejs
              yarn
            ];

            home-manager.sharedModules = [
              {kdn.development.nodejs.enable = true;}
              {
                home.file.".npmrc".text = ''
                  cache=~/.cache/npm
                  prefix=~/.cache/npm-global
                '';
              }
            ];
          };
        }
      )
    )
  ];
}
