{
  config,
  pkgs,
  lib,
  kdn,
  ...
}: let
  cfg = config.kdn.profile.host.brys;
  hostname = config.kdn.hostName;
in {
  options.kdn.profile.host.brys = {
    enable = lib.mkEnableOption "enable brys host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
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
      kdn.hw.disks.initrd.failureTarget = "rescue.target";
      kdn.hw.disks.enable = true;
      kdn.hw.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04LZCR91M8UZPJW8-0:0";
      kdn.hw.disks.luks.volumes."vp4300-brys" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-5650343330304c45444242323333343032303433-5669706572205650343330304c20325442-00000001";
        uuid = "cbfe2928-2249-47fa-a48f-7c53c53a05d4";
        headerSpec.num = 2;
      };

      kdn.hw.disks.luks.volumes."px700-brys" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-473342303335383134-53534450522d50583730302d3032542d3830-00000001";
        uuid = "53513d1d-233f-4c6b-b1ea-eeb40062e580";
        headerSpec.num = 3;
      };
    }
    {
      kdn.hw.nanokvm.enable = true;
    }
    {
      kdn.desktop.sway.portals.debug = true;
      environment.systemPackages = [pkgs.kdn.hubstaff];
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
    (let
      uplinkName = "uplink-2g";
      uplink.iface = "br-${uplinkName}";
      vlan.pic.name = "pic";
      vlan.pic.iface = vlan.pic.name;
      vlan.pic.id = 1859;
    in {
      /*
      Sets up:
      - bridge for VMs and local 2.5GbE network cards
      - `pic` VLAN through the bridge
      */
      systemd.network.enable = true;
      networking.useNetworkd = true;
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
          VLAN = [vlan.pic.iface];

          DHCP = true;
          # `UseDomains = true` for adding search domain `route` for just DNS queries
          UseDomains = true;

          IPv6AcceptRA = true;
          LinkLocalAddressing = "ipv6";

          IPv6PrivacyExtensions = true;
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
      };
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
      };
    })

    (let
      iface = "vm-nbt-1";
      microvmPersistNames = ["microvm"] ++ builtins.attrNames config.kdn.hw.disks.base;
    in {
      systemd.network.networks."40-ethernet-2.5g" = {
        matchConfig.Name = [iface];
      };

      microvm.vms.nbt-1 = {
        autostart = true;
        restartIfChanged = true;
        specialArgs = kdn.configure {} {
          kdn.features.nixos = true;
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

              kdn.networking.netbird.priv.enable = false;
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
    {
      kdn.services.zammad.enable = true;
    }
  ]);
}
