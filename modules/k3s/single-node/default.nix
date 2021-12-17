{ pkgs, ... }: {
  # see https://nixos.wiki/wiki/K3s
  virtualisation.containerd.enable = true;
  virtualisation.containers.containersConf.settings.storage.driver = "zfs";
  services.k3s.docker = false;

  # This is required so that pod can reach the API server (running on port 6443 by default)
  # networking.firewall.allowedTCPPorts = [ 6443 ];
  services.k3s.enable = true;
  # also runs as agent
  services.k3s.role = "server";
  services.k3s.extraFlags = toString [
    # "--kubelet-arg=v=4" # Optionally add additional args to k3s
    "--container-runtime-endpoint unix:///run/containerd/containerd.sock"
  ];
}