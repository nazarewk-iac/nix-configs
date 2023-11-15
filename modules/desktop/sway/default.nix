{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.desktop.sway;
in
{
  options.kdn.desktop.sway = {
    enable = lib.mkEnableOption "Sway base setup";

    prefix = lib.mkOption { default = "kdn-sway"; };
    desktopSessionName = lib.mkOption { default = cfg.prefix; };

    bundle = lib.mkOption {
      type = with lib.types; package;
      default =
        let
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
            runtimeInputs = with pkgs; [ systemd envClear envLoad ];
            text = ''
              ${cfg.prefix}-session-clear-env
              ${cfg.prefix}-session-set-env
              exec systemctl --user start ${config.kdn.desktop.sway.systemd.sway.service} "$@"
            '';
          };

          envLoad = pkgs.writeShellApplication {
            name = "${cfg.prefix}-session-set-env";
            runtimeInputs = with pkgs; [ dbus jq ];
            text = ''
              envs=()
              keys=()
              for arg in "$@"; do
                if [[ "$arg" == *=* ]]; then
                  envs+=("$arg")
                else
                  keys+=("$arg")
                fi
              done
              if [[ "$#" == 0 ]]; then
                readarray -t keys < <(jq -rn 'env|keys[]')
              fi
              for key in "''${keys[@]}"; do
                envs+=("$key=''${!key}")
              done
              dbus-update-activation-environment --systemd "''${envs[@]}"
            '';
          };

          envClear = pkgs.writeShellApplication {
            name = "${cfg.prefix}-session-clear-env";
            runtimeInputs = with pkgs; [ dbus systemd jq ];
            text = ''
              keys=("$@")
              if [[ "$#" == 0 ]]; then
                readarray -t keys < <(systemctl --user show-environment -o json | jq -r 'keys[]')
              fi
              set_empty=()
              for key in "''${keys[@]}"; do
                set_empty+=("$key=")
              done
              dbus-update-activation-environment "''${set_empty[@]}"
              systemctl --user unset-environment "''${keys[@]}"
            '';
          };

          waylandSessionEntry = pkgs.writeTextFile {
            name = "${cfg.desktopSessionName}-wayland-session";
            destination = "/share/wayland-sessions/${cfg.desktopSessionName}.desktop";
            # TODO: SDDM doesn't properly exit this session
            text = ''
              [Desktop Entry]
              Name=${cfg.desktopSessionName} Sway
              Comment=An i3-compatible Wayland compositor
              Exec=${startsway}/bin/startsway --wait
              Type=Application
            '';
          };
        in
        pkgs.symlinkJoin {
          name = "${cfg.prefix}-bundle";
          passthru.providedSessions = [ cfg.desktopSessionName ];
          paths = [
            envClear
            waylandSessionEntry
            envLoad
            startsway
            startsway-headless
          ];
        };
    };

    systemd = lib.mkOption {
      type = with lib.types; attrsOf (submodule ({ name, ... }@args: {
        options = {
          prefix = lib.mkOption {
            type = with lib.types; str;
            default = config.kdn.desktop.sway.prefix;
          };
          suffix = lib.mkOption {
            type = with lib.types; str;
            default = "-${name}";
          };
          name = lib.mkOption {
            type = with lib.types; str;
            default = "${args.config.prefix}${args.config.suffix}";
          };
          units = lib.mkOption {
            type = with lib.types; listOf str;
          };
        };
      }));
      default = {
        sway.suffix = "";
        sway.units = [ "service" ];
        session.units = [ "target" ];
        envs.units = [ "service" "target" ];
        tray.units = [ "target" ];
        polkit-agent.units = [ "service" ];
        secrets-service.units = [ "service" "target" ];
      };
      apply = builtins.mapAttrs (key: value: (lib.trivial.pipe value.units [
        (builtins.map (unit: {
          name = unit;
          value = "${value.name}.${unit}";
        }))
        builtins.listToAttrs
        (attrs: attrs // value)
      ]));
    };

    polkitAgent.package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.libsForQt5.polkit-kde-agent;
    };
    polkitAgent.command = lib.mkOption {
      type = with lib.types; str;
      default = "${cfg.polkitAgent.package}/libexec/polkit-kde-authentication-agent-1";
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
      nixpkgs.overlays = [
        (final: prev: {
          # see https://github.com/NixOS/nixpkgs/issues/238416#issuecomment-1618662374
          # TODO: remove after https://github.com/NixOS/nixpkgs/issues/238416 is resolved upstream
          #element-desktop = prev.element-desktop.override { electron = prev.electron_24; };
        })
      ];
      programs.sway.extraPackages = [ cfg.bundle ];
    }
    {
      # Configure various Sway configs
      # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
      # see https://nixos.wiki/wiki/Sway#Systemd_integration
      programs.sway.enable = true;
      programs.sway.wrapperFeatures.gtk = true;
      programs.sway.extraOptions = [ "--verbose" "--debug" ];
      programs.sway.extraSessionCommands = ''
        # rename NOTIFY_SOCKET to workaround podman systemd detection
        # can be removed when NotifyAccess=all pattern is changed
        export KDN_SWAY_NOTIFY_SOCKET="''${NOTIFY_SOCKET:-}"
        test -z "$KDN_SWAY_NOTIFY_SOCKET" || unset NOTIFY_SOCKET
        . /etc/profile

        # cfg.environmentDefaults
        export \
          ${lib.concatStringsSep " \\\n  " cfg.environmentDefaults}

        # cfg.environment
        export \
          ${lib.concatStringsSep " \\\n  " cfg.environment}
      '';

      services.xserver.displayManager.defaultSession = cfg.desktopSessionName;
      services.xserver.displayManager.sessionPackages = [ cfg.bundle ];
    }
    {
      home-manager.sharedModules = [{
        kdn.desktop.sway = {
          inherit (cfg) enable prefix systemd;
        };
        wayland.windowManager.sway = {
          inherit (config.programs.sway) package;
          systemd.enable = false;
        };
      }];
    }
    {
      kdn.desktop.base.enable = true;

      systemd.user.services.thunar.enable = false; # doesn't pick up proper MIME types when run as daemon

      # see https://wiki.debian.org/Wayland#Toolkits
      kdn.desktop.sway.environmentDefaults = {
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        # see https://github.com/swaywm/wlroots/issues/3189#issuecomment-461608727
        WLR_NO_HARDWARE_CURSORS = "1";
      };

      kdn.desktop.sway.environment = {
        # see https://wiki.debian.org/Wayland#Toolkits

        # Note that some Electron applications (Slack, Element, Discord, etc.) or chromium (861796) may break when setting GDK_BACKEND to "wayland".
        GDK_BACKEND = "wayland"; # teams does break
        SDL_VIDEODRIVER = "wayland";
        QT_QPA_PLATFORM = "wayland;xcb";
        _JAVA_AWT_WM_NONREPARENTING = "1";
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_DBUS_REMOTE = "1";
        # warning: The option `xdg.portal.gtkUsePortal' defined in `/nix/store/y48ib2rr4sd4y8v4wdxqiff2jydjir1z-source/modules/desktop/sway/base/default.nix' has been deprecated. Setting the variable globally with `environment.sessionVariables' NixOS option can have unforseen side-effects.
        GTK_USE_PORTAL = "1";
        NIXOS_OZONE_WL = "1";
      };


      systemd.user.services."${config.kdn.desktop.sway.systemd.sway.name}" = {
        description = config.kdn.desktop.sway.systemd.sway.service;
        documentation = [ "man:sway(5)" ];
        bindsTo = [ "graphical-session.target" config.kdn.desktop.sway.systemd.session.target ];
        wants = [ "graphical-session-pre.target" ];
        after = [ "graphical-session-pre.target" ];
        before = [ "graphical-session.target" ];
        # We explicitly unset PATH here, as we want it to be set by
        # systemctl --user import-environment in startsway
        environment.PATH = lib.mkForce null;
        environment.KDN_SWAY_SYSTEMD = "1";
        serviceConfig.Slice = "session.slice";
        serviceConfig = {
          Type = "notify";
          /*
            TODO: change NotifyAccess to something else to prevent Podman from killing Sway
              KDN_SWAY_NOTIFY_SOCKET rename can be removed after this one is working
              see https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#NotifyAccess=
              see https://gist.github.com/nazarewk/9e071fd43e1803ffaa1726a273f30419#resolution
          */
          NotifyAccess = "all";
          #ExecStart = "/run/current-system/sw/bin/sway";
          ExecStart = "/run/wrappers/bin/sway";
          ExecStopPost = "${cfg.bundle}/bin/${cfg.prefix}-session-clear-env";
          Restart = "no";
          RestartSec = 1;
          TimeoutStopSec = 60;
          TimeoutStartSec = 300;
          #AmbientCapabilities = [ "CAP_SYS_NICE" ];
        };
      };

      systemd.user.targets."${config.kdn.desktop.sway.systemd.session.name}" = {
        description = config.kdn.desktop.sway.systemd.session.target;
        documentation = [ "man:systemd.special(7)" ];
        bindsTo = [
          "graphical-session.target"
          config.kdn.desktop.sway.systemd.sway.service
        ];
        requires = [
          config.kdn.desktop.sway.systemd.envs.target
          config.kdn.desktop.sway.systemd.tray.target
          config.kdn.desktop.sway.systemd.sway.service
        ];
        after = [
          "graphical-session-pre.target"
          config.kdn.desktop.sway.systemd.envs.target
          config.kdn.desktop.sway.systemd.sway.service
        ];
        wants = [ "graphical-session-pre.target" ];
      };

      systemd.user.targets."${config.kdn.desktop.sway.systemd.envs.name}" = {
        description = config.kdn.desktop.sway.systemd.envs.target;
        partOf = [ config.kdn.desktop.sway.systemd.session.target ];
        bindsTo = [ config.kdn.desktop.sway.systemd.envs.service ];
        requires = [ config.kdn.desktop.sway.systemd.envs.service ];
        after = [ config.kdn.desktop.sway.systemd.envs.service ];
      };
      systemd.user.services."${config.kdn.desktop.sway.systemd.envs.name}" = {
        description = config.kdn.desktop.sway.systemd.envs.service;
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
      systemd.user.targets."${config.kdn.desktop.sway.systemd.secrets-service.name}" = {
        description = config.kdn.desktop.sway.systemd.secrets-service.target;
        bindsTo = [ config.kdn.desktop.sway.systemd.secrets-service.service ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        requires = [ config.kdn.desktop.sway.systemd.envs.target ];
      };

      systemd.user.services."${config.kdn.desktop.sway.systemd.secrets-service.name}" = {
        description = config.kdn.desktop.sway.systemd.secrets-service.service;
        requires = [ config.kdn.desktop.sway.systemd.envs.target ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        partOf = [ config.kdn.desktop.sway.systemd.session.target ];
        script = lib.mkDefault "${pkgs.coreutils}/bin/sleep infinity";
        serviceConfig.Slice = "background.slice";
        serviceConfig.Type = "dbus";
        serviceConfig.BusName = "org.freedesktop.secrets";
      };

      systemd.user.targets."${config.kdn.desktop.sway.systemd.tray.name}" = {
        description = config.kdn.desktop.sway.systemd.tray.target;
        bindsTo = [ "tray.target" ];
        before = [ config.kdn.desktop.sway.systemd.session.target "tray.target" ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        requires = [ config.kdn.desktop.sway.systemd.envs.target ];
      };

      systemd.user.services."xdg-desktop-portal" = {
        requires = [ config.kdn.desktop.sway.systemd.envs.target ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        partOf = [ config.kdn.desktop.sway.systemd.session.target ];
        serviceConfig.Slice = "background.slice";
      };

      systemd.user.services."xdg-desktop-portal-gtk" = {
        requires = [ config.kdn.desktop.sway.systemd.envs.target ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        partOf = [ config.kdn.desktop.sway.systemd.session.target ];
        serviceConfig.Slice = "background.slice";
      };

      systemd.user.services."${config.kdn.desktop.sway.systemd.polkit-agent.name}" = {
        description = config.kdn.desktop.sway.systemd.polkit-agent.service;
        partOf = [ config.kdn.desktop.sway.systemd.session.target ];
        requires = [ config.kdn.desktop.sway.systemd.envs.target ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        script = cfg.polkitAgent.command;
        serviceConfig.Slice = "background.slice";
      };

      kdn.desktop.sway.initScripts.systemd = {
        "00-update-systemd-environment" = "${cfg.bundle}/bin/${cfg.prefix}-session-set-env";
        "99-notify-systemd-service" = ''
          # use renamed NOTIFY_SOCKET to workaround podman systemd detection
          # can be removed when NotifyAccess=all pattern is changed
          NOTIFY_SOCKET="$KDN_SWAY_NOTIFY_SOCKET" ${pkgs.systemd}/bin/systemd-notify --ready
        '';
      };

      environment.etc."sway/config.d/00-${config.kdn.desktop.sway.prefix}-init.conf".text = lib.trivial.pipe cfg.initScripts [
        (lib.mapAttrsToList (
          execName: pieces:
            let
              scriptName = "${config.kdn.desktop.sway.prefix}-init-${execName}";
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

        wofi

        grim
        libnotify
        swayidle
        swaylock
        waybar
        wf-recorder

        gsimplecal
        slurp
        wlogout

        cfg.polkitAgent.package

        # sway related
        autotiling
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
    }
    (lib.mkIf config.programs.gnupg.agent.enable {
      systemd.user.services."gpg-agent" = {
        unitConfig.Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
        after = [ config.kdn.desktop.sway.systemd.envs.target ];
        serviceConfig.Slice = "background.slice";
      };
    })
  ]);
}
