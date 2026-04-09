{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.nodejs;
in
{
  options.kdn.development.nodejs = {
    enable = lib.mkEnableOption "Node JS development";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.helix.extraPackages = with pkgs; [ typescript-language-server ];
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          # dev software
          nodejs
          yarn
        ];

        home-manager.sharedModules = [
          { kdn.development.nodejs.enable = true; }
          {
            home.file.".npmrc".text = ''
              cache=~/.cache/npm
              prefix=~/.cache/npm-global
            '';
          }
        ];
      }
    ))
  ];
}
