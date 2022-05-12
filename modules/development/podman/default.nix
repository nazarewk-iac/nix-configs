{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.podman;
in
{
  options.nazarewk.development.podman = {
    enable = mkEnableOption "Podman setup";
  };

  config = mkIf cfg.enable {
    virtualisation.docker.enable = false;

    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman.enable = true;
    virtualisation.podman.dockerCompat = true;
    virtualisation.podman.dockerSocket.enable = false;
    virtualisation.containers.containersConf.settings.storage.driver = "zfs";
  };
}
