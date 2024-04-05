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
      boot.tmp.tmpfsSize = "16G";
    }
    {
      kdn.hardware.edid.enable = true;
      hardware.display.outputs."DP-1".edid = "PG278Q_120.bin";
      hardware.display.outputs."DP-1".mode = "e";
      hardware.display.edid.applyAtRuntime = true;
    }
    {
      home-manager.sharedModules = [{
        wayland.windowManager.sway.config =
          let
            # name is derived from forced edid profile, could be DP-1
            #asus = "The Linux Foundation ${lib.removeSuffix ".bin" config.hardware.display.outputs."DP-1".edid} Linux #0";
            asus = "DP-1";
            dell = "Dell Inc. DELL U2711 G606T29F0EWL";
          in
          {
            output."${asus}".pos = "0 0";
            output."${dell}".pos = "2560 0";
            workspaceOutputAssign = [
              { workspace = "1"; output = dell; }
              { workspace = "2"; output = asus; }
              { workspace = "3"; output = asus; }
              { workspace = "4"; output = dell; }
            ];
          };
      }];
      kdn.filesystems.disko.luks-zfs.enable = true;
    }
    (import ./disko.nix { inherit lib; hostname = config.networking.hostName; })
    {
      # automated unlock using Clevis through Tang server
      boot.initrd.network.flushBeforeStage2 = true;
      networking.interfaces.enp5s0.useDHCP = true;
      networking.interfaces.enp6s0.useDHCP = true;

      boot.initrd.network.enable = true; # this is systemd-networkd all he way through anyway
      boot.initrd.systemd.network.wait-online.enable = true;
      boot.initrd.systemd.network.wait-online.anyInterface = true;
      boot.initrd.systemd.network.wait-online.timeout = 15;

      boot.initrd.clevis.enable = true;
      boot.initrd.clevis.useTang = true;

      environment.systemPackages = with pkgs; [
        clevis
        jose
      ];
      boot.initrd.clevis.devices."krul-main-crypted".secretFile = ./krul-main-crypted.jwe;
    }
  ]);
}
