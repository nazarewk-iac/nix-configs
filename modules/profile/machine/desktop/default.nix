{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.desktop;
in
{
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.desktop.base.enable = true;
      kdn.hardware.gpu.enable = true;
      kdn.hardware.qmk.enable = true;
      kdn.profile.machine.basic.enable = true;

      # INPUT
      services.xserver.xkb.layout = "pl";
      console.useXkbConfig = true;
      services.libinput.enable = true;
      services.libinput.touchpad.disableWhileTyping = true;
      services.libinput.touchpad.naturalScrolling = true;
      services.libinput.touchpad.tapping = true;
      services.xserver.synaptics.twoFingerScroll = true;

      kdn.hardware.pipewire.enable = true;
      kdn.hardware.pipewire.useWireplumber = true;
      kdn.hardware.yubikey.enable = true;

      kdn.headless.enableGUI = true;

      boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];

      kdn.services.printing.enable = true;
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
    }
    {
      home-manager.sharedModules = [{
        # do not drop into ZelliJ automatically OOTB on desktop computers as it's pretty annoying
        programs.zellij.enableFishIntegration = false;
        programs.zellij.enableZshIntegration = false;
        programs.zellij.enableBashIntegration = false;
      }];
    }
  ]);
}
