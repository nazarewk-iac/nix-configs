{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.docker;
in
{
  options.kdn.docker = {
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
