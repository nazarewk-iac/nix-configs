{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.services.k8s.kubeadm;
  nCfg = config.kdn.services.k8s.node;
  clusterCfg = lib.pipe kdnConfig.k8s.clusters [
    builtins.attrValues
    (lib.lists.findFirst (clusterCfg: clusterCfg.isMember) {})
  ];

  configFormat = pkgs.formats.json {};
in {
  # inspired by https://joshrosso.com/c/nix-k8s/
  options.kdn.services.k8s.kubeadm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = clusterCfg != {};
    };
    config.cluster = lib.mkOption {
      type = configFormat.type;
    };
  };

  config = lib.mkIf (config.kdn.services.k8s.enable && cfg.enable) (lib.mkMerge [
    {
      # TODO: address this
      networking.firewall.enable = false;
    }
    {
      kdn.networking.netbird.clients.priv.enable = false;
    }
    {
      kdn.services.k8s.node.enable = true;
      virtualisation.containerd.enable = true;
      virtualisation.containerd.configFile = ./containerd-config.toml;
      environment.systemPackages = [
        nCfg.packages.default
        nCfg.packages.cri-tools
        nCfg.packages.containerd
      ];
    }
    {
      systemd.services.kubelet = {
        enable = true;
        description = "kubelet";

        serviceConfig = {
          WorkingDirectory = "/var/lib/kubelet";
          ExecStart = "${nCfg.packages.default}/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS";
          Environment = [
            "\"KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf\""
            "\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\""
          ];
          EnvironmentFile = [
            "-/var/lib/kubelet/kubeadm-flags.env"
            "-/etc/default/kubelet"
          ];
          Restart = "always";
          StartLimitInterval = 0;
          RestartSec = 10;
        };
        wantedBy = ["network-online.target"];
        after = ["network-online.target"];
        path = [
          # TODO: could probably put concrete dependenies in here?
          "/run/wrappers"
          "/root/.nix-profile"
          "/etc/profiles/per-user/root"
          "/nix/var/nix/profiles/default"
          "/run/current-system/sw"
        ];
      };
    }
    {
      # could try integrating it with easykubenix machinery?
      kdn.services.k8s.kubeadm.config.cluster = {
        apiVersion = "kubeadm.k8s.io/v1beta4";
        kind = "ClusterConfiguration";
        kubernetesVersion = builtins.head clusterCfg.allowedVersions;
        controlPlaneEndpoint = "${clusterCfg.apiserver.domain}:${toString clusterCfg.apiserver.port.shared}";
        networking.podSubnet = builtins.concatStringsSep "," clusterCfg.subnet.pod;
        networking.serviceSubnet = builtins.concatStringsSep "," clusterCfg.subnet.service;
        networking.dnsDomain = clusterCfg.domain;
        apiServer.certSANs =
          [clusterCfg.apiserver.domain]
          ++ lib.pipe (clusterCfg.controlplane.nodes ++ clusterCfg.worker.nodes) [
            lib.lists.unique
            (map (
              hostname: let
                hostConfig = kdnConfig.self.hosts."${hostname}";
                netCfg = hostConfig.kdn.networking;
              in
                # cut out subnet size
                lib.pipe netCfg.iface.internal.address [
                  builtins.attrValues
                  (map (lib.strings.splitString "/"))
                  (map builtins.head)
                ]
            ))
            builtins.concatLists
            (builtins.sort (a: b: a < b))
          ];
        apiServer.extraArgs = [
          {
            name = "bind-address";
            value = "::";
          }
        ];
      };
    }
  ]);
}
