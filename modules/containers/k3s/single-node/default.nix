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
        # "calico"
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
        default = cfg.cni == "cilium";
        type = lib.types.bool;
      };

      values = mkOption {
        type = valuesFormat.type;
        default = {
          operator = {
            replicas = 1;
          };
          containerRuntime = {
            integration = "containerd";
          };
          k3s = {
            requireIPv4PodCIDR = true;
          };
          ipam = {
            mode = "kubernetes";

            operator = {
              clusterPoolIPv4PodCIDRList = [
                cfg.podCIDR
              ];
              clusterPoolIPv4MaskSize = cfg.nodeCIDRMask;
            };
          };
        };
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
        # networking.firewall.allowedTCPPorts = [ 6443 ];
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
        # see https://nixos.wiki/wiki/K3s
        virtualisation.containerd.enable = true;

        nazarewk.k3s.single-node.extraFlags = [
          "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
        ];

        systemd.services.containerd.serviceConfig = lib.mkIf config.boot.zfs.enabled {
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
          environment.systemPackages = with pkgs; [
            cilium-cli
            cilium-configure

            (pkgs.writeShellApplication {
              name = "k3s-cilium";
              runtimeInputs = with pkgs; [ cilium-cli ];
              text = ''
                export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
                cilium "$@"
              '';
            })
          ];

  #        systemd.services.k3s.serviceConfig = {
  #          ExecStartPost = [
  #            "-${cilium-configure}/bin/cilium-configure"
  #          ];
  #        };

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
        }
        (mkIf (cil.replaceKubeProxy) {
          nazarewk.k3s.single-node.extraFlags = [
            "--disable-kube-proxy"
          ];
          nazarewk.k3s.single-node.cilium.values = {
            kubeProxyReplacement = "strict";
          };
        })
      ]))
      (mkIf (cfg.cni == "calico") {
        # Calico doesn't work due to no FHS
        environment.shellAliases = {
          # k3s kubectl apply -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
          # k3s kubectl apply -f https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
          # k3s kubectl apply -f https://projectcalico.docs.tigera.io/manifests/calicoctl.yaml
          calicoctl = "${k3s} kubectl exec -i -n kube-system calicoctl -- /calicoctl";
        };
        virtualisation.containerd.settings = {
          plugins."io.containerd.grpc.v1.cri".cni = {
            # calico installs binaries there
            bin_dir = "/opt/cni/bin";
          };
        };
      })
    ]))
  ];
}