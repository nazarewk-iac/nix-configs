{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.virtualisation.containers.docker;
in
{
  options.kdn.virtualisation.containers.docker = {
    enable = lib.mkEnableOption "docker daemon setup";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    environment.gnome.excludePackages = with pkgs; [
      docker
      docker-client
      docker-compose
    ];
  };
}
