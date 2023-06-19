{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.sway.base;

  startsway-headless = pkgs.writeShellApplication {
    name = "startsway-headless";
    runtimeInputs = with pkgs; [ startsway ];
    text = ''
      export WLR_BACKENDS=headless
      export WLR_LIBINPUT_NO_DEVICES=1
      export XDG_SESSION_TYPE=wayland

      exec startsway
    '';
  };

  startsway = pkgs.writeShellApplication {
    name = "startsway";
    runtimeInputs = with pkgs; [ systemd sessionClearEnv sessionLoadEnv ];
    text = ''
      sway-session-clear-env
      sway-session-load-env
      exec systemctl --user start sway.service
    '';
  };

  sessionLoadEnv = pkgs.writeShellApplication {
    name = "sway-session-load-env";
    runtimeInputs = with pkgs; [ dbus jq ];
    text = ''
      readarray -t envs <<<"$(jq -rn 'env | to_entries[] | "\(.key)=\(.value)"')"
      dbus-update-activation-environment --systemd "''${envs[@]}"
    '';
  };

  sessionClearEnv = pkgs.writeShellApplication {
    name = "sway-session-clear-env";
    runtimeInputs = with pkgs; [ dbus systemd jq ];
    text = ''
      readarray -t set_empty < <(systemctl --user show-environment -o json | jq -r 'keys[] | "\(.)="')
      dbus-update-activation-environment "''${set_empty[@]}"
      readarray -t keys < <(systemctl --user show-environment -o json | jq -r 'keys[]')
      systemctl --user unset-environment "''${keys[@]}"
    '';
  };
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

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      ## systemd
      programs.sway.extraPackages = with pkgs; [
        sessionLoadEnv
        sessionClearEnv
        startsway
        startsway-headless
        seatd
      ];
    }
    {
      kdn.desktop.base.enable = true;
      services.xserver.displayManager.defaultSession = "sway";

      systemd.user.services.thunar.enable = false; # doesn't pick up proper MIME types when run as daemon

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
        NIXOS_OZONE_WL = "1";
      };

      programs.sway.extraSessionCommands = ''
        . /etc/profile

        # cfg.environmentDefaults
        export ${lib.concatStringsSep " \\\n  " cfg.environmentDefaults}

        # cfg.environment
        export ${lib.concatStringsSep " \\\n  " cfg.environment}
      '';

      systemd.user.services.sway = {
        description = "Sway - Wayland window manager";
        documentation = [ "man:sway(5)" ];
        bindsTo = [ "graphical-session.target" "kdn-sway-session.target" ];
        wants = [ "graphical-session-pre.target" ];
        after = [ "graphical-session-pre.target" ];
        before = [ "graphical-session.target" ];
        # We explicitly unset PATH here, as we want it to be set by
        # systemctl --user import-environment in startsway
        environment.PATH = lib.mkForce null;
        environment.KDN_SWAY_SYSTEMD = "1";
        serviceConfig = {
          Type = "notify";
          # NotifyAccess = "exec";
          NotifyAccess = "all";
          ExecStart = "/run/current-system/sw/bin/sway";
          ExecStopPost = "${sessionClearEnv}/bin/sway-session-clear-env";
          Restart = "no";
          RestartSec = 1;
          TimeoutStopSec = 60;
          TimeoutStartSec = 300;
        };
      };

      systemd.user.targets."kdn-sway-session" = {
        description = "Sway compositor session";
        documentation = [ "man:systemd.special(7)" ];
        bindsTo = [ "graphical-session.target" "sway.service" ];
        requires = [ "kdn-sway-envs.target" "kdn-sway-tray.target" "sway.service" ];
        after = [ "graphical-session-pre.target" "kdn-sway-envs.target" "sway.service" ];
        wants = [ "graphical-session-pre.target" ];
      };

      systemd.user.targets."kdn-sway-envs" = {
        description = "Sway target active after loading env";
        partOf = [ "kdn-sway-session.target" ];
        bindsTo = [ "kdn-sway-envs.service" ];
        requires = [ "kdn-sway-envs.service" ];
        after = [ "kdn-sway-envs.service" ];
      };
      systemd.user.services."kdn-sway-envs" = {
        description = "Wait for envs being present";
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        script = ''
          set -x
          until systemctl --user show-environment | grep -q WAYLAND_DISPLAY ; do
            sleep 1
          done
          until systemctl --user show-environment | grep -q KDN_SWAY_SYSTEMD ; do
            sleep 1
          done
        '';
      };

      systemd.user.targets."kdn-sway-tray" = {
        description = "tray target for kdn Sway";
        bindsTo = [ "tray.target" ];
        before = [ "kdn-sway-session.target" "tray.target" ];
        after = [ "kdn-sway-envs.target" ];
        requires = [ "kdn-sway-envs.target" ];
      };

      systemd.user.services."xdg-desktop-portal" = {
        requires = [ "kdn-sway-envs.target" ];
        after = [ "kdn-sway-envs.target" ];
        partOf = [ "kdn-sway-session.target" ];
      };

      systemd.user.services."xdg-desktop-portal-gtk" = {
        requires = [ "kdn-sway-envs.target" ];
        after = [ "kdn-sway-envs.target" ];
        partOf = [ "kdn-sway-session.target" ];
      };

      systemd.user.services."kdn-sway-polkit-agent" = {
        description = "Polkit Agent service";
        partOf = [ "kdn-sway-session.target" ];
        requires = [ "kdn-sway-envs.target" ];
        after = [ "kdn-sway-envs.target" ];
        script = cfg.polkitAgentCommand;
      };

      kdn.sway.base.initScripts.systemd = {
        "00-update-systemd-environment" = "${sessionLoadEnv}/bin/sway-session-load-env";
        "99-notify-systemd-service" = "${pkgs.systemd}/bin/systemd-notify --ready";
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
            systemd.enable = false;
          };
        }
      ];

      programs.sway.extraPackages = with pkgs; [
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
    }
  ]);
}
