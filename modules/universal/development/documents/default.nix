{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.documents = {
            enable = lib.mkEnableOption "documents development";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.documents;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            programs.helix.extraPackages = with pkgs; [
              marksman
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
            home-manager.sharedModules = [{kdn.development.documents.enable = true;}];
          };
        }
      )
    )
  ];
}
