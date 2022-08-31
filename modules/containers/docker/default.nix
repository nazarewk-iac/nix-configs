{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.docker;
in
{
  options.nazarewk.docker = {
    enable = mkEnableOption "docker daemon setup";
  };

  config = mkIf cfg.enable {
    virtualisation.docker.enable = true;

    environment.gnome.excludePackages = with pkgs; [
      docker
      docker-client
      docker-compose
    ];
  };
}
