{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.containers.podman;
in {
  options.kdn.virtualisation.containers.podman = {
    enable = lib.mkEnableOption "Podman setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      virtualisation.docker.enable = lib.mkDefault false;
      virtualisation.podman.enable = true;

      virtualisation.podman.defaultNetwork.settings = {
        dns_enabled = true;
      };

      virtualisation.oci-containers.backend = "podman";
      virtualisation.podman.dockerCompat = !config.virtualisation.docker.enable;
      virtualisation.podman.dockerSocket.enable = !config.virtualisation.docker.enable;

      # see https://github.com/NixOS/nixpkgs/issues/226365#issuecomment-1814296639
      networking.firewall.interfaces."podman*".allowedUDPPorts = [53];

      boot.kernel.sysctl."user.max_user_namespaces" = 15000;
    }
    {
      /*
      fixes `Error: netavark: code: 1, msg: iptables: Chain already exists.` when running more than 1 container
      - https://github.com/containers/netavark/issues/274
      - (fix) https://github.com/containers/netavark/issues/339#issuecomment-2080432677
      */
      virtualisation.containers.containersConf.settings.network.network_backend = lib.mkDefault "netavark";
      virtualisation.containers.containersConf.settings.network.firewall_driver = lib.mkDefault "nftables";
    }
  ]);
}
