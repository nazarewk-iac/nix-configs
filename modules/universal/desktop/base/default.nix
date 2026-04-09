{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.desktop.base = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              apply = value: value && config.kdn.desktop.enable;
            };
          };

  imports = [
    (kdnConfig.util.ifHM (
    lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (
        let
          cfg = config.kdn.desktop.base;
          ydotool-paste = pkgs.writeShellApplication {
            name = "ydotool-paste";
            runtimeInputs = with pkgs; [
              ydotool
              wl-clipboard
            ];
            text = ''
              sleep "''${1:-0.5}"
              wl-paste --no-newline | ydotool type --file=-
            '';
          };
        in {

config = lib.mkIf cfg.enable (
            lib.mkMerge [
              {
                #services.caffeine.enable = lib.mkDefault true;

                xdg.configFile."wofi/config".source = ./wofi/config;

                home.packages = with pkgs; [
                  ydotool-paste

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
                  (lib.mkOrder 9999 ''return config'')
                ];
                nixpkgs.overlays = [
                  (final: prev: {
                    wezterm = let
                      upstream = kdnConfig.inputs.wezterm.packages."${final.stdenv.hostPlatform.system}".default;
                      base = prev.wezterm;
                      #base = upstream;
                    in
                      base.overrideAttrs {
                        patches =
                          (prev.patches or [])
                          ++ [
                          ];
                      };
                  })
                ];
              }
            ]
          );
        }
      )
      ))
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.desktop.base;
        in {

          config = lib.mkIf cfg.enable (
              lib.mkMerge [
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.desktop.base = lib.mkDefault cfg;}];})
{home-manager.sharedModules = [{kdn.desktop.base.enable = cfg.enable;}];}
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
                fonts.packages = with pkgs;
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
                    # see https://github.com/NixOS/nixpkgs/blob/bee4c52a36af4d88c883bb68e494aa26cbe52d58/pkgs/data/fonts/nerd-fonts/default.nix#L89-L89
                    (builtins.filter (e: e ? caskName))
                  ];

                gtk.iconCache.enable = true;
                home-manager.sharedModules = [
                  (
                    {config, ...}: {
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

                environment.systemPackages = with pkgs;
                  [
                    xeyes
                    xhost
                    xlsclients

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
                    bustle # dbus analyser
                    sound-theme-freedesktop
                  ]
                  ++ (with pkgs.kdePackages; [
                    okular # pdf viewer
                    ark # archive manager
                    gwenview # image viewer & editor
                    pix # image gallery viewer
                  ]);

                xdg.portal.enable = true;
                xdg.portal.xdgOpenUsePortal = true;
              }
              {
                # Nemo file browser
                # based on https://github.com/NixOS/nixpkgs/blob/2dbd317f56128ddc550ca337c7c6977d4bbec887/nixos/modules/services/x11/desktop-managers/cinnamon.nix

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
                  dejavu_fonts # Default monospace font in LMDE 6+
                  ubuntu-classic # renamed from `ubuntu_font_family`, which was required for the default theme
                ];
              }
            ]
          );
        }
      )
    )
  ];
}
