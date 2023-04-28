{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.sway.base;
in
{
  options.kdn.sway.base = {
    enable = lib.mkEnableOption "Sway base setup";

    polkitAgentCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.libsForQt5.polkit-kde-agent}/libexec/polkit-kde-authentication-agent-1";
    };

    initScripts = lib.mkOption {
      type = with lib.types; attrsOf (attrsOf str);
      default = { };
    };

    environmentDefaults = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
      apply = lib.kdn.shell.makeShellDefaultAssignments;
    };

    environment = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
      apply = input: lib.mapAttrsToList lib.toShellVar input;
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.desktop.base.enable = true;
    #kdn.xfce.base.enable = true;

    services.xserver.displayManager.defaultSession = "sway";

    systemd.user.services.thunar.enable = false; # doesn't pick up proper MIME files
    systemd.user.services.thunar = {
      after = [ "kdn-sway-envs.target" ];
      wantedBy = [ "kdn-sway-session.target" ];
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

    systemd.user.targets."kdn-sway-session" = {
      description = "Sway compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };

    systemd.user.targets."kdn-sway-envs" = {
      description = "Sway target after running dbus-update-activation-environment";
      partOf = [ "kdn-sway-session.target" ];
    };

    systemd.user.services."xdg-desktop-portal" = {
      requires = [ "kdn-sway-envs.target" ];
      after = [ "kdn-sway-envs.target" ];
    };

    systemd.user.targets."kdn-sway-tray" = {
      description = "Sway target after running dbus-update-activation-environment";
      bindsTo = [ "tray.target" ];
      partOf = [ "kdn-sway-session.target" ];
      before = [ "kdn-sway-session.target" ];
      wantedBy = [ "kdn-sway-session.target" ];
    };

    systemd.user.services."kdn-sway-polkit-agent" = {
      description = "Polkit Agent service";
      partOf = [ "kdn-sway-session.target" ];
      wants = [ "kdn-sway-envs.target" ];
      after = [ "kdn-sway-envs.target" ];
      serviceConfig.ExecStart = cfg.polkitAgentCommand;
    };

    kdn.sway.base.initScripts.systemd = {
      "01-update-systemd-environment" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ dbus systemd ])}:$PATH"

        until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do
          sleep 1
        done
        dbus-update-activation-environment --systemd --all --verbose
        systemctl --user start "kdn-sway-envs.target"
      '';
      "50-wait-polkit" = ''
        until systemctl --user is-active --quiet "kdn-sway-envs.target" ; do sleep 1; done
      '';
      # because tray opens up too late https://github.com/Alexays/Waybar/issues/483
      "99-start-kdn-sway" = ''
        export PATH="${lib.makeBinPath (with pkgs; [ dbus procps systemd ])}:$PATH"
        systemctl --user start "kdn-sway-session.target"
      '';
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
        until systemctl --user is-active --quiet "kdn-sway-session.target" ; do sleep 1; done
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
