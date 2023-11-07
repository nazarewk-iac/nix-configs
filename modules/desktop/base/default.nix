{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.kdn.desktop.base;
in
{
  options.kdn.desktop.base = {
    enable = lib.mkEnableOption "Desktop base setup";
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = with pkgs; [
      cantarell-fonts
      font-awesome
      nerdfonts
      noto-fonts
      noto-fonts-emoji
      noto-fonts-emoji-blob-bin
      noto-fonts-extra
      anonymousPro
    ];

    hardware.uinput.enable = true;
    kdn.programs.ydotool.enable = true;
    programs.dconf.enable = true;
    security.polkit.enable = true;
    services.accounts-daemon.enable = true;
    services.dleyna-renderer.enable = true;
    services.dleyna-server.enable = true;
    services.gvfs.enable = true;
    services.power-profiles-daemon.enable = true;
    services.udisks2.enable = true;
    services.upower.enable = config.powerManagement.enable;
    services.xserver.displayManager.sddm.enable = true;
    # default maximum user is 30000, but I'm assigning higher than that
    services.xserver.displayManager.sddm.settings.Users.MaximumUid = config.ids.uids.nobody - 1;
    services.xserver.displayManager.sddm.wayland.enable = true;
    services.xserver.enable = true;
    services.xserver.updateDbusEnvironment = true;
    xdg.icons.enable = true;
    xdg.mime.enable = true;

    environment.systemPackages = with pkgs; [
      xorg.xeyes
      xorg.xhost
      xorg.xlsclients

      # audio
      libopenaptx
      libfreeaptx
      pulseaudio

      # graphics
      libva-utils

      # tools
      brightnessctl
      gsettings-desktop-schemas
      gtk-engine-murrine
      gtk_engines
      lxappearance
      xsettingsd
      dex # A program to generate and execute DesktopEntry files of the Application type

      # debugging
      evtest # listens for /dev/event* device events (eg: keyboard keys, function keys etc)
      libinput
      v4l-utils
      wev # wayland event viewer
      wshowkeys # display pressed keys
      ashpd-demo # Tool for playing with XDG desktop portals


      # carry-overs from modules/desktop/sway/base/default.nix
      libnotify
      wofi
      wl-clipboard
      wl-clipboard-x11
      wayland-utils
      grim
      libnotify

      # themes
      hicolor-icon-theme # nm-applet, see https://github.com/NixOS/nixpkgs/issues/32730
      gnome-icon-theme # nm-applet, see https://github.com/NixOS/nixpkgs/issues/43836#issuecomment-419217138
      glib # gsettings
      sound-theme-freedesktop
    ] ++ (with pkgs.libsForQt5; [
      dolphin # file manager
      okular # pdf viewer
      ark # archive manager
      gwenview # image viewer & editor
      pix # image gallery viewer
    ]);

    gtk.iconCache.enable = true;

    xdg.portal.enable = true;
    xdg.portal.xdgOpenUsePortal = true;

    qt.enable = true;
    qt.platformTheme = "kde";
    qt.style = "cleanlooks";
  };
}
