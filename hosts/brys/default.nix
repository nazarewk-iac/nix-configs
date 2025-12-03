{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "brys";

      system.stateVersion = "24.11";
      home-manager.sharedModules = [{home.stateVersion = "24.11";}];
      networking.hostId = "0a989258"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.machine.workstation.enable = true;
      kdn.hw.gpu.amd.enable = true;
      kdn.hw.cpu.amd.enable = true;

      kdn.programs.photoprism.enable = false;

      kdn.profile.machine.gaming.enable = true;

      boot.initrd.availableKernelModules = [
        "mt7921e" # MEDIATEK Corp. MT7921K (RZ608) Wi-Fi 6E 80MHz
        "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
        "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
      ];

      # enp5s0 is 1GbE
      #networking.interfaces.enp5s0.wakeOnLan.enable = true;
      # enp6s0 is 2.5GbE
      #networking.interfaces.enp6s0.wakeOnLan.enable = true;

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "32G";
    }
    {
      kdn.hw.edid.enable = true;
      hardware.display.outputs."DP-4" = {
        edid = "PG278Q_120.bin";
        mode = "e";
      };
    }
    /*
       {
      # automated unlock using Clevis through Tang server
      boot.initrd.network.flushBeforeStage2 = true;
      networking.interfaces.enp5s0.useDHCP = true;
      networking.interfaces.enp6s0.useDHCP = true;

      boot.initrd.network.enable = true; # this is systemd-networkd all he way through anyway
      boot.initrd.systemd.network.wait-online.enable = true;
      boot.initrd.systemd.network.wait-online.anyInterface = true;
      boot.initrd.systemd.network.wait-online.timeout = 15;

      #boot.initrd.clevis.useTang = true;
      #boot.initrd.clevis.devices."brys-main-crypted".secretFile = ./brys-main-crypted.jwe;
    }
    */
    {
      # TODO: those are unlocked automatically using TPM2, switch to etra (or k8s cluster) backed Clevis+Tang unlock
      kdn.disks.initrd.failureTarget = "rescue.target";
      kdn.disks.enable = true;
      kdn.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04LZCR91M8UZPJW8-0:0";
      kdn.disks.luks.volumes."vp4300-brys" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-5650343330304c45444242323333343032303433-5669706572205650343330304c20325442-00000001";
        uuid = "cbfe2928-2249-47fa-a48f-7c53c53a05d4";
        headerSpec.partNum = 2;
      };

      kdn.disks.luks.volumes."px700-brys" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-473342303335383134-53534450522d50583730302d3032542d3830-00000001";
        uuid = "53513d1d-233f-4c6b-b1ea-eeb40062e580";
        headerSpec.partNum = 3;
      };
    }
    {
      kdn.hw.nanokvm.enable = true;
    }
    {
      kdn.desktop.sway.portals.debug = true;
    }
    {
      # VNC access over Netbird
      networking.firewall.interfaces."nb-priv".allowedTCPPorts = [
        5900
      ];
      networking.firewall.interfaces."nb-priv".allowedUDPPorts = [
        5900
      ];
    }
    (
      let
        uplinkName = "uplink-2g";
        uplink.iface = "br-${uplinkName}";
        vlan.pic.name = "pic";
        vlan.pic.iface = vlan.pic.name;
        vlan.pic.id = 1859;
        vlan.drek.name = "drek";
        vlan.drek.iface = vlan.drek.name;
        vlan.drek.id = 3547;
      in {
        /*
        Sets up:
        - bridge for VMs and local 2.5GbE network cards
        - `pic` VLAN through the bridge
        */
        networking.networkmanager.unmanaged = [
          "interface-name:enp6s0"
          "interface-name:${vlan.pic.iface}"
          "interface-name:${uplink.iface}"
        ];
        systemd.network.netdevs."50-${uplink.iface}".netdevConfig = {
          Kind = "bridge";
          Name = uplink.iface;
        };
        systemd.network.networks."40-ethernet-2.5g" = {
          matchConfig.Name = ["enp6s0"];
          networkConfig.Bridge = uplink.iface;
          linkConfig.RequiredForOnline = "enslaved";
        };
        systemd.network.networks."50-${uplinkName}" = {
          matchConfig.Name = uplink.iface;
          bridgeConfig = {};
          linkConfig.RequiredForOnline = "carrier";
          networkConfig = {
            VLAN = [
              vlan.pic.iface
              vlan.drek.iface
            ];

            DHCP = true;
            # `UseDomains = true` for adding search domain `route` for just DNS queries
            UseDomains = true;

            IPv6AcceptRA = true;
            LinkLocalAddressing = "ipv6";

            IPv6PrivacyExtensions = true;
            IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          };
          dhcpV4Config.RouteMetric = 100;
          dhcpV6Config.RouteMetric = 100;
        };

        /*
        systemd.network.netdevs."50-${vlan.pic.name}" = {
          netdevConfig.Kind = "vlan";
          netdevConfig.Name = vlan.pic.iface;
          vlanConfig.Id = vlan.pic.id;
        };
        systemd.network.networks."50-${vlan.pic.name}" = {
          matchConfig.Name = vlan.pic.iface;
          networkConfig = {
            DHCP = true;
            IPv6AcceptRA = true;
            LinkLocalAddressing = "ipv6";

            IPv6PrivacyExtensions = true;
            IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          };
          dhcpV4Config.RouteMetric = 1000;
          dhcpV6Config.RouteMetric = 1000;
        };

        systemd.network.netdevs."50-${vlan.drek.name}" = {
          netdevConfig.Kind = "vlan";
          netdevConfig.Name = vlan.drek.iface;
          vlanConfig.Id = vlan.drek.id;
        };
        systemd.network.networks."50-${vlan.drek.name}" = {
          matchConfig.Name = vlan.drek.iface;
          networkConfig = {
            DHCP = true;
            IPv6AcceptRA = true;
            LinkLocalAddressing = "ipv6";

            IPv6PrivacyExtensions = true;
            IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          };
          dhcpV4Config.RouteMetric = 1100;
          dhcpV6Config.RouteMetric = 1100;
        };
        */
      }
    )
    /*
    (let
      iface = "vm-nbt-1";
      microvmPersistNames = ["microvm"] ++ builtins.attrNames config.kdn.disks.base;
    in {
      systemd.network.networks."40-ethernet-2.5g" = {
        matchConfig.Name = [iface];
      };

      microvm.vms.nbt-1 = {
        autostart = true;
        restartIfChanged = true;
        specialArgs =
          kdn.configure {
            moduleType = "nixos";
          } {
            kdn.features.microvm-guest = true;
          };
        config = {
          imports = [
            kdn.self.nixosModules.default
          ];
          config = lib.mkMerge [
            {
              kdn.hostName = "brys-uvm-nbt-1";
              system.stateVersion = "25.05";
              home-manager.sharedModules = [{home.stateVersion = "25.05";}];
              networking.hostId = "fb6ff1fa"; # cut -c-8 </proc/sys/kernel/random/uuid
              kdn.security.secrets.enable = false;

              kdn.networking.netbird.clients.priv.enable = false;
            }
            {
              microvm.interfaces = [
                {
                  type = "tap";
                  id = iface;
                  mac = "42:e2:ce:6a:ce:c1";
                }
              ];
              systemd.network.enable = true;

              systemd.network.networks."20-lan" = {
                matchConfig.Type = "ether";
                networkConfig = {
                  DHCP = true;
                  IPv6AcceptRA = true;
                  LinkLocalAddressing = "ipv6";

                  IPv6PrivacyExtensions = true;
                  IPv6LinkLocalAddressGenerationMode = "stable-privacy";
                };
              };
            }
          ];
        };
      };
    })
    */
    {
      kdn.services.zammad.enable = false;
    }
    {
      services.bpftune.enable = true;
    }
    {
      kdn.disks.nixBuildDir.type = "tmpfs";
      kdn.disks.nixBuildDir.tmpfs.size = "64G";
    }
    {
      networking.hosts."10.116.89.68" = ["gipe"];
      networking.networkmanager.ensureProfiles.profiles.gipe = {
        connection = {
          id = "gipe";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = false;
        };
        ethernet.mac-address = "04:42:1A:ED:8B:04";
        ipv4 = {
          method = "manual";
          address1 = "10.116.89.69/31";
          may-fail = false;
        };
        ipv6.method = "disabled";
      };
    }
    {

      networking.hosts."192.168.2.1" = ["mokerlink"];
      networking.networkmanager.ensureProfiles.profiles.mokerlink-switch = {
        connection = {
          id = "mokerlink-switch";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = false;
        };
        ethernet.mac-address = "04:42:1A:ED:8B:04";
        ipv4 = {
          method = "manual";
          address1 = "192.168.2.2/24";
          may-fail = false;
        };
        ipv6.method = "disabled";
      };
    }
    {
      # kdn.nix.remote-builder.localhost.publicHostKey = "??";
      kdn.nix.remote-builder.localhost.maxJobs = 12;
      kdn.nix.remote-builder.localhost.speedFactor = 32;
    }
  ];
}
