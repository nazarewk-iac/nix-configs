{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.desktop;
in
{
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.basic.enable = true;

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
    services.plantuml-server.enable = true;

    kdn.docker.enable = true;

    environment.systemPackages = with pkgs; [
      dex # A program to generate and execute DesktopEntry files of the Application type
      brave
      # chromium
      firefox-wayland
      jetbrains.pycharm-professional
      jetbrains.idea-ultimate
      jetbrains.clion
      jetbrains.goland
      jetbrains.ruby-mine
      p7zip
      rar
      system-config-printer

      drawio
      plantuml

      gparted
      qjournalctl
      gsmartcontrol
      smartmontools

      # networking
      dnsmasq
      iw

      mc
      qrencode
      cobang # QR code scanner
      imagemagick
      #((pkgs.gradleGen.override { java = jdk; }).gradle_latest)

      playerctl
      spotify
      # spotify-qt
      # spotify-tray  # spotify tray requires X11

      element-desktop
      signal-desktop
      slack
      teams
      zoom-us

      nextcloud-client
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

      transmission-qt
      megatools

      (pkgs.writeScriptBin "qrpaste" ''
        #! ${pkgs.bash}/bin/bash
        ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.qrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
      '')
    ];

    # ANDROID
    programs.adb.enable = true;

    # KEYBASE
    services.kbfs.enable = true;

    # CUSTOM

    services.devmon.enable = true;
    programs.steam.enable = true;

    kdn.desktop.remote-server.enable = true;
    kdn.development.cloud.enable = true;
    kdn.development.data.enable = true;
    kdn.development.elixir.enable = true;
    kdn.development.golang.enable = true;
    kdn.development.k8s.enable = true;
    kdn.development.nix.enable = true;
    kdn.development.python.enable = true;
    kdn.development.ruby.enable = true;
    kdn.development.rust.enable = true;
    kdn.development.terraform.enable = true;
    kdn.hardware.discovery.enable = true;
    kdn.hardware.edid.enable = true;
    kdn.programs.aws-vault.enable = true;
    kdn.programs.keepass.enable = true;
    kdn.programs.nix-direnv.enable = true;
    kdn.programs.nix-index.enable = true;
  };
}
