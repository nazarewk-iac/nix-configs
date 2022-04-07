{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.k3s.single-node;
  cil = cfg.cilium;

  featureGatesString = lib.pipe cfg.featureGates [
    (lib.mapAttrsToList (n: v: "${n}=${toString v}"))
    (builtins.concatStringsSep ",")
  ];

  yaml = pkgs.formats.yaml {};
  
  cilium-configure = pkgs.writeShellApplication {
    name = "cilium-configure";
    runtimeInputs = with pkgs; [ kubernetes-helm kubectl ];
    text = ''
      export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
      namespace="${cil.namespace}"
      kubectl get namespace "$namespace" || kubectl create namespace "$namespace"
      args=(
        --atomic
        --repo=https://helm.cilium.io/
        --namespace="$namespace"
        --version="${cil.version}"
        --values="${yaml.generate "values.yaml" cil.values}"
        --wait
        "$@"
      )
      helm upgrade --install "''${args[@]}" cilium cilium
    '';
  };

  k3s-node-shutdown =  (pkgs.writeShellApplication {
    name = "k3s-node-shutdown";
    runtimeInputs = with pkgs; [ kubectl ];
    text = builtins.readFile ./k3s-node-shutdown.sh;
  });
  k3s-erase = pkgs.writeShellApplication {
    name = "k3s-erase";
    runtimeInputs = with pkgs; [
      systemd
      findutils
      coreutils
      util-linux
      gawk
      nettools # hostname
    ];
    text = builtins.readFile ./k3s-erase.sh;
  };
in {
  options.nazarewk.k3s.single-node = {
    enable = mkEnableOption "local (single node) k3s setup";

    enableScripts = mkOption {
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

    maxPodsPerNode = mkOption {
      type = types.ints.unsigned;
      # TODO: calculate: 2 ** (32 - cfg.nodeCIDRMask) * 0.43
      default = 7045;
    };

    featureGates = mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = {
        GracefulNodeShutdownBasedOnPodPriority = true;
      };
    };

    drainer = {
      enable = mkOption {
        type = lib.types.bool;
        default = true;
      };

      timeouts = {
        initial =  mkOption {
          type = types.ints.unsigned;
          default = 30;
        };
        force = mkOption {
          type = types.ints.unsigned;
          default = 90;
        };
      };
    };

    reservations = {
      system = {
        cpu = mkOption {
          type = types.str;
          default = "500m";
        };
        memory = mkOption {
          type = types.str;
          default = "1G";
        };
      };
      kube = {
        cpu = mkOption {
          type = types.str;
          default = "500m";
        };
        memory = mkOption {
          type = types.str;
          default = "1G";
        };
      };
    };

    zfsVolume = mkOption {
      type = types.str;
      default = "";
    };

    config = {
      k3s = mkOption {
        type = yaml.type;
        default = {};
      };
      
      kubelet = mkOption {
        type = yaml.type;
        default = {};
      };
    };

    kube-prometheus = {
      enable = mkEnableOption "kube-prometheus tweaks";
    };

    rook-ceph = {
      enable = mkEnableOption "Rook Ceph tweaks";
    };

    istio = {
      enable = mkEnableOption "Istio tweaks";
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
        default = false;
        type = lib.types.bool;
      };

      hubble = mkOption {
        default = true;
        type = lib.types.bool;
      };

      values = mkOption {
        type = yaml.type;
        default = {};
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enableScripts {
      environment.systemPackages = [
        k3s-node-shutdown
        k3s-erase
      ];
    })
    (mkIf cfg.enable (mkMerge [
      {
        zramSwap.enable = false;
        # see Cilium https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
        # inspired by https://github.com/Mic92/dotfiles/tree/master/nixos/modules/k3s

        # This is required so that pod can reach the API server (running on port 6443 by default)
        networking.firewall.allowedTCPPorts = [
          6443
          443
        ];

        services.k3s.enable = true;
        # also runs as agent
        services.k3s.role = "server";
        nazarewk.k3s.single-node.config.k3s = {
          secrets-encryption = true;
          cluster-cidr = cfg.podCIDR;
          service-cidr = cfg.serviceCIDR;
          cluster-dns = cfg.clusterDNS;
          kube-apiserver-arg = [
            "--event-ttl=72h"
            "--feature-gates=${featureGatesString}"
          ];
          kube-scheduler-arg = [
            "--feature-gates=${featureGatesString}"
          ];
          kube-controller-manager-arg = [
            "--node-cidr-mask-size=${toString cfg.nodeCIDRMask}"
            "--feature-gates=${featureGatesString}"
          ];
          kubelet-arg = [
            "config=/etc/rancher/k3s/kubelet.config"
          ];
        };

        environment.systemPackages = with pkgs; [
          k3s
        ];

        environment.etc."rancher/k3s/kubelet.config".source = yaml.generate "k3s-config.yaml" cfg.config.kubelet;
        environment.etc."rancher/k3s/config.yaml".source = yaml.generate "k3s-config.yaml" cfg.config.k3s;
        nazarewk.k3s.single-node.config.kubelet = {
          # see https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
          apiVersion = "kubelet.config.k8s.io/v1beta1";
          kind = "KubeletConfiguration";

          # see https://github.com/kubernetes/kubernetes/blob/21184400a4ac185e7e4c6ddb52eb9c25a4cc453f/pkg/kubelet/nodeshutdown/nodeshutdown_manager_linux.go#L420-L442
          # $ kubectl get priorityclasses.scheduling.k8s.io -o wide
          # NAME                      VALUE        GLOBAL-DEFAULT   AGE
          # system-node-critical      2000001000   false            8d
          # system-cluster-critical   2000000000   false            8d
          # WARNING: requires --feature-gates=GracefulNodeShutdownBasedOnPodPriority=true
          shutdownGracePeriodByPodPriority = [
            {
              priority = 2000001000; # system-node-critical
              shutdownGracePeriodSeconds = 60;
            }
            {
              priority = 2000000000; # system-cluster-critical
              shutdownGracePeriodSeconds = 60;
            }
            {
              priority = 1; # give Pods with ANY priority set separate wave of evictions
              shutdownGracePeriodSeconds = 60;
            }
            {
              priority = 0; # default for all Pods
              shutdownGracePeriodSeconds = 60;
            }
          ];
          maxPods = cfg.maxPodsPerNode;

          containerLogMaxSize = "10Mi";
          containerLogMaxFiles = 10;

          systemReserved = cfg.reservations.system;
          kubeReserved = cfg.reservations.kube;
          featureGates = cfg.featureGates;
          logging = {
            # format = "json"; # doesn't work for some reason
          };
        };

        systemd.services.k3s = {
          serviceConfig = {
            TimeoutStartSec = 600;
            Restart = mkForce "on-failure";
          };
        };
      }
      (mkIf cfg.kube-prometheus.enable {
        nazarewk.k3s.single-node.config.k3s.disable = [
          "metrics-server"  # using Prometheus Operator instead
        ];
      })
      (mkIf cfg.istio.enable {
        nazarewk.k3s.single-node.config.k3s.disable = [
          "traefik"  # using Istio ingress instead
        ];
      })
      (mkIf cfg.rook-ceph.enable {
        nazarewk.k3s.single-node.config.k3s.disable = [
          "local-storage"  # using Rook Ceph instead
        ];
        # Can be removed for Rook 1.8.9+ when the PR lands in a release
        # https://github.com/rook/rook/pull/9967
        system.activationScripts.rookLVMLinks = ''
          mkdir -p /sbin
          files=(
            ${pkgs.cryptsetup}/bin/*
            ${pkgs.lvm2.bin}/bin/*
            ${pkgs.parted}/bin/*
            ${pkgs.util-linux.bin}/bin/*
          )
          for file in ''${files[@]}; do
            ln -sf "$file" "/sbin/''${file##*/}"
          done
        '';

        environment.systemPackages = with pkgs; [
          ceph
          cryptsetup
          lvm2
          parted
          util-linux
        ];
        boot.initrd.kernelModules = [
          # Rook Ceph
          "rbd"
          "nbd"
        ];
      })
      (mkIf cfg.drainer.enable {
        systemd.services.k3s = {
          # restartIfChanges seems to make a full stop, then full start which triggers drainer
          restartIfChanged = false;
          #unitConfig = {
          #  Upholds = [ "k3s-drainer.service" ];
          #};
        };
        systemd.services.k3s-drainer = {
          restartIfChanged = false;
          description = "drains Kubernetes node before k3s stops";
          wants = [ "k3s.service" ];
          after = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          unitConfig = {
            StopPropagatedFrom = [ "k3s.service" ];
          };
          environment = {
            KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          };
          serviceConfig = let
            k = "${pkgs.kubectl}/bin/kubectl";
            drain = "${k} drain --by-priority --delete-emptydir-data --ignore-daemonsets";
          in {
            RemainAfterExit = true;
            RestartSec = 30;
            TimeoutStopSec = cfg.drainer.timeouts.initial + cfg.drainer.timeouts.force;
            ExecStart = "${k} uncordon ${config.networking.hostName}";
            ExecStop = [
              "-${drain} --timeout ${toString cfg.drainer.timeouts.initial}s ${config.networking.hostName}"
              "${drain} --timeout ${toString cfg.drainer.timeouts.force}s --disable-eviction ${config.networking.hostName}"
            ];
          };
        };
      })
      (mkIf (cfg.zfsVolume != "") {
        # use external containerd on ZFS root
        # see https://nixos.wiki/wiki/K3s
        virtualisation.containerd.enable = true;
        virtualisation.containerd.settings = {
          plugins."io.containerd.grpc.v1.cri".containerd = {
            snapshotter = "zfs";
          };
        };

        nazarewk.k3s.single-node.config.k3s = {
          container-runtime-endpoint = "/run/containerd/containerd.sock";
          kubelet-arg = [ "containerd=unix:///run/containerd/containerd.sock" ];
        };

        systemd.services.containerd.serviceConfig = {
          ExecStartPre = [
            "-${pkgs.zfs}/bin/zfs create -o mountpoint=/var/lib/containerd/io.containerd.snapshotter.v1.zfs ${cfg.zfsVolume}"
            "-${pkgs.zfs}/bin/zfs mount ${cfg.zfsVolume}"
          ];
        };

        systemd.services.k3s = {
          requires = ["containerd.service"];
          after = ["containerd.service"];
        };
      })
      (mkIf (cfg.cni == "cilium") (mkMerge [
        {
          # TODO: figure out why firewall is preventing Cilium from working
          networking.firewall.enable = false;

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
          ];

          boot.initrd.kernelModules = [
            # cilium
            "iptable_mangle"
            "iptable_raw"
            "iptable_filter"
          ];

          systemd.services.k3s.serviceConfig = {
            ExecStartPost = let
              wait-for-k3s = (pkgs.writeShellApplication {
                name = "wait-for-k3s";
                runtimeInputs = with pkgs; [ pkgs.k3s ];
                text = ''
                  until ${pkgs.k3s}/bin/k3s kubectl get node >/dev/null ; do
                    sleep 5
                  done
                '';
              });
            in [
#              "${wait-for-k3s}/bin/wait-for-k3s"
#              "-${cilium-configure}/bin/cilium-configure --kubeconfig=/etc/rancher/k3s/k3s.yaml"
            ];
          };
          nazarewk.k3s.single-node.config.k3s = {
            flannel-backend = "none";
            disable-network-policy = true;
          };

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
          nazarewk.k3s.single-node.config.k3s = {
            disable-kube-proxy = true;
          };
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
