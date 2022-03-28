{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.k3s.single-node;
  cil = cfg.cilium;
  
  valuesFormat = pkgs.formats.yaml {};
  
  cilium-configure = (pkgs.writeShellApplication {
    name = "cilium-configure";
    runtimeInputs = with pkgs; [ kubernetes-helm kubectl ];
    text = ''
      export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
      namespace="${cil.namespace}"
      kubectl get namespace "$namespace" || kubectl create namespace "$namespace"
      args=(
        --repo=https://helm.cilium.io/
        --namespace="$namespace"
        --version="${cil.version}"
        --values="${valuesFormat.generate "values.yaml" cil.values}"
        --wait
        "$@"
      )
      helm upgrade --install "''${args[@]}" cilium cilium
    '';
  });
in {
  options.nazarewk.k3s.single-node = {
    enable = mkEnableOption "local (single node) k3s setup";

    enableEraseScript = mkOption {
      default = cfg.enable;
      type = lib.types.bool;
    };

    cni = mkOption {
      default = "cilium";
      type = types.enum [
        "cilium"
      ];
    };

    podCIDR = mkOption {
      type = types.str;
      default = "10.42.0.0/16";
    };

    serviceCIDR = mkOption {
      type = types.str;
      default = "10.43.0.0/16";
    };

    clusterDNS = mkOption {
      type = types.str;
      default = "10.43.0.10";
    };

    nodeCIDRMask = mkOption {
      type = types.ints.unsigned;
      default = 18;
    };

    zfsVolume = mkOption {
      type = types.str;
      default = "";
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
    };

    cilium = {
      version = mkOption {
        default = "1.11.2";
        type = types.str;
      };

      namespace = mkOption {
        default = "kube-system";
        type = types.str;
      };

      replaceKubeProxy = mkOption {
        default = true;
        type = lib.types.bool;
      };

      hubble = mkOption {
        default = true;
        type = lib.types.bool;
      };

      values = mkOption {
        type = valuesFormat.type;
        default = {};
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enableEraseScript {
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "k3s-erase";
          runtimeInputs = with pkgs; [ systemd findutils coreutils util-linux gawk ];
          text = builtins.readFile ./k3s-erase.sh;
        })
      ];
    })
    (mkIf cfg.enable (mkMerge [
      {
        # see Cilium https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
        # inspired by https://github.com/Mic92/dotfiles/tree/master/nixos/modules/k3s

        # This is required so that pod can reach the API server (running on port 6443 by default)
        networking.firewall.allowedTCPPorts = [
          6443
          443
        ];

        # TODO: figure out why firewall is preventing Cilium from working
        networking.firewall.enable = false;

        boot.initrd.kernelModules = [
          "iptable_mangle"
          "iptable_raw"
          "iptable_filter"
        ];

        services.k3s.enable = true;
        # also runs as agent
        services.k3s.role = "server";
        services.k3s.extraFlags = lib.escapeShellArgs (map toString cfg.extraFlags);

        nazarewk.k3s.single-node.extraFlags = [
          "--cluster-cidr=${cfg.podCIDR}"
          "--service-cidr=${cfg.serviceCIDR}"
          "--cluster-dns=${cfg.clusterDNS}"
          "--kube-controller-manager-arg=--node-cidr-mask-size=${toString cfg.nodeCIDRMask}"
        ];

        environment.systemPackages = with pkgs; [
          k3s
        ];
      }
      (mkIf (cfg.zfsVolume != "") {
        # use external containerd on ZFS root
        # see https://nixos.wiki/wiki/K3s
        virtualisation.containerd.enable = true;

        nazarewk.k3s.single-node.extraFlags = [
          "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
        ];

        systemd.services.containerd.serviceConfig = {
          ExecStartPre = [
            "-${pkgs.zfs}/bin/zfs create -o mountpoint=/var/lib/containerd/io.containerd.snapshotter.v1.zfs ${cfg.zfsVolume}"
            "-${pkgs.zfs}/bin/zfs mount ${cfg.zfsVolume} || true"
          ];
        };

        systemd.services.k3s = {
          requires = ["containerd.service"];
          after = ["containerd.service"];
        };
      })
      (mkIf (cfg.cni == "cilium") (mkMerge [
        {
          # see Cilium at https://docs.cilium.io/en/stable/operations/system_requirements/#firewall-rules
          networking.firewall.allowedTCPPorts = [
            # 2379 2380 # etcd
            4240  # health checks
            4244  # hubble server
            4245  # hubble relay
            6060  # cilium-agent pprof server (listening on 127.0.0.1)
            6061  # cilium-operator pprof server (listening on 127.0.0.1)
            6062  # Hubble Relay pprof server (listening on 127.0.0.1)
            6942  # operator Prometheus metrics
            9090  # cilium-agent Prometheus metrics
            9876  # cilium-agent health status API
            9890  # cilium-agent gops server (listening on 127.0.0.1)
            9891  # operator gops server (listening on 127.0.0.1)
            9892  # clustermesh-apiserver gops server (listening on 127.0.0.1)
            9893  # Hubble Relay gops server (listening on 127.0.0.1)
          ];
          networking.firewall.allowedUDPPorts = [
            8472 # VXLAN overlay
          ];
          environment.systemPackages = with pkgs; [
            cilium-cli
            cilium-configure

            iptables  # for debugging

            (pkgs.writeShellApplication {
              name = "k3s-cilium";
              runtimeInputs = with pkgs; [ cilium-cli ];
              text = ''
                export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
                cilium "$@"
              '';
            })
          ];

          systemd.services.k3s.serviceConfig = {
            ExecStartPost = [
              "-${cilium-configure}/bin/cilium-configure --kubeconfig=/etc/rancher/k3s/k3s.yaml"
            ];
          };

          nazarewk.k3s.single-node.extraFlags = [
            "--flannel-backend=none"
            "--disable-network-policy"
          ];

          virtualisation.containerd.settings = {
            plugins."io.containerd.grpc.v1.cri".cni = {
              # calico installs binaries there
              bin_dir = "/opt/cni/bin";
            };
          };

          nazarewk.k3s.single-node.cilium.values = {
            hubble.relay.enabled = true;
            hubble.ui.enabled = true;

            operator.replicas = 1;
            containerRuntime.integration = "containerd";
            k8s.requireIPv4PodCIDR = true;
            ipam.mode = "kubernetes";

            ipam.operator.clusterPoolIPv4PodCIDRList = [ cfg.podCIDR ];
            ipam.operator.clusterPoolIPv4MaskSize = cfg.nodeCIDRMask;
          };

          # systemd 245+ introduced defaults incompatible with Cilium, we need to fix it manually:
          # see note at https://docs.cilium.io/en/stable/operations/system_requirements/#linux-distribution-compatibility-matrix
          boot.kernel.sysctl = {
            "net.ipv4.conf.lxc*.rp_filter" = 0;
          };
        }
        (mkIf (cil.replaceKubeProxy) {
          nazarewk.k3s.single-node.extraFlags = [
            "--disable-kube-proxy"
          ];
          nazarewk.k3s.single-node.cilium.values = {
            kubeProxyReplacement = "strict";
          };
        })
        (mkIf (cil.hubble) {
          nazarewk.k3s.single-node.cilium.values = {
            hubble.relay.enabled = true;
            hubble.ui.enabled = true;
          };
          environment.systemPackages = with pkgs; [
            hubble
          ];
        })
      ]))
    ]))
  ];
}