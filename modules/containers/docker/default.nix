{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.containers.docker;
in
{
  options.kdn.containers.docker = {
    enable = lib.mkEnableOption "docker daemon setup";
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
