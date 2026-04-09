{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.desktop.base;
in
{
  options.kdn.desktop.base = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      apply = value: value && config.kdn.desktop.enable;
    };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            #services.caffeine.enable = lib.mkDefault true;
            xdg.configFile."wofi/config".source = ./wofi/config;

            home.packages = with pkgs; [
              (pkgs.writeShellApplication {
                name = "ydotool-paste";
                runtimeInputs = with pkgs; [
                  ydotool
                  wl-clipboard
                ];
                text = ''
                  sleep "''${1:-0.5}"
                  wl-paste --no-newline | ydotool type --file=-
                '';
              })

              qalculate-qt
              libqalculate
            ];

            programs.foot.enable = true;
            programs.foot.server.enable = false;
            programs.foot.settings.main.dpi-aware = "no";
            programs.foot.settings.scrollback.lines = 100000;
          }
          {
            programs.wezterm.enable = true;
            programs.wezterm.extraConfig = lib.mkMerge [
              (lib.mkOrder 1 ''
                local wezterm = require 'wezterm'
                local config = wezterm.config_builder()
              '')
              ''config.front_end = "OpenGL"''
              (lib.mkOrder 9999 "return config")
            ];
            nixpkgs.overlays = [
              (final: prev: {
                wezterm =
                  let
                    upstream = kdnConfig.inputs.wezterm.packages."${final.stdenv.hostPlatform.system}".default;
                    base = prev.wezterm;
                    #base = upstream;
                  in
                  base.overrideAttrs {
                    patches = (prev.patches or [ ]) ++ [
                    ];
                  };
              })
            ];
          }
        ]
      )
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          { home-manager.sharedModules = [ { kdn.desktop.base.enable = cfg.enable; } ]; }
          {
            services.displayManager.sddm.enable = true;
            services.displayManager.sddm.settings.Users.MaximumUid = config.ids.uids.nobody - 1;
            services.displayManager.sddm.wayland.enable = true;
            services.displayManager.sddm.theme = "chili";
            environment.systemPackages = with pkgs; [
              sddm-chili-theme
            ];
          }
          {
            fonts.fontDir.enable = true;
            fonts.packages =
              with pkgs;
              [
                cantarell-fonts
                font-awesome
                noto-fonts
                noto-fonts-color-emoji
                noto-fonts-monochrome-emoji
                noto-fonts-emoji-blob-bin
              ]
              ++ lib.pipe pkgs.nerd-fonts [
                builtins.attrValues
                (builtins.filter (e: e ? caskName))
              ];

            gtk.iconCache.enable = true;
            home-manager.sharedModules = [
              (
                { config, ... }:
                {
                  gtk.gtk4.theme = config.gtk.theme;
                  gtk.gtk2.force = true;
                  xdg.configFile."fontconfig/conf.d/10-hm-fonts.conf".force = true;
                  xdg.configFile."gtk-3.0/gtk.css".force = true;
                  xdg.configFile."gtk-3.0/settings.ini".force = true;
                  xdg.configFile."gtk-4.0/gtk.css".force = true;
                  xdg.configFile."gtk-4.0/settings.ini".force = true;
                }
              )
            ];
          }
          {
            hardware.uinput.enable = true;
            kdn.programs.dconf.enable = true;
            kdn.programs.ydotool.enable = true;
            programs.wshowkeys.enable = true;
            services.accounts-daemon.enable = true;
            services.dleyna.enable = true;
            services.gvfs.enable = true;
            services.power-profiles-daemon.enable = true;
            services.udisks2.enable = true;
            services.upower.enable = config.powerManagement.enable;
            services.xserver.enable = true;
            services.xserver.updateDbusEnvironment = true;
            xdg.icons.enable = true;
            xdg.mime.enable = true;

            environment.systemPackages =
              with pkgs;
              [
                xeyes
                xhost
                xlsclients
                libva-utils
                brightnessctl
                gsettings-desktop-schemas
                gtk-engine-murrine
                gtk_engines
                lxappearance
                xsettingsd
                dex
                evtest
                libinput
                v4l-utils
                wev
                ashpd-demo
                grim
                libnotify
                libsecret
                wayland-utils
                wl-clipboard
                wl-clipboard-x11
                hicolor-icon-theme
                gnome-icon-theme
                glib
                bustle
                sound-theme-freedesktop
              ]
              ++ (with pkgs.kdePackages; [
                okular
                ark
                gwenview
                pix
              ]);

            xdg.portal.enable = true;
            xdg.portal.xdgOpenUsePortal = true;
          }
          {
            services.gnome.glib-networking.enable = true;

            environment.systemPackages = with pkgs; [
              nemo-with-extensions
              nemo-fileroller
              gtk3.out
              xdg-user-dirs
              desktop-file-utils
            ];
            services.dbus.packages = with pkgs; [
              nemo-with-extensions
            ];
            fonts.packages = with pkgs; [
              dejavu_fonts
              ubuntu-classic
            ];
          }
        ]
      )
    ))
  ];
}
