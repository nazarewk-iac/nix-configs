{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.desktop;
in
{
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.desktop.base.enable = true;
    kdn.profile.machine.basic.enable = true;

    hardware.opengl.enable = true;
    hardware.opengl.driSupport = true;
    hardware.opengl.driSupport32Bit = true;

    # INPUT
    services.xserver.layout = "pl";
    console.useXkbConfig = true;
    services.xserver.libinput.enable = true;
    services.xserver.libinput.touchpad.disableWhileTyping = true;
    services.xserver.libinput.touchpad.naturalScrolling = true;
    services.xserver.libinput.touchpad.tapping = true;
    services.xserver.synaptics.twoFingerScroll = true;

    kdn.hardware.pipewire.enable = true;
    kdn.hardware.pipewire.useWireplumber = true;
    kdn.hardware.yubikey.enable = true;

    kdn.headless.enableGUI = true;

    boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];

    # Enable CUPS to print documents.
    services.printing.enable = true;
    services.printing.drivers = with pkgs; [
      hplip
      #gutenprint
      #gutenprintBin
      brlaser
      brgenml1lpr
      brgenml1cupswrapper
    ];
    environment.systemPackages = with pkgs; [
      libreoffice-qt # non-qt failed to build on 2023-04-07
      # chromium
      thunderbird
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
  };
}
