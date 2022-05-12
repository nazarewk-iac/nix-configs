{ lib, pkgs, config, flakeInputs, system, ... }:
with lib;
let
  cfg = config.nazarewk.development.nodejs;
in
{
  options.nazarewk.development.nodejs = {
    enable = mkEnableOption "Node JS development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # dev software
      nodejs
      yarn
    ];

    home-manager.sharedModules = [
      {
        home.file.".npmrc".text = ''
          cache=~/.cache/npm
          prefix=~/.cache/npm-global
        '';
      }
    ];
  };
}
