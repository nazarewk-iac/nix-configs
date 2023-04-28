{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.containers;
in
{
  options.kdn.containers = {
    enable = lib.mkEnableOption "container development setup";
  };

  config = lib.mkIf cfg.enable {
    kdn.containers.podman.enable = lib.mkDefault true;
    kdn.containers.docker.enable = lib.mkDefault (!config.kdn.containers.podman.enable);

    environment.systemPackages = with pkgs; [
      buildah
      buildkit
      dive
      skopeo
    ];
  };
}
