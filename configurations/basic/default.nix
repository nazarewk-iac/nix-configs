{ config, pkgs, lib, ... }:
{
  imports = [
    ../../users/nazarewk
  ];

  networking.nameservers = [
    "2606:4700:4700::1111" # CloudFlare
    "1.1.1.1" # CloudFlare
    "8.8.8.8" # Google
  ];
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  # REMOTE access
  services.openssh.enable = true;
  services.openssh.openFirewall = true;
  services.openssh.passwordAuthentication = false;


  # HARDWARE
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  hardware.opengl.driSupport32Bit = true;
  hardware.video.hidpi.enable = true;


  # LOCALE
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_GB.UTF-8"; # en_GB - Monday as first day of week
  };
  time.timeZone = "Europe/Warsaw";
  location.provider = "geoclue2";

  # INPUT
  services.xserver.layout = "pl";
  console.useXkbConfig = true;
  services.xserver.libinput.enable = true;
  services.xserver.libinput.touchpad.disableWhileTyping = true;
  services.xserver.libinput.touchpad.naturalScrolling = true;
  services.xserver.libinput.touchpad.tapping = true;
  services.xserver.synaptics.twoFingerScroll = true;

  # USERS
  users.users.root.initialHashedPassword = "";

  services.avahi.enable = true;

  environment.systemPackages = with pkgs; [
    cachix
  ];

  environment.shellAliases = {
    "userctl" = "systemctl --user";
    "userjournal" = "journalctl --user";
  };

  # KEYBASE
  services.davfs2.enable = true;

  nazarewk.headless.base.enable = true;
  nazarewk.hardware.pipewire.enable = true;
  nazarewk.hardware.pipewire.useWireplumber = true;
  nazarewk.hardware.yubikey.enable = true;
  nazarewk.sway.gdm.enable = true;

  services.locate.enable = true;
  services.locate.localuser = null;
  services.locate.locate = pkgs.mlocate;
  services.locate.pruneBindMounts = true;
}