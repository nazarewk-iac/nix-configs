{ config, pkgs, lib, ... }:
{
  imports = [
    ../headless
  ];

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
  services.xserver.libinput.enable = true;
  services.xserver.libinput.touchpad.disableWhileTyping = true;
  services.xserver.libinput.touchpad.naturalScrolling = true;
  services.xserver.libinput.touchpad.tapping = true;
  services.xserver.synaptics.twoFingerScroll = true;

  # KEYBASE
  services.davfs2.enable = true;

  nazarewk.hardware.pipewire.enable = true;
  nazarewk.hardware.pipewire.useWireplumber = true;
  nazarewk.hardware.yubikey.enable = true;
  nazarewk.sway.gdm.enable = true;
  nazarewk.sway.systemd.enable = true;

  nazarewk.headless.enableGUI = true;

  home-manager.sharedModules = [
    ({ config, ... }: {
      xdg.userDirs.enable = true;
    })
  ];
}
