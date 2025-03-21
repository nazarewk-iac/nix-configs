{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.nodejs;
in {
  options.kdn.development.nodejs = {
    enable = lib.mkEnableOption "Node JS development";
  };

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
