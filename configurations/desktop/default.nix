{ config, pkgs, lib, ... }:
{
  imports = [
    ../../users/nazarewk
    ../basic
  ];

  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "wasm32-wasi"
    "wasm64-wasi"
    "x86_64-windows"
  ];

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
  ];

  # ANDROID
  programs.adb.enable = true;

  # KEYBASE
  services.kbfs.enable = true;

  # CUSTOM

  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.teamviewer.enable = true;
  programs.steam.enable = true;

  nazarewk.development.cloud.enable = true;
  nazarewk.development.k8s.enable = true;
  nazarewk.development.python.enable = true;
  nazarewk.development.ruby.enable = true;
  nazarewk.development.terraform.enable = true;
  nazarewk.programs.aws-vault.enable = true;
  nazarewk.programs.nix-direnv.enable = true;
  nazarewk.programs.nix-index.enable = true;
  nazarewk.sway.gdm.enable = true;
}