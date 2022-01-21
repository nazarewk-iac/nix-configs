{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.base;
in {
  options.nazarewk.sway.base = {
    enable = mkEnableOption "Sway base setup";
  };

  config = mkIf cfg.enable {
    nazarewk.gnome.base.enable = true;
    nazarewk.xfce.base.enable = true;

    # Configure various Sway configs
    # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
    # see https://nixos.wiki/wiki/Sway#Systemd_integration
    programs.sway.enable = true;
    programs.sway.wrapperFeatures.gtk = true;
    programs.sway.extraOptions = [ "--debug" ];
    environment.pathsToLink = [ "/libexec" ];

    programs.sway.extraSessionCommands = ''
      # see https://wiki.debian.org/Wayland#Toolkits
      export GDK_BACKEND=wayland
      export SDL_VIDEODRIVER=wayland
      export QT_QPA_PLATFORM='wayland;xcb'
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
      export _JAVA_AWT_WM_NONREPARENTING=1
      export MOZ_ENABLE_WAYLAND=1
      export MOZ_DBUS_REMOTE=1

      eval $(gnome-keyring-daemon --start)
      export SSH_AUTH_SOCK
    '';

    systemd.user.targets.sway-session = {
      description = "Sway compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };

    environment.etc."sway/config.d/systemd-init-10.conf".source = let
      initPolkit = (pkgs.writeScriptBin "_sway-init-polkit" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do sleep 1; done
        exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
      '');
      in pkgs.writeText "sway-systemd-init.conf" ''
        exec ${initPolkit}/bin/_sway-init-polkit
      '';

    systemd.user.services.xfce4-notifyd.enable = false;

    programs.sway.extraPackages = with pkgs; [
      (pkgs.writeScriptBin "_sway-wait-ready" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        interval=3
        until systemctl --user is-active --quiet sway-session.target ; do sleep "$interval"; done
        test "$#" -lt 1 || exec "$@"
      '')
      (pkgs.writeScriptBin "_sway-root-gui" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        if [ "$1" == "--enable" ] ; then
          ${pkgs.xlibs.xhost}/bin/xhost si:localuser:root
        else
          ${pkgs.xlibs.xhost}/bin/xhost -si:localuser:root
        fi
      '')

      swaylock
      swayidle
      waybar
      wl-clipboard
      wl-clipboard-x11
      wf-recorder
      v4l-utils
      mako
      alacritty
      dmenu
      libappindicator
      libappindicator-gtk3
      grim
      wlogout
      libnotify
      slurp
      qt5.qtwayland
      qt5Full

      xorg.xeyes
      xlibs.xhost

      # audio
      libopenaptx
      libfreeaptx
      pulseaudio

      # sway related
      brightnessctl
      polkit_gnome
      lxappearance
      xsettingsd
      gsettings-desktop-schemas
      gnome.networkmanagerapplet
      gtk_engines
      gtk-engine-murrine
      # wayland programs
      autotiling
      gammastep
      clipman
      wofi
      wev # wayland event viewer
      swayr # window switcher
      kanshi # autorandr
      wshowkeys # display pressed keys
      wdisplays # randr equivalent

      # themes
      hicolor-icon-theme # see https://github.com/NixOS/nixpkgs/issues/32730
      gnome-icon-theme # see https://github.com/NixOS/nixpkgs/issues/43836#issuecomment-419217138
      gnome3.adwaita-icon-theme
      adwaita-qt
      glib # gsettings
      gnome.dconf-editor
    ];

    xdg.portal.enable = true;
    xdg.portal.gtkUsePortal = true;
    xdg.portal.wlr.enable = true;
    xdg.portal.extraPortals = with pkgs; [
      # # xdg.portal.gtkUsePortal requires implementation in here (there is more than 1)
      # # it is provided by gnome at https://github.com/NixOS/nixpkgs/blob/b2737d4980a17cc2b7d600d7d0b32fd7333aca88/nixos/modules/services/x11/desktop-managers/gnome.nix#L377-L380
      # xdg-desktop-portal-gtk

    ];
  };
}
