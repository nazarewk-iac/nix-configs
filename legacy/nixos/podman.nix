{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman.enable = true;
  virtualisation.podman.dockerCompat = true;
  virtualisation.podman.dockerSocket.enable = true;
  virtualisation.containers.containersConf.settings.storage.driver = "zfs";
}