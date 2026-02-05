{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: {
  options.kdn.services.k8s.node = {
    enable = lib.mkEnableOption "kubernetes node configuration";
    packages.default = lib.mkOption {
      type = lib.types.package;
      default = config.kdn.services.k8s.packages.default;
    };
    packages.containerd = lib.mkOption {
      type = lib.types.package;
      default = config.kdn.services.k8s.packages.containerd;
    };

    packages.cri-tools = lib.mkOption {
      type = lib.types.package;
      default = config.kdn.services.k8s.packages.cri-tools;
    };
  };

  config = lib.mkIf (config.kdn.services.k8s.enable && config.kdn.services.k8s.node.enable) (lib.mkMerge [
    {
      boot.kernelModules = ["overlay" "br_netfilter"];
      boot.kernel.sysctl = {
        "net.bridge.bridge-nf-call-iptables" = 1;
        "net.bridge.bridge-nf-call-ip6tables" = 1;
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
      # TODO: switch it to assertion?
      swapDevices = lib.mkForce [];
    }
    {
      kdn.toolset.network.enable = true;
      environment.systemPackages = with pkgs; [
        nerdctl
      ];
    }
    {
      kdn.disks.persist."sys/config".directories = [
        "/etc/kubernetes"
      ];
      kdn.disks.persist."sys/config".files = [
        "/etc/default/kubelet"
      ];
      kdn.disks.persist."sys/data".directories = [
        "/var/lib/kubelet"
      ];
    }
    {
      kdn.disks.persist."sys/data".directories = [
        "/var/lib/etcd"
      ];
    }
    {
      kdn.disks.persist."sys/data".directories = [
        "/var/lib/containerd"
      ];

      kdn.fs.zfs.containers.fsname = "${config.kdn.disks.zpool-main.name}/containerd/storage";
      disko.devices.zpool."${config.kdn.disks.zpool-main.name}" = {
        datasets."containerd/storage" = {
          type = "zfs_volume";
          options."com.sun:auto-snapshot" = "false";
          extraArgs = ["-p"]; # create parents, this is missing from the volume
        };
      };
    }
  ]);
}
