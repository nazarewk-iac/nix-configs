{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.virtualisation.containers;
in
{
  options.kdn.virtualisation.containers = {
    enable = lib.mkEnableOption "container development setup";
  };

  config = lib.mkIf cfg.enable {
    kdn.virtualisation.containers.podman.enable = lib.mkDefault true;
    kdn.virtualisation.containers.docker.enable = lib.mkDefault (!config.kdn.virtualisation.containers.podman.enable);

    environment.systemPackages = with pkgs; [
      buildah
      buildkit
      dive
      skopeo
    ];
  };
}
