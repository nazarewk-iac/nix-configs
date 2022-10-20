{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.sway.base;
in
{
  options.kdn.sway.base = {
    enable = lib.mkEnableOption "Sway base setup";

    systemd.target = mkOption {
      type = types.str;
      default = "sway-session-kdn";
    };

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
    kdn.desktop.base.enable = true;
    kdn.gnome.base.enable = true;
    kdn.xfce.base.enable = true;

    systemd.user.services.thunar = {
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
    };

    # Configure various Sway configs
    # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
    # see https://nixos.wiki/wiki/Sway#Systemd_integration
    programs.sway.enable = true;
    programs.sway.wrapperFeatures.gtk = true;
    programs.sway.extraOptions = [ "--verbose" "--debug" ];
    environment.pathsToLink = [ "/libexec" ];

    # see https://wiki.debian.org/Wayland#Toolkits
    kdn.sway.base.environmentDefaults = {
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      # see https://github.com/swaywm/wlroots/issues/3189#issuecomment-461608727
      WLR_NO_HARDWARE_CURSORS = "1";
      SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/keyring/ssh";
    };

    kdn.sway.base.environment = {
      # see https://wiki.debian.org/Wayland#Toolkits

      # Note that some Electron applications (Slack, Element, Discord, etc.) or chromium (861796) may break when setting GDK_BACKEND to "wayland".
      # GDK_BACKEND = "wayland"; # teams does break
      SDL_VIDEODRIVER = "wayland";
      QT_QPA_PLATFORM = "wayland;xcb";
      _JAVA_AWT_WM_NONREPARENTING = "1";
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_DBUS_REMOTE = "1";
    };

    programs.sway.extraSessionCommands = ''
      . /etc/profile

      # cfg.environmentDefaults
      export ${lib.concatStringsSep " \\\n  " cfg.environmentDefaults}

      # cfg.environment
      export ${lib.concatStringsSep " \\\n  " cfg.environment}
    '';

    systemd.user.targets."${cfg.systemd.target}" = {
      description = "Sway compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };

    kdn.sway.base.initScripts.polkit = {
      "00-init" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ procps systemd ])}:$PATH"
        until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do sleep 1; done
        exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
      '';
    };
    kdn.sway.base.initScripts.systemd = {
      "01-update-systemd-environment" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ dbus systemd ])}:$PATH"

        until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do
          sleep 1
        done
        dbus-update-activation-environment --systemd --all --verbose
      '';
      "50-wait-polkit" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ procps ])}:$PATH"
        until pgrep -fu $UID polkit-gnome-authentication-agent-1 ; do sleep 1; done
      '';
      # because tray opens up too late https://github.com/Alexays/Waybar/issues/483
      "99-start-${cfg.systemd.target}" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ dbus procps systemd ])}:$PATH"
        systemctl --user start ${cfg.systemd.target}.target
      '';
    };

    environment.etc."sway/config.d/00-kdn-init.conf".text = lib.pipe cfg.initScripts [
      (lib.mapAttrsToList (
        execName: pieces:
          let
            scriptName = "kdn-sway-init-${execName}";
            scriptContent = lib.pipe pieces [
              (lib.mapAttrsToList (
                pieceName: piece:
                  let
                    pieceScriptName = "${scriptName}-${pieceName}";
                    pieceScript = pkgs.writeScriptBin pieceScriptName piece;
                  in
                  "${pieceScript}/bin/${pieceScriptName}"
              ))
              (lib.concatStringsSep "\n")
            ];
            script = pkgs.writeScriptBin scriptName ''
              #!${pkgs.bash}/bin/bash
              set -xEeuo pipefail
              ${scriptContent}
            '';
          in
          "exec ${script}/bin/${scriptName}"
      ))
      (lib.concatStringsSep "\n")
    ];

    systemd.user.services.xfce4-notifyd.enable = false;

    home-manager.sharedModules = [
      {
        kdn.sway.base.enable = true;
        wayland.windowManager.sway = {
          inherit (config.programs.sway) extraSessionCommands extraOptions wrapperFeatures;
          systemdIntegration = false;
        };
      }
    ];

    programs.sway.extraPackages = with pkgs; [
      (pkgs.writeScriptBin "_sway-wait-ready" ''
        #! ${pkgs.bash}/bin/bash
        set -xeEuo pipefail
        until systemctl --user is-active --quiet "${cfg.systemd.target}.target" ; do sleep 1; done
        until systemctl --user is-active --quiet "tray.target" ; do sleep 1; done
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
      dmenu
      grim
      wlogout
      libnotify
      slurp
      gsimplecal

      # sway related
      brightnessctl
      polkit_gnome
      lxappearance
      xsettingsd
      gsettings-desktop-schemas
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
      gnome.adwaita-icon-theme
      adwaita-qt
      glib # gsettings
      gnome.dconf-editor
    ];

    xdg.portal.enable = true;
    xdg.portal.gtkUsePortal = true;
    xdg.portal.wlr.enable = true;
    xdg.portal.wlr.settings = {
      screencast = {
        chooser_type = "dmenu";
        # https://github.com/emersion/xdg-desktop-portal-wlr/blob/1cc5ff570d745facbde4237ac96634502ec0cae6/src/screencast/wlr_screencast.c#L471-L473
        # use wofi instead
        chooser_cmd = "${pkgs.wofi}/bin/wofi -d -n --prompt='Select the monitor to share:'";
      };
    };
  };
}
