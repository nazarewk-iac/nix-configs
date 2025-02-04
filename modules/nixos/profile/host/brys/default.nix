{
  config,
  pkgs,
  lib,
  modulesPath,
  self,
  ...
}: let
  cfg = config.kdn.profile.host.brys;
  hostname = config.networking.hostName;
in {
  options.kdn.profile.host.brys = {
    enable = lib.mkEnableOption "enable brys host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;
      kdn.hardware.cpu.amd.enable = true;

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
      kdn.hardware.edid.enable = true;
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
    (
      let
        cfg = config.kdn.hardware.disks;
        d1 = "vp4300-brys";
        d2 = "px700-brys";
      in {
        # TODO: those are unlocked automatically using TPM2, switch to etra (or k8s cluster) backed Clevis+Tang unlock
        kdn.hardware.disks.initrd.failureTarget = "rescue.target";
        kdn.hardware.disks.enable = true;
        kdn.hardware.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04LZCR91M8UZPJW8-0:0";
        kdn.hardware.disks.luks.volumes."${d1}" = {
          targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-5650343330304c45444242323333343032303433-5669706572205650343330304c20325442-00000001";
          uuid = "cbfe2928-2249-47fa-a48f-7c53c53a05d4";
          headerSpec.num = 2;
        };

        kdn.hardware.disks.luks.volumes."${d2}" = {
          targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-473342303335383134-53534450522d50583730302d3032542d3830-00000001";
          uuid = "53513d1d-233f-4c6b-b1ea-eeb40062e580";
          headerSpec.num = 3;
        };
      }
    )
    {
      kdn.hardware.nanokvm.enable = true;
    }
    {
      networking.networkmanager.ensureProfiles.profiles.pic = {
        connection.id = "pic";
        connection.type = "vlan";
        connection.interface-name = "pic";
        connection.autoconnect = true;
        vlan.id = 1859;
        vlan.flags = 1;
        vlan.parent = "enp6s0";
        ipv4.ignore-auto-dns = true;
        ipv4.method = "auto";
        ipv4.never-default = true;
        ipv6.addr-gen-mode = "stable-privacy";
        ipv6.ignore-auto-dns = true;
        ipv6.method = "auto";
        ipv6.never-default = true;
      };
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
  ]);
}
