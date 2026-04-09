{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.web;
in
{
  options.kdn.development.web = {
    enable = lib.mkEnableOption "web development";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        kdn.development.nodejs.enable = true;
        programs.helix.extraPackages = with pkgs; [ vscode-langservers-extracted ];
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.development.web.enable = true; } ];
        kdn.development.nodejs.enable = true;
      }
    ))
  ];
}
