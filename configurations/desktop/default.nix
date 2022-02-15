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
  networking.firewall.enable = true;
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "wasm32-wasi"
    "wasm64-wasi"
    "x86_64-windows"
  ];

  # HARDWARE
  services.cpupower-gui.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  hardware.opengl.driSupport32Bit = true;
  hardware.video.hidpi.enable = true;

  # SSH
  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  # LOCALE
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_GB.UTF-8"; # en_GB - Monday as first day of week
  };
  time.timeZone = "Europe/Warsaw";

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

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [
    hplip
    gutenprint
    gutenprintBin
    brlaser
    brgenml1lpr
    brgenml1cupswrapper
  ];
  services.avahi.enable = true;
  programs.seahorse.enable = true;

  programs.java.enable = true;
  environment.systemPackages = with pkgs; [
    dex # A program to generate and execute DesktopEntry files of the Application type
    firefox-wayland
    chromium
    google-chrome
    jetbrains.pycharm-professional
    jetbrains.idea-ultimate
    p7zip
    system-config-printer

    gparted

    # networking
    dnsmasq
    iw

    mc
    libqrencode
    imagemagick
    #((pkgs.gradleGen.override { java = jdk; }).gradle_latest)

    playerctl
    spotify
    zoom-us
    slack
    signal-desktop
    element-desktop
    nextcloud-client
    cadaver
    libreoffice
    flameshot
    vlc
    evince
    xfce.ristretto
    xfce.exo
    xfce.xfconf
    shotwell
    gimp
    pdftk

    (pkgs.writeScriptBin "qrpaste" ''
      #! ${pkgs.bash}/bin/bash
      ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.libqrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
    '')

    # experiments
    cachix
  ];

  # ANDROID
  programs.adb.enable = true;

  # KEYBASE
  services.kbfs.enable = true;
  services.davfs2.enable = true;

  # virtualization
  virtualisation.libvirtd.enable = true;

  # CUSTOM

  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.teamviewer.enable = true;
  programs.steam.enable = true;

  nazarewk.headless.base.enable = true;
  nazarewk.development.cloud.enable = true;
  nazarewk.development.k8s.enable = true;
  nazarewk.development.python.enable = true;
  nazarewk.development.ruby.enable = true;
  nazarewk.hardware.pipewire.enable = true;
  nazarewk.hardware.pipewire.useWireplumber = true;
  nazarewk.hardware.yubikey.enable = true;
  nazarewk.programs.aws-vault.enable = true;
  nazarewk.programs.nix-direnv.enable = true;
  nazarewk.programs.nix-index.enable = true;
  nazarewk.sway.gdm.enable = true;
  nazarewk.sway.systemd.enable = false;
}