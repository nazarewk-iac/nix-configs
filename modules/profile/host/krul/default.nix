{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.krul;
  hostname = config.networking.hostName;
in
{
  options.kdn.profile.host.krul = {
    enable = lib.mkEnableOption "enable krul host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home-manager.users.kdn.programs.firefox.profiles.kdn.path = "owvm95ih.kdn";
      home-manager.users.kdn.home.file.".mozilla/firefox/profiles.ini".force = true;

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

      networking.interfaces.enp5s0.wakeOnLan.enable = true;
      networking.interfaces.enp6s0.wakeOnLan.enable = true;

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "32G";
    }
    /*(
      let
        asusConn = "DP-4";
        # name is derived from forced edid profile, could be DP-1
        #asus = "The Linux Foundation ${lib.removeSuffix ".bin" config.hardware.display.outputs."DP-1".edid} Linux #0";
        asus = asusConn;
        dell = "Dell Inc. DELL U2711 G606T29F0EWL";
        m32uc = "GIGA-BYTE TECHNOLOGY CO., LTD. M32UC 22090B013112";
      in
      {
        kdn.hardware.edid.enable = true;
        hardware.display.outputs."${asusConn}" = {
          edid = "PG278Q_120.bin";
          mode = "e";
        };
        home-manager.sharedModules = [{
          wayland.windowManager.sway.config = {
            workspaceOutputAssign = [
              { workspace = "1"; output = m32uc; }
              { workspace = "2"; output = asus; }
              { workspace = "3"; output = asus; }
              { workspace = "4"; output = m32uc; }
            ];
          };
        }];
      }
    )*/
    {
      # automated unlock using Clevis through Tang server
      boot.initrd.network.flushBeforeStage2 = true;
      networking.interfaces.enp5s0.useDHCP = true;
      networking.interfaces.enp6s0.useDHCP = true;

      boot.initrd.network.enable = true; # this is systemd-networkd all he way through anyway
      boot.initrd.systemd.network.wait-online.enable = true;
      boot.initrd.systemd.network.wait-online.anyInterface = true;
      boot.initrd.systemd.network.wait-online.timeout = 15;

      boot.initrd.clevis.useTang = true;
      #boot.initrd.clevis.devices."krul-main-crypted".secretFile = ./krul-main-crypted.jwe;
    }
    (
      let
        cfg = config.kdn.hardware.disks;
        d1 = "vp4300-krul";
        d2 = "px700-krul";
      in
      {
        kdn.hardware.disks.initrd.failureTarget = "emergency.target";
        kdn.hardware.disks.enable = true;
        kdn.hardware.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04MBA03UR5RXVOGO-0:0";
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
  ]);
}
