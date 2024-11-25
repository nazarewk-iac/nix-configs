{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  cfg = config.kdn.desktop.base;
in {
  options.kdn.desktop.base = {
    enable = lib.mkEnableOption "Desktop base setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.displayManager.sddm.enable = true;
      # default maximum user is 30000, but I'm assigning higher than that
      services.displayManager.sddm.settings.Users.MaximumUid = config.ids.uids.nobody - 1;
      services.displayManager.sddm.wayland.enable = true;
      services.displayManager.sddm.theme = "chili";
      environment.systemPackages = with pkgs; [
        sddm-chili-theme
      ];
    }
    {
      fonts.fontDir.enable = true;
      fonts.packages = with pkgs; [
        cantarell-fonts
        font-awesome
        nerdfonts
        noto-fonts
        noto-fonts-emoji
        noto-fonts-emoji-blob-bin
        noto-fonts-extra
      ];

      gtk.iconCache.enable = true;
      home-manager.sharedModules = [
        ({config, ...}: {
          home.file."${config.gtk.gtk2.configLocation}".force = true;
          xdg.configFile."fontconfig/conf.d/10-hm-fonts.conf".force = true;
          xdg.configFile."gtk-3.0/gtk.css".force = true;
          xdg.configFile."gtk-3.0/settings.ini".force = true;
          xdg.configFile."gtk-4.0/gtk.css".force = true;
          xdg.configFile."gtk-4.0/settings.ini".force = true;
        })
      ];
    }
    {
      hardware.uinput.enable = true;
      kdn.programs.ydotool.enable = true;
      kdn.programs.dconf.enable = true;
      services.accounts-daemon.enable = true;
      services.dleyna-renderer.enable = true;
      services.dleyna-server.enable = true;
      services.gvfs.enable = true;
      services.power-profiles-daemon.enable = true;
      services.udisks2.enable = true;
      services.upower.enable = config.powerManagement.enable;
      services.xserver.enable = true;
      services.xserver.updateDbusEnvironment = true;
      xdg.icons.enable = true;
      xdg.mime.enable = true;
      programs.wshowkeys.enable = true;

      environment.systemPackages = with pkgs;
        [
          xorg.xeyes
          xorg.xhost
          xorg.xlsclients

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
          ashpd-demo # Tool for playing with XDG desktop portals

          # carry-overs from modules/desktop/sway/base/default.nix
          grim
          libnotify
          libsecret
          wayland-utils
          wl-clipboard
          wl-clipboard-x11

          # themes
          hicolor-icon-theme # nm-applet, see https://github.com/NixOS/nixpkgs/issues/32730
          gnome-icon-theme # nm-applet, see https://github.com/NixOS/nixpkgs/issues/43836#issuecomment-419217138
          glib # gsettings
          sound-theme-freedesktop
        ]
        ++ (with pkgs.libsForQt5; [
          okular # pdf viewer
          ark # archive manager
          gwenview # image viewer & editor
          /*
             TODO: didn't build on 2024-04-16
          pix # image gallery viewer
          */
        ]);

      xdg.portal.enable = true;
      xdg.portal.xdgOpenUsePortal = true;
    }
    {
      # Nemo file browser
      # based on https://github.com/NixOS/nixpkgs/blob/2dbd317f56128ddc550ca337c7c6977d4bbec887/nixos/modules/services/x11/desktop-managers/cinnamon.nix

      services.gnome.glib-networking.enable = true;
      programs.file-roller.enable = true;
      programs.file-roller.package = pkgs.nemo-fileroller;

      environment.systemPackages = with pkgs.cinnamon // pkgs; [
        nemo-with-extensions
        gtk3.out
        xdg-user-dirs
        desktop-file-utils
      ];
      services.dbus.packages = with pkgs.cinnamon // pkgs; [
        nemo-with-extensions
      ];
      fonts.packages = with pkgs; [
        dejavu_fonts # Default monospace font in LMDE 6+
        ubuntu_font_family # required for default theme
      ];
    }
  ]);
}
