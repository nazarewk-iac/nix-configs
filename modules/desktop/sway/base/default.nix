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

    polkitAgentCommand = mkOption {
      type = types.str;
      default = "${pkgs.libsForQt5.polkit-kde-agent}/libexec/polkit-kde-authentication-agent-1";
    };

    initScripts = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      default = { };
    };

    environmentDefaults = mkOption {
      type = types.attrsOf types.str;
      default = { };
      apply = lib.kdn.shell.makeShellDefaultAssignments;
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      apply = input: mapAttrsToList lib.toShellVar input;
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.desktop.base.enable = true;
    #kdn.xfce.base.enable = true;

    services.xserver.displayManager.defaultSession = "sway";

    systemd.user.services.thunar.enable = false; # doesn't pick up proper MIME files
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
      # warning: The option `xdg.portal.gtkUsePortal' defined in `/nix/store/y48ib2rr4sd4y8v4wdxqiff2jydjir1z-source/modules/desktop/sway/base/default.nix' has been deprecated. Setting the variable globally with `environment.sessionVariables' NixOS option can have unforseen side-effects.
      GTK_USE_PORTAL = "1";
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
        exec "${cfg.polkitAgentCommand}"
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
        until pgrep -fu $UID "${cfg.polkitAgentCommand}" ; do sleep 1; done
      '';
      # because tray opens up too late https://github.com/Alexays/Waybar/issues/483
      "99-start-${cfg.systemd.target}" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ dbus procps systemd ])}:$PATH"
        systemctl --user start ${cfg.systemd.target}.target
      '';
      # TODO: pass-secret-service doesn't get the WAYLAND_DISPLAY etc.
      # - maybe it starts before graphical-session.target is activated?
      #      4d3@oams ~> diff /tmp/envkeys-*
      #      < COLORTERM
      #      7d5
      #      < DISPLAY
      #      9d6
      #      < __ETC_PROFILE_DONE
      #      11d7
      #      < GDK_PIXBUF_MODULE_FILE
      #      16d11
      #      < GTK_USE_PORTAL
      #      20d14
      #      < I3SOCK
      #      23d16
      #      < _JAVA_AWT_WM_NONREPARENTING
      #      27d19
      #      < KDN_SWAY_SYSTEMD
      #      39,40d30
      #      < MOZ_DBUS_REMOTE
      #      < MOZ_ENABLE_WAYLAND
      #      48d37
      #      < NOTIFY_SOCKET
      #      58d46
      #      < QT_QPA_PLATFORM
      #      60d47
      #      < QT_WAYLAND_DISABLE_WINDOWDECORATION
      #      62d48
      #      < SDL_VIDEODRIVER
      #      67,68d52
      #      < SWAYSOCK
      #      < _SWAY_WRAPPER_ALREADY_EXECUTED
      #      70d53
      #      < TERM
      #      72,74c55
      #      < TERMINFO
      #      < TERM_PROGRAM
      #      < TERM_PROGRAM_VERSION
      #      ---
      #      > TERM
      #      78,79d58
      #      < WAYLAND_DISPLAY
      #      < WLR_NO_HARDWARE_CURSORS
      #      81,82d59
      #      < XCURSOR_SIZE
      #      < XCURSOR_THEME
      #      84d60
      #      < XDG_CURRENT_DESKTOP
      #      kdn@oams ~ [1]>
    };

    environment.etc."sway/config.d/00-kdn-init.conf".text = lib.trivial.pipe cfg.initScripts [
      (lib.mapAttrsToList (
        execName: pieces:
          let
            scriptName = "kdn-sway-init-${execName}";
            scriptContent = lib.trivial.pipe pieces [
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
        if [ "''${1:-}" == "--enable" ] ; then
          ${pkgs.xorg.xhost}/bin/xhost si:localuser:root
        else
          ${pkgs.xorg.xhost}/bin/xhost -si:localuser:root
        fi
      '')

      dmenu
      wofi

      grim
      libnotify
      swayidle
      swaylock
      waybar
      wf-recorder
      wl-clipboard
      wl-clipboard-x11

      gsimplecal
      slurp
      wlogout

      # polkit related
      # lxqt.lxqt-policykit # lxqt crashes after authenticating with U2F
      libsForQt5.polkit-kde-agent
      # polkit_gnome # asks for U2F twice then fails for no reason

      # sway related
      autotiling
      clipman
      gammastep
      kanshi # autorandr
      swayr # window switcher
      wayland-utils
      wdisplays # randr equivalent
      wlr-randr

      ashpd-demo # Tool for playing with XDG desktop portals
    ];

    xdg.portal.enable = true;
    xdg.portal.xdgOpenUsePortal = true;
    xdg.portal.extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    #xdg.portal.lxqt.enable = true;
    xdg.portal.wlr.enable = true;
    xdg.portal.wlr.settings = {
      screencast = {
        chooser_type = "dmenu";
        # https://github.com/emersion/xdg-desktop-portal-wlr/blob/1cc5ff570d745facbde4237ac96634502ec0cae6/src/screencast/wlr_screencast.c#L471-L473
        # use wofi instead
        chooser_cmd = "${pkgs.wofi}/bin/wofi -d -n --prompt='Select the monitor to share:'";
      };
    };

    # XFCE pieces
    services.tumbler.enable = true;
    programs.thunar.enable = true;
    programs.thunar.plugins = with pkgs.xfce; [
      thunar-archive-plugin
      thunar-volman
      thunar-media-tags-plugin
    ];
  };
}
