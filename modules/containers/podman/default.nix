{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.containers.podman;
in
{
  options.kdn.containers.podman = {
    enable = lib.mkEnableOption "Podman setup";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault false;

    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman.enable = true;
    virtualisation.podman.dockerCompat = lib.mkDefault false;
    virtualisation.podman.dockerSocket.enable = !config.virtualisation.docker.enable;
    virtualisation.containers.containersConf.settings.storage.driver = "zfs";

    environment.systemPackages = with pkgs; [
      # podman # conflicts with option's wrapper
      buildah
    ];
  };
}
