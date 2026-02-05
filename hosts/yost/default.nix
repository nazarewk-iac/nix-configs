{
  config,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "yost";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "81305e2c"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.hw.cpu.intel.enable = true;
      security.sudo.wheelNeedsPassword = false;

      zramSwap.enable = false;

      boot.tmp.tmpfsSize = "4G";
      boot.initrd.kernelModules = [
        "sdhci"
        "sdhci_pci"
      ];
    }
    {
      kdn.services.k8s.enable = true;
      kdn.services.k8s.kubeadm.enable = true;

      kdn.networking.enable = true;
      kdn.networking.iface.default = "lan";
      kdn.networking.iface.internal = "pic";

      kdn.networking.ifaces."kdn-eth0".selector.mac = "a8:b8:e0:04:12:f1";
      kdn.networking.ifaces."kdn-eth1".selector.mac = "a8:b8:e0:04:12:f2";
      kdn.networking.ifaces."kdn-eth2".selector.mac = "a8:b8:e0:04:12:f3";
      kdn.networking.ifaces."kdn-eth3".selector.mac = "a8:b8:e0:04:12:f4";

      kdn.networking.bonds."lan".type = "lacp";
      kdn.networking.bonds."lan".children = ["kdn-eth0" "kdn-eth1" "kdn-eth2" "kdn-eth3"];
      kdn.networking.ifaces."lan".mac = "6e:8f:d1:7e:15:4a";
      kdn.networking.ifaces."lan".dynamicIPClient = true;
      kdn.networking.ifaces."lan".metric = 100;

      kdn.networking.vlans."pic".id = 1859;
      kdn.networking.vlans."pic".parent = "lan";
      kdn.networking.ifaces."pic".dynamicIPClient = true;
      kdn.networking.ifaces."pic".metric = 1000;
      kdn.networking.ifaces."pic".address.internal4 = "10.92.0.10/24";
      kdn.networking.ifaces."pic".address.internal6 = "fd12:ed4e:366d:eb17:5205:6552:3956:1447/64";
    }
    {
      kdn.disks.enable = true;

      # 250GB for system disk - /dev/disk/by-id/nvme-eui.002538d341a07650
      kdn.disks.devices."${config.kdn.disks.defaults.bootDeviceName}".path = "/dev/disk/by-id/nvme-eui.002538d341a07650";
      kdn.disks.luks.volumes."system-yost" = {
        uuid = "f78b56c0-1736-4f63-8ccf-07277ecdd6b9";
        target.deviceKey = config.kdn.disks.defaults.bootDeviceName;
        target.partitionKey = "system-yost";
        targetSpec.size = "100%";
        targetSpec.partNum = 3;
        headerSpec.partNum = 2;
      };

      disko.devices.zpool."${config.kdn.disks.zpool-main.name}" = {
        datasets."luks/data-yost/header" = {
          type = "zfs_volume";
          options."com.sun:auto-snapshot" = "true";
          extraArgs = ["-p"]; # create parents, this is missing from the volume
          size = lib.mkDefault "${toString config.kdn.disks.luks.header.size}M";
        };
      };

      # 1 TB high durability disk - /dev/disk/by-id/nvme-eui.002538b631a43840
      kdn.disks.luks.volumes."data-yost" = {
        uuid = "2641827a-e09d-4832-9492-243b35e0305b";
        targetSpec.path = "/dev/disk/by-id/nvme-eui.002538b631a43840";
        header.path = "/dev/zvol/${config.kdn.disks.zpool-main.name}/luks/data-yost/header";
        header.deviceKey = null;
        header.partitionKey = null;
        zpool.name = "pic-local";
      };
      kdn.disks.zpools."pic-local" = {};
    }
    {
      kdn.disks.disko.devices._meta.deviceDependencies = {
        disk.data-yost = [
          ["zpool" config.kdn.disks.zpool-main.name]
        ];
      };
    }
  ];
}
