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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          # dev software
          nodejs
          yarn
        ];
      }
      (kdnConfig.util.ifHM {
        programs.helix.extraPackages = with pkgs; [ typescript-language-server ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        home-manager.sharedModules = [
          { kdn.development.nodejs.enable = true; }
          {
            home.file.".npmrc".text = ''
              cache=~/.cache/npm
              prefix=~/.cache/npm-global
            '';
          }
        ];
      })
    ]
  );
}
