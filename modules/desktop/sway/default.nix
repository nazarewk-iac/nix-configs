{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.desktop.sway;
  jsonFormat = pkgs.formats.json {};
in {
  # TODO: figure out why exiting Sway doesn't stop/restart `sddm-helper` aka `sddm` aka `display-manager.service`
  # TODO: figure out why exiting Sway a second time cannot `systemctl restart display-manager.service`
  # TODO: figure out why exiting Sway logs out all SSH sessions
  options.kdn.desktop.sway = {
    enable = lib.mkEnableOption "Sway base setup";

    keys = lib.mkOption {
      type = lib.types.submodule {freeformType = jsonFormat.type;};
    };

    prefix = lib.mkOption {default = "kdn-sway";};
    desktopSessionName = lib.mkOption {default = cfg.prefix;};

    bundle = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.callPackage ./bundle.nix {
        inherit (cfg) prefix desktopSessionName;
        serviceName = config.kdn.desktop.sway.systemd.sway.service;
      };
    };

    systemd = lib.mkOption {
      type = with lib.types;
        attrsOf (submodule ({name, ...} @ args: {
          options = {
            prefix = lib.mkOption {
              type = with lib.types; str;
              default = config.kdn.desktop.sway.prefix;
            };
            prefixes = lib.mkOption {
              type = with lib.types; listOf str;
              default = [
                args.config.prefix
                config.kdn.desktop.sway.prefix
              ];
              apply = builtins.filter (s: s != "");
            };
            shortName = lib.mkOption {
              readOnly = true;
              type = with lib.types; str;
              default = name;
            };
            suffix = lib.mkOption {
              type = with lib.types; str;
              default = "";
            };
            suffixes = lib.mkOption {
              type = with lib.types; listOf str;
              default = [args.config.suffix];
              apply = builtins.filter (s: s != "");
            };
            name = lib.mkOption {
              type = with lib.types; str;
              default = builtins.concatStringsSep "-" (builtins.filter (s: s != "") (
                args.config.prefixes
                ++ [
                  args.config.shortName
                ]
                ++ args.config.suffixes
              ));
            };
            units = lib.mkOption {
              type = with lib.types; listOf str;
            };
          };
        }));
      default = {
        sway.suffix = "";
        sway.units = ["service"];
        session.units = ["target"];
        envs.units = ["service" "target"];
        tray.units = ["target"];
        polkit-agent.units = ["service"];
        secrets-service.prefix = "dbus";
        secrets-service.units = ["service" "target"];
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
      default = {};
    };

    environmentDefaults = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = {};
      apply = lib.kdn.shell.makeShellDefaultAssignments;
    };

    environment = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = {};
      apply = input: lib.attrsets.mapAttrsToList lib.toShellVar input;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {kdn.desktop.sway.keys = import ./keys.nix;}
    {
      # see https://github.com/NixOS/nixpkgs/issues/354210
      #environment.systemPackages = [ (lib.meta.hiPrio pkgs.xwayland) ];
      programs.sway.extraPackages = [cfg.bundle];
    }
    {
      # Configure various Sway configs
      # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
      # see https://nixos.wiki/wiki/Sway#Systemd_integration
      programs.sway.enable = true;
      programs.sway.wrapperFeatures.gtk = true;
      programs.sway.extraOptions = ["--verbose" "--debug"];
      programs.sway.extraSessionCommands = ''
        # rename NOTIFY_SOCKET to workaround podman systemd detection
        # can be removed when NotifyAccess=all pattern is changed
        export KDN_SWAY_NOTIFY_SOCKET="''${NOTIFY_SOCKET:-}"
        test -z "$KDN_SWAY_NOTIFY_SOCKET" || unset NOTIFY_SOCKET
        if test -e /etc/profile ; then
          . /etc/profile
        fi

        # cfg.environmentDefaults
        export \
          ${lib.concatStringsSep " \\\n  " cfg.environmentDefaults}

        # cfg.environment
        export \
          ${lib.concatStringsSep " \\\n  " cfg.environment}
      '';

      services.displayManager.defaultSession = cfg.desktopSessionName;
      services.displayManager.sessionPackages = [cfg.bundle];
    }
    {
      home-manager.sharedModules = [
        {
          kdn.desktop.sway = {
            inherit (cfg) enable prefix systemd keys;
          };
          wayland.windowManager.sway = {
            inherit (config.programs.sway) package;
            systemd.enable = false;
          };
        }
      ];
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
        documentation = ["man:sway(5)"];
        bindsTo = ["graphical-session.target" config.kdn.desktop.sway.systemd.session.target];
        requires = ["graphical-session-pre.target"];
        after = ["graphical-session-pre.target"];
        before = ["graphical-session.target"];
        # We explicitly unset PATH here, as we want it to be set by
        # systemctl --user import-environment in start logic
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
          ExecStart = lib.meta.getExe config.programs.sway.package;
          ExecStopPost = cfg.bundle.exes.env-clear;
          Restart = "no";
          RestartSec = 1;
          TimeoutStopSec = 60;
          TimeoutStartSec = 300;
        };
      };

      systemd.user.targets."${config.kdn.desktop.sway.systemd.session.name}" = {
        description = config.kdn.desktop.sway.systemd.session.target;
        documentation = ["man:systemd.special(7)"];
        bindsTo = [
          "graphical-session.target"
          config.kdn.desktop.sway.systemd.sway.service
        ];
        requires = [
          "graphical-session-pre.target"
          config.kdn.desktop.sway.systemd.envs.target
          config.kdn.desktop.sway.systemd.tray.target
        ];
        before = ["graphical-session.target"];
        after = [
          "graphical-session-pre.target"
          config.kdn.desktop.sway.systemd.envs.target
          config.kdn.desktop.sway.systemd.sway.service
        ];
      };

      systemd.user.targets."${config.kdn.desktop.sway.systemd.envs.name}" = {
        description = config.kdn.desktop.sway.systemd.envs.target;
        partOf = [config.kdn.desktop.sway.systemd.session.target];
        bindsTo = [config.kdn.desktop.sway.systemd.envs.service];
        after = [config.kdn.desktop.sway.systemd.envs.service];
      };
      systemd.user.services."${config.kdn.desktop.sway.systemd.envs.name}" = {
        description = config.kdn.desktop.sway.systemd.envs.service;
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        serviceConfig.ExecStart = [
          "${cfg.bundle.exes.env-wait} --show --progress"
          "${pkgs.coreutils}/bin/sleep 2"
          "${pkgs.coreutils}/bin/echo ${config.kdn.desktop.sway.systemd.envs.service} finished executing."
        ];
      };

      systemd.user.targets."${config.kdn.desktop.sway.systemd.tray.name}" = {
        description = config.kdn.desktop.sway.systemd.tray.target;
        bindsTo = ["tray.target"];
        before = [config.kdn.desktop.sway.systemd.session.target "tray.target"];
        after = [config.kdn.desktop.sway.systemd.envs.target];
        requires = [config.kdn.desktop.sway.systemd.envs.target];
      };

      systemd.user.services."xdg-desktop-portal" = {
        requires = [config.kdn.desktop.sway.systemd.envs.target];
        after = [config.kdn.desktop.sway.systemd.envs.target];
        partOf = [config.kdn.desktop.sway.systemd.session.target];
        serviceConfig.Slice = "background.slice";
      };

      systemd.user.services."xdg-desktop-portal-gtk" = {
        requires = [config.kdn.desktop.sway.systemd.envs.target];
        after = [config.kdn.desktop.sway.systemd.envs.target];
        partOf = [config.kdn.desktop.sway.systemd.session.target];
        serviceConfig.Slice = "background.slice";
      };

      systemd.user.services."${config.kdn.desktop.sway.systemd.polkit-agent.name}" = {
        description = config.kdn.desktop.sway.systemd.polkit-agent.service;
        partOf = [config.kdn.desktop.sway.systemd.session.target];
        requires = [config.kdn.desktop.sway.systemd.envs.target];
        after = [config.kdn.desktop.sway.systemd.envs.target];
        script = cfg.polkitAgent.command;
        serviceConfig.Slice = "background.slice";
      };

      kdn.desktop.sway.initScripts.systemd = {
        "00-update-systemd-environment" = cfg.bundle.exes.env-load;
        "99-notify-systemd-service" = ''
          # use renamed NOTIFY_SOCKET to workaround podman systemd detection
          # can be removed when NotifyAccess=all pattern is changed
          NOTIFY_SOCKET="$KDN_SWAY_NOTIFY_SOCKET" ${pkgs.systemd}/bin/systemd-notify --ready
        '';
      };

      environment.etc."sway/config.d/00-${config.kdn.desktop.sway.prefix}-init.conf".text = lib.trivial.pipe cfg.initScripts [
        (lib.attrsets.mapAttrsToList (
          execName: pieces: let
            scriptName = "${config.kdn.desktop.sway.prefix}-init-${execName}";
            scriptContent = lib.trivial.pipe pieces [
              (lib.attrsets.mapAttrsToList (
                pieceName: piece: let
                  pieceScriptName = "${scriptName}-${pieceName}";
                  pieceScript = pkgs.writeScriptBin pieceScriptName piece;
                in "${pieceScript}/bin/${pieceScriptName}"
              ))
              (lib.concatStringsSep "\n")
            ];
            script = pkgs.writeScriptBin scriptName ''
              #!${pkgs.bash}/bin/bash
              set -xEeuo pipefail
              ${scriptContent}
            '';
          in "exec ${script}/bin/${scriptName}"
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
        wl-color-picker

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
    {
      services.dbus.packages = [
        (
          let
            name = lib.pipe config.kdn.desktop.sway.systemd.secrets-service.service [
              (lib.strings.removePrefix "dbus-")
              (lib.strings.removeSuffix ".service")
            ];
          in
            pkgs.writeTextFile {
              name = "${name}.service";
              destination = "/share/dbus-1/services/${name}.service";
              text = ''
                [D-BUS Service]
                Name=org.freedesktop.secrets
                Exec=${pkgs.coreutils}/bin/false
                SystemdService=${config.kdn.desktop.sway.systemd.secrets-service.service}
              '';
            }
        )
      ];
      systemd.user.targets."${config.kdn.desktop.sway.systemd.secrets-service.name}" = {
        description = config.kdn.desktop.sway.systemd.secrets-service.target;
        bindsTo = [config.kdn.desktop.sway.systemd.secrets-service.service];
        after = [config.kdn.desktop.sway.systemd.envs.target];
        requires = [config.kdn.desktop.sway.systemd.envs.target];
      };

      systemd.user.services."${config.kdn.desktop.sway.systemd.secrets-service.name}" = {
        description = config.kdn.desktop.sway.systemd.secrets-service.service;
        requires = [config.kdn.desktop.sway.systemd.envs.target];
        after = [config.kdn.desktop.sway.systemd.envs.target];
        partOf = [config.kdn.desktop.sway.systemd.session.target];
        script = lib.mkDefault "${pkgs.coreutils}/bin/sleep infinity";
        serviceConfig.Slice = "background.slice";
        serviceConfig.Type = "dbus";
        serviceConfig.BusName = "org.freedesktop.secrets";
      };
    }
    (lib.mkIf config.programs.gnupg.agent.enable {
      systemd.user.services."${config.kdn.desktop.sway.systemd.envs.name}" = {
        serviceConfig.ExecStart = lib.mkAfter [
          # stops `gpg-agent.service` after this one activates, it will be activated again by socket
          "${pkgs.systemd}/bin/systemctl stop --user gpg-agent.service"
        ];
      };
      systemd.user.services."gpg-agent" = {
        # I want to stop gpg-agent whenever `envs` target activates or deactivetes
        # starting it again should be handled by `*.socket`
        unitConfig.PartOf = [config.kdn.desktop.sway.systemd.envs.target];
        unitConfig.StopPropagatedFrom = [config.kdn.desktop.sway.systemd.envs.target];
        unitConfig.After = [config.kdn.desktop.sway.systemd.envs.target];
        serviceConfig.Slice = "background.slice";
      };
    })
  ]);
}
