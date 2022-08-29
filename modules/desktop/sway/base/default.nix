{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.base;
in
{
  options.nazarewk.sway.base = {
    enable = mkEnableOption "Sway base setup";

    initScripts = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      default = { };
    };

    environmentDefaults = mkOption {
      type = types.attrsOf types.str;
      default = { };
      apply = input:
        let
          escapeDefault = arg: ''"${replaceStrings [''"''] [''\"''] (toString arg)}"'';
        in
        (mapAttrsToList (n: v: "${n}=\"\${${n}:-${escapeDefault v}}\"") input);
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      apply = input: mapAttrsToList lib.toShellVar input;
    };
  };

  config = mkIf cfg.enable {
    nazarewk.desktop.base.enable = true;
    nazarewk.gnome.base.enable = true;
    nazarewk.xfce.base.enable = true;

    # TODO: figure out why thunar.service does not consume session environment
    systemd.user.services.thunar.enable = false;

    # Configure various Sway configs
    # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
    # see https://nixos.wiki/wiki/Sway#Systemd_integration
    programs.sway.enable = true;
    programs.sway.wrapperFeatures.gtk = true;
    programs.sway.extraOptions = [ "--verbose" "--debug" ];
    environment.pathsToLink = [ "/libexec" ];

    # see https://wiki.debian.org/Wayland#Toolkits
    nazarewk.sway.base.environmentDefaults = {
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      # see https://github.com/swaywm/wlroots/issues/3189#issuecomment-461608727
      WLR_NO_HARDWARE_CURSORS = "1";
    };

    nazarewk.sway.base.environment = {
      # see https://wiki.debian.org/Wayland#Toolkits
      GDK_BACKEND = "wayland";
      SDL_VIDEODRIVER = "wayland";
      QT_QPA_PLATFORM = "wayland;xcb";
      _JAVA_AWT_WM_NONREPARENTING = "1";
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_DBUS_REMOTE = "1";
    };

    programs.sway.extraSessionCommands = ''
      . /etc/profile

      export ${lib.concatStringsSep " \\\n  " cfg.environmentDefaults}
      export ${lib.concatStringsSep " \\\n  " cfg.environment}
      eval $(${pkgs.gnome.gnome-keyring}/bin/gnome-keyring-daemon --start)
      export SSH_AUTH_SOCK
    '';

    systemd.user.targets.sway-session = {
      description = "Sway compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };

    # because tray opens up too late https://github.com/Alexays/Waybar/issues/483

    nazarewk.sway.base.initScripts.polkit = {
      "00-init" = ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail

        until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do sleep 1; done
        exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
      '';
    };
    nazarewk.sway.base.initScripts.systemd = {
      "50-wait-polkit" = ''
        #!${pkgs.bash}/bin/bash
        set -xeEuo pipefail

        until pgrep -fu $UID polkit-gnome-authentication-agent-1 ; do sleep 2; done
      '';
      # because tray opens up too late https://github.com/Alexays/Waybar/issues/483
      "50-wait-waybar" = ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail

        until pgrep -fu $UID waybar && sleep 3 ; do sleep 2; done
      '';
      "90-start-sway-session" = ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail

        systemctl --user start sway-session.target
      '';
    };

    environment.etc."sway/config.d/00-nazarewk-init.conf".text = lib.concatStringsSep "\n" (lib.mapAttrsToList
      (
        execName: scripts:
          let
            scriptName = "nazarewk-sway-init-${execName}";
            scriptContent = lib.concatStringsSep "\n" (lib.mapAttrsToList
              (
                pieceName: piece:
                  let
                    pieceScriptName = "${scriptName}-${pieceName}";
                    pieceScript = pkgs.writeScriptBin pieceScriptName piece;
                  in
                  "${pieceScript}/bin/${pieceScriptName}"
              )
              scripts);
            script = pkgs.writeScriptBin scriptName ''
              #!${pkgs.bash}/bin/bash
              set -xEeuo pipefail
              ${scriptContent}
            '';
          in
          "exec ${script}/bin/${scriptName}"
      )
      cfg.initScripts);

    systemd.user.services.xfce4-notifyd.enable = false;

    services.dbus.packages = with pkgs; [
      # mako
    ];


    home-manager.sharedModules = [
      {
        # according to Dunst FAQ https://dunst-project.org/faq/#cannot-acquire-orgfreedesktopnotifications
        # you might need to create a file in home directory instead of system-wide to select proper notification daemon
        home.file.".local/share/dbus-1/services/fr.emersion.mako.service".source = "${pkgs.mako}/share/dbus-1/services/fr.emersion.mako.service";
      }
    ];

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
          ${pkgs.xorg.xhost}/bin/xhost si:localuser:root
        else
          ${pkgs.xorg.xhost}/bin/xhost -si:localuser:root
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
      foot
      dmenu
      libappindicator
      libappindicator-gtk3
      grim
      wlogout
      libnotify
      slurp

      # sway related
      brightnessctl
      polkit_gnome
      lxappearance
      xsettingsd
      gsettings-desktop-schemas
      networkmanagerapplet
      gtk_engines
      gtk-engine-murrine
      # wayland programs
      autotiling
      gammastep
      clipman
      wofi
      wev # wayland event viewer
      evtest # listens for /dev/event* device events (eg: keyboard keys, function keys etc)
      swayr # window switcher
      kanshi # autorandr
      wshowkeys # display pressed keys
      wdisplays # randr equivalent
      wlr-randr
      wayland-utils

      # themes
      hicolor-icon-theme # see https://github.com/NixOS/nixpkgs/issues/32730
      gnome-icon-theme # see https://github.com/NixOS/nixpkgs/issues/43836#issuecomment-419217138
      gnome3.adwaita-icon-theme
      adwaita-qt
      glib # gsettings
      gnome.dconf-editor
    ];

    xdg.portal.enable = true;
    environment.sessionVariables.GTK_USE_PORTAL = "1";
    xdg.portal.wlr.enable = true;
    xdg.portal.extraPortals = with pkgs; [
      # # xdg.portal.gtkUsePortal requires implementation in here (there is more than 1)
      # # it is provided by gnome at https://github.com/NixOS/nixpkgs/blob/b2737d4980a17cc2b7d600d7d0b32fd7333aca88/nixos/modules/services/x11/desktop-managers/gnome.nix#L377-L380
      # xdg-desktop-portal-gtk

    ];
  };
}
