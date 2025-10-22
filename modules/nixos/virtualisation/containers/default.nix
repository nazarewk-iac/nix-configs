{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.containers;
in {
  options.kdn.virtualisation.containers = {
    enable = lib.mkEnableOption "container development setup";
  };

  config = lib.mkIf cfg.enable {
    kdn.virtualisation.containers.podman.enable = lib.mkDefault true;
    kdn.virtualisation.containers.docker.enable = lib.mkDefault (!config.kdn.virtualisation.containers.podman.enable);

    virtualisation.containers.storage.settings.storage.driver = lib.mkDefault "overlay";
    virtualisation.containers.storage.settings.storage.runroot =
      lib.mkDefault "/run/containers/storage";
    virtualisation.containers.storage.settings.storage.graphroot =
      lib.mkDefault "/var/lib/containers/storage";

    environment.systemPackages = with pkgs; [
      buildah
      buildkit
      dive
      skopeo
    ];

    kdn.hw.disks.persist."usr/cache".directories = [
      "/var/lib/containers/cache"
    ];
    kdn.hw.disks.persist."usr/data".directories = [
      "/var/lib/containers/storage"
    ];
    home-manager.sharedModules = [
      {
        kdn = {
          virtualisation.containers.enable = true;
        };
      }
    ];
  };
}
