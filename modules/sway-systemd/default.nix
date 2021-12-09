{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.services.sway-systemd;
  mandatoryEnvs = toString [
    "DISPLAY"
    "WAYLAND_DISPLAY"
    "SWAYSOCK"
    "XDG_CURRENT_DESKTOP"
  ];
in {
  options.services.sway-systemd = {
    enable = mkEnableOption "running Sway WM as a systemd service";
  };

  config = mkIf cfg.enable {
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

    systemd.user.services.sway = {
      description = "Sway - Wayland window manager";
      documentation = [ "man:sway(5)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
      # We explicitly unset PATH here, as we want it to be set by
      # systemctl --user import-environment in startsway
      environment.PATH = lib.mkForce null;
      serviceConfig = {
        Type = "notify";
        # NotifyAccess = "exec";
        NotifyAccess = "all";
        # wrapper already contains dbus-session-run
        ExecStart = "/run/current-system/sw/bin/sway";
        ExecStopPost = "systemctl --user unset-environment ${mandatoryEnvs}";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

  #  systemd.user.services.swayidle = {
  #    description = "Idle Manager for Wayland";
  #    documentation = [ "man:swayidle(1)" ];
  #    wantedBy = [ "sway-session.target" ];
  #    partOf = [ "graphical-session.target" ];
  #    path = [ pkgs.bash ];
  #    serviceConfig = {
  #      ExecStart = ''
  #        ${pkgs.swayidle}/bin/swayidle -w -d \
  #               timeout 300 '${pkgs.sway}/bin/swaymsg "output * dpms off"' \
  #               resume '${pkgs.sway}/bin/swaymsg "output * dpms on"'
  #             '';
  #    };
  #  };

    environment.etc."sway/config.d/sway-systemd-init.conf".source = pkgs.writeText "sway-systemd-init.conf" ''
      exec _sway-init
      exec _sway-init-polkit
    '';

    programs.sway.extraPackages = with pkgs; [
      (pkgs.writeScriptBin "startsway" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        systemctl --user import-environment $(${pkgs.jq}/bin/jq -rn 'env | keys[]')
        exec systemctl --user start sway.service
      '')
      # tray opens up too late https://github.com/Alexays/Waybar/issues/483
      (pkgs.writeScriptBin "_sway-init" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        interval=2
        until systemctl --user show-environment | grep WAYLAND_DISPLAY ; do
          sleep "$interval"
          dbus-update-activation-environment --systemd --all --verbose
        done
        until pgrep -fu $UID polkit-gnome-authentication-agent-1 ; do sleep "$interval"; done
        until pgrep -fu $UID waybar && sleep 3 ; do sleep "$interval"; done
        systemctl --user start sway-session.target
        systemd-notify --ready
        test "$#" -lt 1 || exec "$@"
      '')
      (pkgs.writeScriptBin "_sway-init-polkit" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do sleep 1; done
        exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
      '')
      (pkgs.writeScriptBin "_sway-wait-ready" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        interval=3
        until systemctl --user is-active --quiet sway-session.target ; do sleep "$interval"; done
        test "$#" -lt 1 || exec "$@"
      '')

      swaylock
      swayidle
      waybar
      wl-clipboard
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

      # Gnome services
      gnome.gnome-keyring
      gcr
    ];

    # services.gnome.gnome-keyring.enable replacement goes below:
    services.dbus.packages = [
      pkgs.gnome.gnome-keyring
      pkgs.gcr
    ];
    #security.wrappers.gnome-keyring-daemon = {
    #  source = "${pkgs.gnome.gnome-keyring}/bin/gnome-keyring-daemon";
    #  capabilities = "cap_ipc_lock=ep";
    #};

    xdg.portal.enable = true;
    xdg.portal.gtkUsePortal = true;
    xdg.portal.wlr.enable = true;
    xdg.portal.extraPortals = with pkgs; [
      xdg-desktop-portal-gtk # xdg.portal.gtkUsePortal requires implementation in here (there is more than 1)
      gnome.gnome-keyring
    ];
  };
}
