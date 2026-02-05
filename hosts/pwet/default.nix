{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "e3885c11"; # cut -c-8 </proc/sys/kernel/random/uuid
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

      kdn.networking.ifaces."kdn-eth0".selector.mac = "a8:b8:e0:04:10:b5";
      kdn.networking.ifaces."kdn-eth1".selector.mac = "a8:b8:e0:04:10:b6";
      kdn.networking.ifaces."kdn-eth2".selector.mac = "a8:b8:e0:04:10:b7";
      kdn.networking.ifaces."kdn-eth3".selector.mac = "a8:b8:e0:04:10:b8";

      kdn.networking.bonds."lan".type = "lacp";
      kdn.networking.bonds."lan".children = ["kdn-eth0" "kdn-eth1" "kdn-eth2" "kdn-eth3"];
      kdn.networking.ifaces."lan".mac = "42:e0:77:ff:44:b7";
      kdn.networking.ifaces."lan".dynamicIPClient = true;
      kdn.networking.ifaces."lan".metric = 100;

      kdn.networking.vlans."pic".id = 1859;
      kdn.networking.vlans."pic".parent = "lan";
      kdn.networking.ifaces."pic".dynamicIPClient = true;
      kdn.networking.ifaces."pic".metric = 1000;
      kdn.networking.ifaces."pic".address.internal4 = "10.92.0.8/24";
      kdn.networking.ifaces."pic".address.internal6 = "fd12:ed4e:366d:eb17:b31d:36cf:bcb7:4c52/64";
    }
    {
      kdn.disks.enable = true;

      # 250GB for system disk - /dev/disk/by-id/nvme-eui.002538d341a07655
      kdn.disks.devices."${config.kdn.disks.defaults.bootDeviceName}".path = "/dev/disk/by-id/nvme-eui.002538d341a07655";
      kdn.disks.luks.volumes."system-pwet" = {
        uuid = "423e310a-cd6d-47d2-b8fb-3592bf5b7f64";
        target.deviceKey = config.kdn.disks.defaults.bootDeviceName;
        target.partitionKey = "system-pwet";
        targetSpec.size = "100%";
        targetSpec.partNum = 3;
        headerSpec.partNum = 2;
      };

      disko.devices.zpool."${config.kdn.disks.zpool-main.name}" = {
        datasets."luks/data-pwet/header" = {
          type = "zfs_volume";
          options."com.sun:auto-snapshot" = "true";
          extraArgs = ["-p"]; # create parents, this is missing from the volume
          size = lib.mkDefault "${toString config.kdn.disks.luks.header.size}M";
        };
      };

      # 1 TB high durability disk - /dev/disk/by-id/nvme-eui.002538b631a4383d
      kdn.disks.luks.volumes."data-pwet" = {
        uuid = "0f373c09-80bb-4d88-a1cb-d36fb7d829a1";
        targetSpec.path = "/dev/disk/by-id/nvme-eui.002538b631a4383d";
        header.path = "/dev/zvol/${config.kdn.disks.zpool-main.name}/luks/data-pwet/header";
        header.deviceKey = null;
        header.partitionKey = null;
        zpool.name = "pic-local";
      };
      kdn.disks.zpools."pic-local" = {};
    }
    {
      kdn.disks.disko.devices._meta.deviceDependencies = {
        disk.data-pwet = [
          ["zpool" config.kdn.disks.zpool-main.name]
        ];
      };
    }
  ];
}
