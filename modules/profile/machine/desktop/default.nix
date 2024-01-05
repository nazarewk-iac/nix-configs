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
      kdn.profile.machine.basic.enable = true;
      kdn.hardware.qmk.enable = true;

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
    }
    (lib.mkIf config.boot.initrd.systemd.enable {
      specialisation.boot-debug = {
        inheritParentConfig = true;
        configuration = lib.mkMerge [
          {
            system.nixos.tags = [ "boot-debug" ];
            boot.kernelParams = [
              # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
              #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
              "systemd.debug-shell=1"
              "systemd.log_level=debug"
              "systemd.unit=multi-user.target"
            ];
          }
        ];
      };
    })
  ]);
}
