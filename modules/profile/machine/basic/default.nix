{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.basic;
in
{
  options.kdn.profile.machine.basic = {
    enable = lib.mkEnableOption "enable basic machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.baseline.enable = true;

    networking.networkmanager.wifi.powersave = true;

    # HARDWARE
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;
    hardware.opengl.enable = true;
    hardware.opengl.driSupport = true;
    hardware.opengl.driSupport32Bit = true;
    hardware.video.hidpi.enable = true;

    # INPUT
    services.xserver.layout = "pl";
    console.useXkbConfig = true;
    services.xserver.libinput.touchpad.disableWhileTyping = true;
    services.xserver.libinput.touchpad.naturalScrolling = true;
    services.xserver.libinput.touchpad.tapping = true;
    services.xserver.synaptics.twoFingerScroll = true;

    kdn.hardware.pipewire.enable = true;
    kdn.hardware.pipewire.useWireplumber = true;
    kdn.hardware.yubikey.enable = true;

    environment.systemPackages = with pkgs; [
      # chromium
      firefox
      p7zip
      rar
      system-config-printer

      gparted
      gsmartcontrol
      smartmontools

      imagemagick

      playerctl
      pdftk

      (pkgs.writeScriptBin "qrpaste" ''
        #! ${pkgs.bash}/bin/bash
        ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.qrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
      '')
    ];
    home-manager.sharedModules = [
      ({ config, ... }: {
        xdg.userDirs.enable = true;
      })
    ];
  };
}
