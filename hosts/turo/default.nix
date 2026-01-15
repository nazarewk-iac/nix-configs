{
  config,
  lib,
  kdnConfig,
  ...
}: let
  ifaces.lan."kdn-eth0".mac = "a8:b8:e0:04:13:0d";
  ifaces.lan."kdn-eth1".mac = "a8:b8:e0:04:13:0e";
  ifaces.lan."kdn-eth2".mac = "a8:b8:e0:04:13:0f";
  ifaces.lan."kdn-eth3".mac = "a8:b8:e0:04:13:10";

  bonds = {};
  bonds.lan.children = builtins.attrNames ifaces.lan;
  bonds.lan.iface = "lan";
  bonds.lan.metric = 100;

  vlans = {};
  vlans.pic.iface = "pic";
  vlans.pic.id = 1859;
  vlans.pic.parent = bonds.lan // {name = "lan";};
in {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "turo";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "0f4fc33f"; # cut -c-8 </proc/sys/kernel/random/uuid
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
      kdn.disks.enable = true;

      # 250GB for system disk - /dev/disk/by-id/nvme-eui.002538d341a07655
      kdn.disks.devices."${config.kdn.disks.defaults.bootDeviceName}".path = "/dev/disk/by-id/nvme-eui.002538d341a07652";
      kdn.disks.luks.volumes."system-turo" = {
        uuid = "ef38c899-33de-4c41-9c74-bad311c2b293";
        target.deviceKey = config.kdn.disks.defaults.bootDeviceName;
        target.partitionKey = "system-turo";
        targetSpec.size = "100%";
        targetSpec.partNum = 3;
        headerSpec.partNum = 2;
      };

      disko.devices.zpool."${config.kdn.disks.zpool-main.name}" = {
        datasets."luks/data-turo/header" = {
          type = "zfs_volume";
          options."com.sun:auto-snapshot" = "true";
          extraArgs = ["-p"]; # create parents, this is missing from the volume
          size = lib.mkDefault "${builtins.toString config.kdn.disks.luks.header.size}M";
        };
      };

      # 1 TB high durability disk - /dev/disk/by-id/nvme-eui.002538b631a43842
      kdn.disks.luks.volumes."data-turo" = {
        uuid = "29814ef8-632e-4c37-a1b8-541eecb45488";
        targetSpec.path = "/dev/disk/by-id/nvme-eui.002538b631a43842";
        header.path = "/dev/zvol/${config.kdn.disks.zpool-main.name}/luks/data-turo/header";
        header.deviceKey = null;
        header.partitionKey = null;
        zpool.name = "turo-data";
      };
      kdn.disks.zpools."turo-data" = {};
    }
    {
      kdn.disks.disko.devices._meta.deviceDependencies = {
        disk.data-turo = [
          ["zpool" config.kdn.disks.zpool-main.name]
        ];
      };
    }
    {
      networking.networkmanager.unmanaged =
        lib.attrsets.mapAttrsToList (_: entry: "mac:${entry.mac}") ifaces.lan;

      systemd.network.networks = lib.pipe ifaces [
        (lib.attrsets.mapAttrsToList (netName: netIfaces:
          lib.attrsets.mapAttrsToList (name: iface: {
            "50-${name}" = {
              matchConfig.Name = name;
            };
          })
          netIfaces))
        builtins.concatLists
        lib.mkMerge
      ];
      systemd.network.links = lib.pipe ifaces [
        (lib.attrsets.mapAttrsToList (netName: netIfaces:
          lib.attrsets.mapAttrsToList (name: iface: {
            "00-${name}" = {
              matchConfig.PermanentMACAddress = iface.mac;
              linkConfig.AlternativeName = name;
            };
          })
          netIfaces))
        builtins.concatLists
        lib.mkMerge
      ];
    }
    {
      # TODO: bond is stuck in `configuring` state, enable networkd debug logs and retry?
      networking.networkmanager.unmanaged = lib.attrsets.mapAttrsToList (_: entry: "interface-name:${entry.iface}") bonds;
      systemd.network.netdevs = lib.pipe bonds [
        (lib.attrsets.mapAttrsToList (name: bond: {
          "50-${name}" = {
            netdevConfig.Kind = "bond";
            netdevConfig.Name = bond.iface;
            bondConfig = {
              Mode = "802.3ad";
              TransmitHashPolicy = "layer2+3";
              LACPTransmitRate = "fast";
              MIIMonitorSec = "100ms";
            };
          };
        }))
        lib.mkMerge
      ];
      systemd.network.networks = lib.pipe bonds [
        (lib.attrsets.mapAttrsToList (name: bond:
          (builtins.map (iface: {
              "50-${iface}" = {
                networkConfig.Bond = bond.iface;
              };
            })
            bond.children)
          ++ [
            {
              "50-${name}" = {
                matchConfig.Name = bond.iface;
                linkConfig = {
                  RequiredForOnline = "yes";
                  RequiredFamilyForOnline = "ipv4";
                };
                networkConfig = {
                  DHCP = true;
                  UseDomains = true;

                  IPv6AcceptRA = true;
                  LinkLocalAddressing = "ipv6";

                  IPv6PrivacyExtensions = true;
                  IPv6LinkLocalAddressGenerationMode = "stable-privacy";
                };

                linkConfig.Multicast = true; # required for IPv6AcceptRA to take effect on bond interface
                dhcpV4Config.RouteMetric = bond.metric;
                dhcpV6Config.RouteMetric = bond.metric;
              };
            }
          ]))
        builtins.concatLists
        lib.mkMerge
      ];
    }
    {
      networking.networkmanager.unmanaged = lib.attrsets.mapAttrsToList (_: entry: "interface-name:${entry.iface}") vlans;
      systemd.network.netdevs = lib.pipe vlans [
        (lib.attrsets.mapAttrsToList (name: vlan: {
          "50-${name}" = {
            netdevConfig.Kind = "vlan";
            netdevConfig.Name = vlan.iface;
            vlanConfig.Id = vlan.id;
          };
        }))
        lib.mkMerge
      ];
      systemd.network.networks = lib.pipe vlans [
        (lib.attrsets.mapAttrsToList (name: vlan: {
          "50-${vlan.parent.name}".networkConfig.VLAN = [vlan.iface];
          "50-${name}" = {
            matchConfig.Name = vlan.iface;
            linkConfig = {
              RequiredForOnline = "no";
            };
            networkConfig = {
              VLAN = vlan.iface;

              DHCP = true;
              UseDomains = true;

              IPv6AcceptRA = true;
              LinkLocalAddressing = "ipv6";
              IPv6PrivacyExtensions = true;
              IPv6LinkLocalAddressGenerationMode = "stable-privacy";
            };

            linkConfig.Multicast = true; # required for IPv6AcceptRA to take effect on bond interface
            dhcpV4Config.RouteMetric = 1000;
            dhcpV6Config.RouteMetric = 1000;
          };
        }))
        lib.mkMerge
      ];
    }
  ];
}
