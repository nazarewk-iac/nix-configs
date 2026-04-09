{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.documents;
in
{
  options.kdn.development.documents = {
    enable = lib.mkEnableOption "documents development";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.helix.extraPackages = with pkgs; [ marksman ];
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.development.documents.enable = true; } ];
      }
    ))
  ];
}
