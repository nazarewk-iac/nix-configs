# The Sway session core, as a den aspect. It ports five files of the old tree:
#
#   modules/universal/desktop/sway/default.nix               the NixOS session half
#   modules/universal/desktop/sway/home-manager/default.nix  the user half
#   modules/universal/desktop/sway/bundle.nix                the five session scripts
#   modules/universal/desktop/sway/keys.nix                  the key-name map
#   modules/universal/desktop/sway/remote/default.nix        the VNC extras
#
# The old modules stay in place and keep working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs one Sway session under systemd. The NixOS half turns `programs.sway` on, builds the
# session bundle, declares the six user units that order the session, registers the session with the
# display manager, and configures the XDG portal. The user half turns the Home Manager Sway module
# on and states every keybinding, every window rule and every input opinion.
#
# ## Two aspects, one file
#
# | Aspect | Classes | Contents |
# |---|---|---|
# | `desktop-sway` | `nixos`, `homeManager` | the session core |
# | `desktop-sway-remote` | `nixos` | the VNC and the pipe tools |
#
# The house style comes from ./toolset.nix, which serves 11 names from one file.
#
# ## Class list: `nixos` and `homeManager`. There is no `darwin` class.
#
# Sway is a Wayland compositor for Linux. The old NixOS half sits behind a `nixos` guard, so it has
# no darwin route at all, and every package of the user half is Linux-only. So this aspect declares
# no `darwin` target, and `denModules.desktop-sway-darwin` does not exist. An adopter who names that
# pair gets `attribute 'desktop-sway-darwin' missing`, which is the correct answer.
#
# den partitions an aspect by scope, so a den host includes this aspect **twice**: once in the host
# aspect for the `nixos` target, and once in the user aspect for the `homeManager` target.
#
# ## What the port changes
#
# 1. **`enable` goes, and the `apply` gate goes with it.** The old option carries
#    `apply = value: value && config.kdn.desktop.enable`, so a desktop flag could veto Sway. A den
#    aspect declares no reachable `enable`, so inclusion is the switch and the veto has nothing to
#    veto. ../common/graphical.nix carries the "this machine runs a graphical session" fact instead,
#    and the `nixos` target sets it.
# 2. **The Home Manager forward goes.** The old NixOS half pushes `enable`, `prefix`, `systemd` and
#    `keys` into `home-manager.sharedModules`. den has no such bridge. One `declaration` module
#    below holds every option, and both targets import it, so a user computes the same unit names
#    from the same `prefix`.
# 3. **The key map becomes a shared option.** ../common/desktop-sway.nix declares
#    `kdn.desktop-sway.keys`, and its default holds the same 13 names as the old `keys.nix`. Eight
#    aspects read that one map.
# 4. **`kdn.desktop-sway.envsTarget` gets the real name.** ../common/desktop-sway.nix defaults that
#    option to a short literal, so a leaf aspect works on its own. Both targets here override it
#    with the computed name at `lib.mkDefault`, so a leaf orders its unit after the target this
#    aspect really declares.
# 5. **Two cross-tree reads become options of this aspect.** The old user half reads
#    `config.kdn.locale.xkbLayout` and hardcodes one laptop panel name. `kdn.desktop-sway.xkbLayout`
#    holds the first, with the same `"us"` default that the `locale` aspect uses, and
#    `kdn.desktop-sway.lidOutput` holds the second. So this aspect needs no `locale` include.
# 6. **The Sway package cross-read becomes an option.** The old forward hands the NixOS
#    `programs.sway.package` to Home Manager. `kdn.desktop-sway.package` is `null` by default, so
#    each side keeps its own nixpkgs default, and a consumer that wants one package states it once.
# 7. **`lib.kdn.shell.makeShellDefaultAssignments` is inlined.** An aspect gets the consumer's plain
#    `lib`, which holds no `kdn` attribute. The three helper functions sit in `declaration` below.
# 8. **The bundle is inlined.** The old `bundle.nix` is a `callPackage` file. `mkBundle` below is the
#    same code as a plain function, so this aspect stays one file and adds no scanned `.nix` payload.
# 9. **`pkgs.kdn.sway-vnc` becomes a plain `callPackage`.** The remote aspect reaches
#    ../../../packages/sway-vnc with no overlay, the way ./zellij.nix reaches its two helpers.
# 10. **The bundle of leaves becomes `includes`.** The old user half turns kanshi, nwg-shell and
#     swaync on and imports waybar, swaylock, media-keys and swayr, so one Sway flag gave all seven.
#     `includes` below reproduces that set. **nwg-panel stays out**, because the old half sets
#     `panel.enable = false`, and an include would turn it on.
# 11. **The Linux guard replaces the parent-kind guard.** The old user half runs only under a NixOS
#     parent. den has no parent, so the `homeManager` target reads
#     `pkgs.stdenv.hostPlatform.isLinux`. That also keeps the aarch64-darwin home harness of
#     `den-eval-instantiate` evaluable.
# 12. **Two writes move to their own aspect.** The swayr configuration file now belongs to
#     `desktop-sway-swayr`, and the wofi persistence entry belongs to a `programs/` aspect. Neither
#     one appears here.
# 13. **The nwg-panel unit ordering goes.** The old half orders that unit after the session
#     environment target, inside `lib.mkIf config.services.nwg-shell.panel.enable`. The panel is off,
#     so the branch is dead. `desktop-sway-nwg-panel` owns the panel now.
# 14. **`kdn.env.packages` does not survive.** A den target names its class, so the `nixos` target
#     writes `environment.systemPackages` and the `homeManager` target writes `home.packages`.
# 15. **The NixOS `wayland.systemd.target` declaration goes.** The old NixOS half declares that
#     option itself and defaults it to the session target, then reads it back in four `partOf`
#     lines. This port names the session target in those four lines, so the value is the same and the
#     aspect declares one option less. Home Manager keeps its own `wayland.systemd.target`, which
#     home-manager declares in `modules/wayland.nix`, and the `homeManager` target below sets it.
# 16. **The GTK portal backend moves to `desktop-base`.** nixpkgs asserts
#     `xdg.portal.extraPortals != [ ]` (`<nixpkgs>/nixos/modules/config/xdg/portal.nix:134-139`), and
#     the old tree meets that assertion here, two files away from the module that turns the portal on.
#     `desktop-base` now names its own backend in `kdn.desktop-base.portals`, so this aspect adds the
#     wlroots backend alone.
#
# ## One quirk this port keeps on purpose
#
# The unit names carry the prefix **twice**: the session target is
# `kdn-sway-kdn-sway-session.target`, not `kdn-sway-session.target`. The old submodule defaults
# `prefixes` to `[ <this entry's prefix> <the aspect prefix> ]`, and both hold `"kdn-sway"`. The old
# user half proves the result, because it writes that exact doubled literal by hand
# (desktop/sway/home-manager/default.nix:331). A live machine holds those unit names, so the port
# reproduces them. Do not "fix" this without a migration.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  # The session bundle. It is `modules/universal/desktop/sway/bundle.nix`, as a plain function.
  #
  # It returns a `symlinkJoin` with two extra attributes: `passthru.providedSessions`, which the
  # display manager reads, and `exes`, which the unit definitions read.
  mkBundle =
    {
      lib,
      pkgs,
      prefix,
      serviceName,
      desktopSessionName,
    }:
    let
      scripts.start-headless = pkgs.writeShellApplication {
        name = "${prefix}-start-headless";
        text = ''
          export WLR_BACKENDS=headless
          export WLR_LIBINPUT_NO_DEVICES=1
          export XDG_SESSION_TYPE=wayland

          exec ${lib.meta.getExe scripts.start}
        '';
      };

      scripts.start = pkgs.writeShellApplication {
        name = "${prefix}-start";
        runtimeInputs = with pkgs; [ systemd ];
        text = ''
          ${lib.meta.getExe scripts.env-clear}
          ${lib.meta.getExe scripts.env-load}

          args=()
          IGNORE_ERROR=0
          ret_code=0

          while [[ $# -gt 0 ]]; do
            case "$1" in
              --ignore-error) IGNORE_ERROR=1 ; shift ;;
              *) args+=("$1") ; shift ;;
            esac
          done

          systemctl --user start ${serviceName} "''${args[@]}" || true
          systemctl --user status ${serviceName} || ret_code=$?
          test "$IGNORE_ERROR" == 0 || exit 0
          exit $ret_code
        '';
      };

      scripts.env-load = pkgs.writeShellApplication {
        name = "${prefix}-session-env-load";
        runtimeInputs = with pkgs; [
          dbus
          jq
        ];
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

      scripts.env-clear = pkgs.writeShellApplication {
        name = "${prefix}-session-env-clear";
        runtimeInputs = with pkgs; [
          dbus
          systemd
          jq
        ];
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

      scripts.env-wait = pkgs.writeShellApplication {
        name = "${prefix}-session-env-wait";
        runtimeInputs = with pkgs; [
          systemd
          jq
        ];
        text = ''
          log() {
            test "$LOG" == 1 || return 0
            echo "$@" >&2
          }

          progress() {
            test "$PROGRESS" == 1 || return 0
            echo "$@" >&2
          }

          wait_for_env() {
            until systemctl --user show-environment | grep -q "$1" ; do
              progress "$1: still waiting..."
              sleep $((RANDOM % MAXWAIT))
            done
            local cur=$SECONDS
            log "$1: loaded $((cur - last )) seconds after previous variable ($cur seconds since script start)"
            last=$SECONDS
          }

          LOG=1
          PROGRESS=0
          SHOW=0
          SLEEP=0
          while [[ $# -gt 0 ]]; do
            case $1 in
              -s|--show) SHOW=1 ; shift ;;
              --no-log) LOG=0 ; shift ;;
              -p|--progress) PROGRESS=1 ; shift ;;
              --sleep) SLEEP=$2 ; shift 2 ;;
            esac
          done

          last=0
          MAXWAIT=2

          for var in WAYLAND_DISPLAY KDN_SWAY_SYSTEMD ; do
            wait_for_env "$var"
          done

          log "found all the variables after $SECONDS seconds."
          test "$SHOW" == 0 || ${lib.meta.getExe scripts.env-show}
          sleep "$SLEEP"
          log "wait script has finished"
        '';
      };

      scripts.env-show = pkgs.writeShellApplication {
        name = "${prefix}-session-env-show";
        runtimeInputs = with pkgs; [
          systemd
          jq
        ];
        text = "systemctl --user show-environment --output=json | jq -S";
      };

      extra.desktop-entry = pkgs.writeTextFile {
        name = "${desktopSessionName}-wayland-session";
        destination = "/share/wayland-sessions/${desktopSessionName}.desktop";
        # TODO: this doesn't exit properly in SDDM
        text = ''
          [Desktop Entry]
          Name=${desktopSessionName}
          Comment=An i3-compatible Wayland compositor
          Exec=${lib.meta.getExe scripts.start} --wait --ignore-error
          Type=Application
        '';
      };
    in
    (pkgs.symlinkJoin {
      name = "${prefix}-bundle";
      passthru.providedSessions = [ desktopSessionName ];
      paths = builtins.attrValues (scripts // extra);
    })
    // {
      exes = builtins.mapAttrs (n: pkg: lib.meta.getExe pkg) scripts;
    };

  # Every option of this aspect. Both targets import this one module, so a NixOS host and a Home
  # Manager user compute the same unit names from the same prefix.
  declaration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway;

      # `lib.kdn.shell.makeShellDefaultAssignments`, inlined. An aspect gets the consumer's plain
      # `lib`, and that holds no `kdn` attribute. The escape covers a double quote and a dollar
      # sign, unlike `lib.escapeShellArg`, which covers a single quote.
      escapeShellDefaultValue =
        arg: ''"${builtins.replaceStrings [ ''"'' "$" ] [ ''\"'' "\$" ] (toString arg)}"'';
      escapeShellDefault = n: v: "\"\${${n}:-${escapeShellDefaultValue v}}\"";
      escapeShellDefaultAssignment = n: v: "${n}=${escapeShellDefault n v}";
      makeShellDefaultAssignments = lib.attrsets.mapAttrsToList escapeShellDefaultAssignment;
    in
    {
      # `keys` and `envsTarget` live in the shared file, because eight sway aspects read them.
      imports = [ ../common/desktop-sway.nix ];

      options.kdn.desktop-sway.prefix = lib.mkOption {
        type = lib.types.str;
        default = "kdn-sway";
        example = "sway";
        description = ''
          The name prefix of every unit, script and configuration file this aspect writes.

          Read the header note about the doubled prefix before you change it: the unit names hold
          this value twice.
        '';
      };

      options.kdn.desktop-sway.desktopSessionName = lib.mkOption {
        type = lib.types.str;
        default = cfg.prefix;
        defaultText = lib.literalExpression "config.kdn.desktop-sway.prefix";
        description = "The session name the display manager shows and starts.";
      };

      options.kdn.desktop-sway.package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.sway";
        description = ''
          One Sway package for both classes.

          `null` keeps the nixpkgs default of each side: `programs.sway.package` on a NixOS host and
          `wayland.windowManager.sway.package` for a Home Manager user. The old tree handed the NixOS
          value to Home Manager through a bridge that den has not got, so a consumer that needs the
          two sides equal states the package here.
        '';
      };

      options.kdn.desktop-sway.portals.debug = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Run all three XDG desktop portals with verbose logging.";
      };

      options.kdn.desktop-sway.polkitAgent.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.kdePackages.polkit-kde-agent-1;
        defaultText = lib.literalExpression "pkgs.kdePackages.polkit-kde-agent-1";
        description = "The package that holds the graphical polkit authentication agent.";
      };

      options.kdn.desktop-sway.polkitAgent.command = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.polkitAgent.package}/libexec/polkit-kde-authentication-agent-1";
        defaultText = lib.literalExpression "the agent binary of kdn.desktop-sway.polkitAgent.package";
        description = "The command that starts the polkit authentication agent.";
      };

      options.kdn.desktop-sway.bundle = lib.mkOption {
        type = lib.types.package;
        default = mkBundle {
          inherit lib pkgs;
          inherit (cfg) prefix desktopSessionName;
          serviceName = cfg.systemd.sway.service;
        };
        defaultText = lib.literalExpression "the session bundle this aspect builds";
        description = ''
          The session bundle: five shell scripts plus one Wayland session entry.

          `passthru.providedSessions` names the session for the display manager, and `exes` names
          each script path for a unit definition.
        '';
      };

      options.kdn.desktop-sway.initScripts = lib.mkOption {
        type = with lib.types; attrsOf (attrsOf str);
        default = { };
        description = ''
          Shell fragments that Sway runs at start-up, grouped by script name.

          The `nixos` target writes one `exec` line per group into
          `/etc/sway/config.d/00-<prefix>-init.conf`, and it sorts the fragments of a group by key.
        '';
      };

      options.kdn.desktop-sway.environmentDefaults = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
        apply = makeShellDefaultAssignments;
        description = ''
          Environment variables the session sets only when the value is still empty.

          The `apply` turns the set into a list of `NAME="''${NAME:-value}"` assignments.
        '';
      };

      options.kdn.desktop-sway.environment = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
        apply = input: lib.attrsets.mapAttrsToList lib.toShellVar input;
        description = ''
          Environment variables the session always sets.

          The `apply` turns the set into a list of shell assignments.
        '';
      };

      options.kdn.desktop-sway.systemd = lib.mkOption {
        type =
          with lib.types;
          attrsOf (
            submodule (
              { name, ... }@args:
              {
                options = {
                  prefix = lib.mkOption {
                    type = with lib.types; str;
                    default = cfg.prefix;
                    defaultText = lib.literalExpression "config.kdn.desktop-sway.prefix";
                    description = "The first prefix of this unit group's name.";
                  };
                  prefixes = lib.mkOption {
                    type = with lib.types; listOf str;
                    default = [
                      args.config.prefix
                      cfg.prefix
                    ];
                    defaultText = lib.literalExpression "[ this entry's prefix, the aspect prefix ]";
                    apply = builtins.filter (s: s != "");
                    description = ''
                      Every prefix of this unit group's name, in order.

                      The default holds the aspect prefix **twice**, so a name reads
                      `kdn-sway-kdn-sway-session`. The header states why the port keeps that.
                    '';
                  };
                  shortName = lib.mkOption {
                    readOnly = true;
                    type = with lib.types; str;
                    default = name;
                    description = "The attribute name of this unit group.";
                  };
                  suffix = lib.mkOption {
                    type = with lib.types; str;
                    default = "";
                    description = "The first suffix of this unit group's name.";
                  };
                  suffixes = lib.mkOption {
                    type = with lib.types; listOf str;
                    default = [ args.config.suffix ];
                    apply = builtins.filter (s: s != "");
                    description = "Every suffix of this unit group's name, in order.";
                  };
                  name = lib.mkOption {
                    type = with lib.types; str;
                    default = builtins.concatStringsSep "-" (
                      builtins.filter (s: s != "") (
                        args.config.prefixes ++ [ args.config.shortName ] ++ args.config.suffixes
                      )
                    );
                    description = "The unit name, with no unit type extension.";
                  };
                  units = lib.mkOption {
                    type = with lib.types; listOf str;
                    description = ''
                      The unit types this group declares, for example `service` or `target`.

                      The `apply` of the parent option adds one read-only attribute per entry, so
                      `units = [ "target" ]` makes `<group>.target` hold the full unit name.
                    '';
                  };
                };
              }
            )
          );
        default = {
          sway.suffix = "";
          sway.units = [ "service" ];
          session.units = [ "target" ];
          envs.units = [
            "service"
            "target"
          ];
          tray.units = [ "target" ];
          polkit-agent.units = [ "service" ];
          secrets-service.prefix = "dbus";
          secrets-service.units = [
            "service"
            "target"
          ];
        };
        apply = builtins.mapAttrs (
          key: value:
          (lib.trivial.pipe value.units [
            (map (unit: {
              name = unit;
              value = "${value.name}.${unit}";
            }))
            builtins.listToAttrs
            (attrs: attrs // value)
          ])
        );
        description = ''
          The unit-name tree of the session. One entry per unit group.

          The `apply` adds one attribute per unit type, so `systemd.envs.target` holds the full
          target name and `systemd.sway.service` holds the full service name.
        '';
      };

      options.kdn.desktop-sway.launcher = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = lib.literalExpression ''[ "''${pkgs.wofi}/bin/wofi" "--show" "drun" ]'';
        description = ''
          The application launcher command, as an argument list.

          An empty list writes no launcher keybinding. `desktop-sway-nwg-shell` supplies the drawer
          command, and this aspect includes that leaf.
        '';
      };

      options.kdn.desktop-sway.fileManager = lib.mkOption {
        type = lib.types.str;
        default = lib.getExe pkgs.nemo-with-extensions;
        defaultText = lib.literalExpression "lib.getExe pkgs.nemo-with-extensions";
        description = "The graphical file manager command.";
      };

      options.kdn.desktop-sway.lidOutput = lib.mkOption {
        type = lib.types.str;
        default = "eDP-1";
        example = "eDP-2";
        description = ''
          The output name of the built-in laptop panel.

          The session disables that output when the lid closes, and it enables the output again when
          the lid opens.
        '';
      };

      options.kdn.desktop-sway.xkbLayout = lib.mkOption {
        type = lib.types.str;
        default = "us";
        example = "pl";
        description = ''
          The keyboard layout of every Sway keyboard input.

          The default matches `kdn.locale.xkbLayout` of the `locale` aspect, so a consumer that runs
          both aspects wires `kdn.desktop-sway.xkbLayout = config.kdn.locale.xkbLayout;` and this
          aspect needs no `locale` include.
        '';
      };
    };

  # -------------------------------------------------------------------- the nixos target
  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway;
    in
    {
      imports = [
        declaration
        ../common/graphical.nix
      ];

      # TODO: figure out why exiting Sway doesn't stop/restart `sddm-helper` aka `sddm` aka `display-manager.service`
      # TODO: figure out why exiting Sway a second time cannot `systemctl restart display-manager.service`
      # TODO: figure out why exiting Sway logs out all SSH sessions
      config = lib.mkMerge [
        {
          # This machine runs a graphical session. The old tree read a desktop `enable` flag here.
          kdn.graphical = lib.mkDefault true;

          # The shared file defaults this to a short literal, so a leaf aspect works on its own.
          # The real target name carries the doubled prefix.
          kdn.desktop-sway.envsTarget = lib.mkDefault cfg.systemd.envs.target;
        }
        {
          # see https://github.com/NixOS/nixpkgs/issues/354210
          #environment.systemPackages = [ (lib.meta.hiPrio pkgs.xwayland) ];
          programs.sway.extraPackages = [ cfg.bundle ];
        }
        (lib.mkIf (cfg.package != null) { programs.sway.package = cfg.package; })
        {
          # Configure various Sway configs
          # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
          # see https://nixos.wiki/wiki/Sway#Systemd_integration
          programs.sway.enable = true;
          programs.sway.wrapperFeatures.gtk = true;
          programs.sway.extraOptions = [
            "--verbose"
            "--debug"
          ];
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
          services.displayManager.sessionPackages = [ cfg.bundle ];
        }
        {
          systemd.user.services.thunar.enable = false; # doesn't pick up proper MIME types when run as daemon

          # see https://wiki.debian.org/Wayland#Toolkits
          kdn.desktop-sway.environmentDefaults = {
            QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
            # see https://github.com/swaywm/wlroots/issues/3189#issuecomment-461608727
            WLR_NO_HARDWARE_CURSORS = "1";
          };

          kdn.desktop-sway.environment = {
            # see https://wiki.debian.org/Wayland#Toolkits

            # Note that some Electron applications (Slack, Element, Discord, etc.) or chromium (861796) may break when setting GDK_BACKEND to "wayland".
            GDK_BACKEND = "wayland"; # teams does break
            SDL_VIDEODRIVER = "wayland";
            QT_QPA_PLATFORM = "wayland;xcb";
            _JAVA_AWT_WM_NONREPARENTING = "1";
            MOZ_ENABLE_WAYLAND = "1";
            MOZ_DBUS_REMOTE = "1";
            # The old tree notes that `xdg.portal.gtkUsePortal` is deprecated, and that a global
            # `environment.sessionVariables` write has unforeseen side effects. So the value goes
            # into the session environment instead.
            GTK_USE_PORTAL = "1";
            NIXOS_OZONE_WL = "1";
          };

          systemd.user.services."${cfg.systemd.sway.name}" = {
            description = cfg.systemd.sway.service;
            documentation = [ "man:sway(5)" ];
            bindsTo = [
              "graphical-session.target"
              cfg.systemd.session.target
            ];
            requires = [ "graphical-session-pre.target" ];
            after = [ "graphical-session-pre.target" ];
            before = [ "graphical-session.target" ];
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

          systemd.user.targets."${cfg.systemd.session.name}" = {
            description = cfg.systemd.session.target;
            documentation = [ "man:systemd.special(7)" ];
            bindsTo = [
              "graphical-session.target"
              cfg.systemd.sway.service
            ];
            requires = [
              "graphical-session-pre.target"
              cfg.systemd.envs.target
              cfg.systemd.tray.target
            ];
            before = [ "graphical-session.target" ];
            after = [
              "graphical-session-pre.target"
              cfg.systemd.envs.target
              cfg.systemd.sway.service
            ];
          };

          systemd.user.targets."${cfg.systemd.envs.name}" = {
            description = cfg.systemd.envs.target;
            partOf = [ cfg.systemd.session.target ];
            bindsTo = [ cfg.systemd.envs.service ];
            after = [ cfg.systemd.envs.service ];
          };
          systemd.user.services."${cfg.systemd.envs.name}" = {
            description = cfg.systemd.envs.service;
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;
            serviceConfig.ExecStart = [
              "${cfg.bundle.exes.env-wait} --show --progress"
              "${pkgs.coreutils}/bin/sleep 2"
              "${pkgs.coreutils}/bin/echo ${cfg.systemd.envs.service} finished executing."
            ];
          };

          systemd.user.targets."${cfg.systemd.tray.name}" = {
            description = cfg.systemd.tray.target;
            bindsTo = [ "tray.target" ];
            before = [
              cfg.systemd.session.target
              "tray.target"
            ];
            after = [ cfg.systemd.envs.target ];
            requires = [ cfg.systemd.envs.target ];
          };

          systemd.user.services."xdg-desktop-portal" = {
            requires = [ cfg.systemd.envs.target ];
            after = [ cfg.systemd.envs.target ];
            partOf = [ cfg.systemd.session.target ];
            serviceConfig.Slice = "background.slice";
          };

          systemd.user.services."xdg-desktop-portal-gtk" = {
            requires = [ cfg.systemd.envs.target ];
            after = [ cfg.systemd.envs.target ];
            partOf = [ cfg.systemd.session.target ];
            serviceConfig.Slice = "background.slice";
          };

          systemd.user.services."${cfg.systemd.polkit-agent.name}" = {
            description = cfg.systemd.polkit-agent.service;
            partOf = [ cfg.systemd.session.target ];
            requires = [ cfg.systemd.envs.target ];
            after = [ cfg.systemd.envs.target ];
            script = cfg.polkitAgent.command;
            serviceConfig.Slice = "background.slice";
          };

          kdn.desktop-sway.initScripts.systemd = {
            "00-update-systemd-environment" = cfg.bundle.exes.env-load;
            "99-notify-systemd-service" = ''
              # use renamed NOTIFY_SOCKET to workaround podman systemd detection
              # can be removed when NotifyAccess=all pattern is changed
              NOTIFY_SOCKET="$KDN_SWAY_NOTIFY_SOCKET" ${pkgs.systemd}/bin/systemd-notify --ready
            '';
          };

          environment.etc."sway/config.d/00-${cfg.prefix}-init.conf".text = lib.trivial.pipe cfg.initScripts [
            (lib.attrsets.mapAttrsToList (
              execName: pieces:
              let
                scriptName = "${cfg.prefix}-init-${execName}";
                scriptContent = lib.trivial.pipe pieces [
                  (lib.attrsets.mapAttrsToList (
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
                ${pkgs.xhost}/bin/xhost si:localuser:root
              else
                ${pkgs.xhost}/bin/xhost -si:localuser:root
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

          # `desktop-base` owns `xdg.portal.enable`, `xdg.portal.xdgOpenUsePortal` and the GTK
          # backend, through its own `kdn.desktop-base.portals` option. `includes` above pulls that
          # aspect in, so this aspect adds the wlroots backend alone. A second GTK entry here would
          # duplicate the package in `extraPortals`.
          #xdg.portal.lxqt.enable = true;
          # `xdg.portal.wlr.enable` turns the portal on and adds its own backend package
          # (`<nixpkgs>/nixos/modules/config/xdg/portals/wlr.nix:57-61`).
          xdg.portal.wlr.enable = true;
          xdg.portal.wlr.settings = {
            screencast = {
              chooser_type = "dmenu";
              # https://github.com/emersion/xdg-desktop-portal-wlr/blob/1cc5ff570d745facbde4237ac96634502ec0cae6/src/screencast/wlr_screencast.c#L471-L473
              # use wofi instead
              chooser_cmd = "${pkgs.wofi}/bin/wofi -d -n --prompt='Select the monitor to share:'";
            };
          };

          # see https://github.com/NixOS/nixpkgs/blob/eb62e6aa39ea67e0b8018ba8ea077efe65807dc8/nixos/modules/programs/wayland/sway.nix#L160-L170
          xdg.portal.config.sway = {
            # Use xdg-desktop-portal-gtk for every portal interface...
            default = "gtk";
            "org.freedesktop.impl.portal.ScreenCast" = "wlr";
            "org.freedesktop.impl.portal.Screenshot" = "wlr";
            # ignore inhibit bc gtk portal always returns as success,
            # despite sway/the wlr portal not having an implementation,
            # stopping firefox from using wayland idle-inhibit
            "org.freedesktop.impl.portal.Inhibit" = "none";
          };
        }
        (lib.mkIf cfg.portals.debug {
          systemd.user.services.xdg-desktop-portal.serviceConfig.ExecStart = lib.mkForce [
            ""
            "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal --verbose"
          ];

          systemd.user.services.xdg-desktop-portal-wlr.serviceConfig.ExecStart = lib.mkForce [
            ""
            "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr --loglevel=TRACE"
          ];
          systemd.user.services.xdg-desktop-portal-gtk.serviceConfig.ExecStart = lib.mkForce [
            ""
            "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk --verbose"
          ];
        })
        {
          services.dbus.packages = [
            (
              let
                name = lib.pipe cfg.systemd.secrets-service.service [
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
                  SystemdService=${cfg.systemd.secrets-service.service}
                '';
              }
            )
          ];
          systemd.user.targets."${cfg.systemd.secrets-service.name}" = {
            description = cfg.systemd.secrets-service.target;
            bindsTo = [ cfg.systemd.secrets-service.service ];
            after = [ cfg.systemd.envs.target ];
            requires = [ cfg.systemd.envs.target ];
          };

          systemd.user.services."${cfg.systemd.secrets-service.name}" = {
            description = cfg.systemd.secrets-service.service;
            requires = [ cfg.systemd.envs.target ];
            after = [ cfg.systemd.envs.target ];
            partOf = [ cfg.systemd.session.target ];
            script = lib.mkDefault "${pkgs.coreutils}/bin/sleep infinity";
            serviceConfig.Slice = "background.slice";
            serviceConfig.Type = "dbus";
            serviceConfig.BusName = "org.freedesktop.secrets";
          };
        }
        (lib.mkIf config.programs.gnupg.agent.enable {
          systemd.user.services."${cfg.systemd.envs.name}" = {
            serviceConfig.ExecStart = lib.mkAfter [
              # stops `gpg-agent.service` after this one activates, it will be activated again by socket
              "${pkgs.systemd}/bin/systemctl stop --user gpg-agent.service"
            ];
          };
          systemd.user.services."gpg-agent" = {
            # I want to stop gpg-agent whenever `envs` target activates or deactivetes
            # starting it again should be handled by `*.socket`
            unitConfig.PartOf = [ cfg.systemd.envs.target ];
            unitConfig.StopPropagatedFrom = [ cfg.systemd.envs.target ];
            unitConfig.After = [ cfg.systemd.envs.target ];
            serviceConfig.Slice = "background.slice";
          };
        })
      ];
    };

  # -------------------------------------------------------------------- the homeManager target
  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway;

      ydotool-paste = pkgs.writeShellApplication {
        name = "ydotool-paste";
        runtimeInputs = with pkgs; [
          ydotool
          wl-clipboard
          # TODO: move it to it's own package and refactor to wait for input before starting to type
        ];
        text = ''
          sleep "''${1:-0.5}"
          wl-paste --no-newline | ydotool type --file=-
        '';
      };
    in
    {
      imports = [ declaration ];

      # Every package below is Wayland-only, and nixpkgs refuses each one on darwin. The old tree
      # reached this half through a "Home Manager under a NixOS parent" guard, and den has no parent.
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
        lib.mkMerge [
          {
            kdn.desktop-sway.envsTarget = lib.mkDefault cfg.systemd.envs.target;

            xsession.preferStatusNotifierItems = true;
            services.network-manager-applet.enable = true;
            systemd.user.services.network-manager-applet.Unit = {
              After = [ cfg.systemd.envs.target ];
              PartOf = [ cfg.systemd.session.target ];
              Requires = lib.mkForce [ cfg.systemd.envs.target ];
            };

            services.blueman-applet.enable = true;
            systemd.user.services.blueman-applet.Unit = {
              After = [
                "tray.target"
                "bluetooth.target"
                cfg.systemd.envs.target
              ];
              PartOf = [ cfg.systemd.session.target ];
              Requires = lib.mkForce [
                "tray.target"
                cfg.systemd.envs.target
              ];
            };

            # segfaults https://github.com/NixOS/nixpkgs/issues/183730
            # cliboard not working https://github.com/NixOS/nixpkgs/issues/181759
            services.flameshot.enable = true;
            services.flameshot.package = pkgs.flameshot.override { enableWlrSupport = true; };
            services.flameshot.settings = {
              General = {
                # checkForUpdates = false; # TODO: check unknown config 2024-09-19
                contrastOpacity = 188;
                copyPathAfterSave = false;
                drawColor = "#ffff00";
                filenamePattern = "screenshot-%F_%T";
                saveAfterCopy = true;
                saveAsFileExtension = "jpg";
                savePathFixed = true;
                showStartupLaunchMessage = false;
                uploadHistoryMax = 25;
                useJpgForClipboard = true;
              };
            };
            systemd.user.services.flameshot.Unit = {
              After = lib.mkForce [
                "tray.target"
                cfg.systemd.envs.target
              ];
              Requires = lib.mkForce [
                "tray.target"
                cfg.systemd.envs.target
              ];
            };

            wayland.systemd.target = lib.mkDefault cfg.systemd.session.target;

            wayland.windowManager.sway.enable = true;
            wayland.windowManager.sway.systemd.enable = false;

            wayland.windowManager.sway.extraConfig = ''
              bindswitch --reload --locked lid:on output ${cfg.lidOutput} disable
              bindswitch --reload --locked lid:off output ${cfg.lidOutput} enable

              include /etc/sway/config.d/*
            '';
          }
          (lib.mkIf (cfg.package != null) { wayland.windowManager.sway.package = cfg.package; })
          {
            wayland.windowManager.sway.config = {
              defaultWorkspace = "workspace number 1";
              keybindings =
                let
                  exec =
                    cmd:
                    let
                      cmdString = if builtins.typeOf cmd == "list" then lib.escapeShellArgs cmd else "'${cmd}'";
                    in
                    "exec ${cmdString}";
                in
                with cfg.keys;
                builtins.mapAttrs (n: lib.mkDefault) (
                  {
                    "--release ${super}+V" = exec (lib.getExe ydotool-paste); # fix using it by nix path
                    "--inhibited --release ${super}+${ctrl}+V" = exec (lib.getExe ydotool-paste); # fix using it by nix path
                    # X parity
                    "${lalt}+F4" = "kill";
                    "${ctrl}+${alt}+${delete}" = exec (lib.getExe pkgs.wlogout);
                    "${super}+E" = exec cfg.fileManager;
                    # Scratchpad:
                    #   Sway has a "scratchpad", which is a bag of holding for windows.
                    #   You can send windows there and get them back later.
                    # Move the currently focused window to the scratchpad
                    #"$Super+Shift+minus" = "move scratchpad";
                    # Show the next scratchpad window or hide the focused scratchpad window.
                    # If there are multiple scratchpad windows, this command cycles through them.
                    #"$Super+minus" = "scratchpad show";
                    "${super}+K" = exec (lib.getExe pkgs.qalculate-qt);
                    "${super}+Return" = exec "${lib.getExe pkgs.foot}";
                    "${lalt}+F2" = exec "${pkgs.wofi}/bin/wofi --show run";
                    # Kill focused window
                    "${super}+${shift}+Q" = "kill";

                    # layout stuff
                    # Switch the current container between different layout styles
                    "${super}+${ctrl}+S" = "layout stacking";
                    "${super}+${ctrl}+T" = "layout tabbed";
                    "${super}+${ctrl}+E" = "layout toggle split";

                    # Make the current focus fullscreen
                    "${super}+F" = "fullscreen";
                    # Toggle the current focus between tiling and floating mode
                    "${super}+${shift}+F" = "floating toggle";
                    "${super}+${shift}+S" = "sticky toggle";

                    # mode switching
                    "${super}+R" = "mode resize";
                    "${super}+Pause" = "mode passthrough";
                    "${super}+Scroll_Lock" = "mode passthrough";

                    # moving around
                    "${super}+A" = "focus parent";
                    "${super}+Left" = "focus left";
                    "${super}+Down" = "focus down";
                    "${super}+Up" = "focus up";
                    "${super}+Right" = "focus right";
                    "--border --whole-window ${super}+${mouse-up}" = "focus right";
                    "--border --whole-window ${super}+${mouse-down}" = "focus left";
                    "--border --whole-window ${super}+${shift}+${mouse-up}" = "focus next sibling";
                    "--border --whole-window ${super}+${shift}+${mouse-down}" = "focus prev sibling";

                    "${super}+${shift}+Left" = "move left";
                    "${super}+${shift}+Down" = "move down";
                    "${super}+${shift}+Up" = "move up";
                    "${super}+${shift}+Right" = "move right";

                    "${super}+${shift}+${ctrl}+Left" = "move workspace to output left";
                    "${super}+${shift}+${ctrl}+Down" = "move workspace to output down";
                    "${super}+${shift}+${ctrl}+Up" = "move workspace to output up";
                    "${super}+${shift}+${ctrl}+Right" = "move workspace to output right";

                    # workspaces
                    "${super}+1" = "workspace number 1";
                    "${super}+2" = "workspace number 2";
                    "${super}+3" = "workspace number 3";
                    "${super}+4" = "workspace number 4";
                    "${super}+5" = "workspace number 5";
                    "${super}+6" = "workspace number 6";
                    "${super}+7" = "workspace number 7";
                    "${super}+8" = "workspace number 8";
                    "${super}+9" = "workspace number 9";
                    "${super}+0" = "workspace number 10";

                    "${super}+${shift}+1" = "move container to workspace number 1";
                    "${super}+${shift}+2" = "move container to workspace number 2";
                    "${super}+${shift}+3" = "move container to workspace number 3";
                    "${super}+${shift}+4" = "move container to workspace number 4";
                    "${super}+${shift}+5" = "move container to workspace number 5";
                    "${super}+${shift}+6" = "move container to workspace number 6";
                    "${super}+${shift}+7" = "move container to workspace number 7";
                    "${super}+${shift}+8" = "move container to workspace number 8";
                    "${super}+${shift}+9" = "move container to workspace number 9";
                    "${super}+${shift}+0" = "move container to workspace number 10";
                  }
                  # An empty launcher list writes no binding, so a consumer that excludes every
                  # launcher aspect still evaluates.
                  // lib.optionalAttrs (cfg.launcher != [ ]) {
                    # Launchers
                    "${super}+D" = exec cfg.launcher;
                  }
                );

              modes.passthrough = with cfg.keys; {
                "${super}+Pause" = "mode default";
                "${super}+Scroll_Lock" = "mode default";
              };

              modes.resize = with cfg.keys; {
                "${super}+${ctrl}+Left" = "resize shrink width 1";
                "${super}+${ctrl}+Down" = "resize grow height 1";
                "${super}+${ctrl}+Up" = "resize shrink height 1";
                "${super}+${ctrl}+Right" = "resize grow width 1";

                "${ctrl}+Left" = "resize shrink width 5";
                "${ctrl}+Down" = "resize grow height 5";
                "${ctrl}+Up" = "resize shrink height 5";
                "${ctrl}+Right" = "resize grow width 5";

                "Left" = "resize shrink width 15";
                "Down" = "resize grow height 15";
                "Up" = "resize shrink height 15";
                "Right" = "resize grow width 15";

                "${lalt}+Left" = "resize shrink width 50";
                "${lalt}+Down" = "resize grow height 50";
                "${lalt}+Up" = "resize shrink height 50";
                "${lalt}+Right" = "resize grow width 50";

                "${super}+${lalt}+Left" = "resize shrink width 100";
                "${super}+${lalt}+Down" = "resize grow height 100";
                "${super}+${lalt}+Up" = "resize shrink height 100";
                "${super}+${lalt}+Right" = "resize grow width 100";

                # Return to default mode
                "Return" = "mode default";
                "Escape" = "mode default";
              };
              bars = [ ];
              focus.followMouse = false;
              floating.modifier = "${cfg.keys.super} normal";
              workspaceLayout = "tabbed";
              workspaceAutoBackAndForth = true;
              input."type:touchpad" = {
                tap = "enabled";
                natural_scroll = "enabled";
              };
              input."type:keyboard" = {
                xkb_layout = cfg.xkbLayout;
                # https://major.io/2022/05/24/sway-reload-causes-a-firefox-crash/
                # xkb_numlock = "enable";
                repeat_delay = "333";
                repeat_rate = "50";
              };

              floating = {
                border = 0;
                criteria = [
                  { app_id = "org.kde.polkit-kde-authentication-agent-1"; }
                  { app_id = "pinentry-qt"; }
                  {
                    app_id = "firefox";
                    title = "Picture-in-Picture";
                  }
                  {
                    app_id = "firefox";
                    title = "Firefox — Sharing Indicator";
                  }
                ];
              };

              window.commands =
                let
                  modal = [
                    "border none"
                    "floating enable"
                    "sticky enable"
                  ];
                  centerModal = modal ++ [
                    "move position center"
                  ];
                  entries = [
                    {
                      criteria = {
                        app_id = "firefox";
                        title = "Firefox — Sharing Indicator";
                      };
                      commands = [ "resize set 10px 30px" ];
                    }
                    {
                      criteria = {
                        title = "File Operation Progress";
                      };
                      commands = centerModal;
                    }
                  ];
                  expandEntry =
                    entry:
                    map (command: {
                      inherit (entry) criteria;
                      inherit command;
                    }) entry.commands;
                in
                lib.lists.flatten (map expandEntry entries);

              startup = [
                { command = lib.getExe pkgs.sway-assign-cgroups; }
              ];
            };

            home.packages = with pkgs; [
              ydotool-paste

              qalculate-qt
              libqalculate
            ];

            # `desktop-sway-kanshi` runs the daemon; this aspect states which target starts it.
            services.kanshi.systemdTarget = lib.mkDefault cfg.systemd.session.target;
          }
          {
            # `desktop-sway-nwg-shell` supplies the drawer. The old tree read the same two values
            # across the module boundary; here the two aspects load together through `includes`.
            kdn.desktop-sway-nwg-shell.drawer.opts.fm = lib.mkDefault cfg.fileManager;
            kdn.desktop-sway.launcher = lib.mkDefault [ config.kdn.desktop-sway-nwg-shell.drawer.exec ];
          }
          {
            /*
              wlroots crash fix
                see https://github.com/wez/wezterm/issues/6270#issuecomment-2408627063
            */
            programs.wezterm.extraConfig = "";
          }
        ]
      );
    };

  # -------------------------------------------------------------------- desktop-sway-remote
  remoteNixosTarget =
    {
      lib,
      pkgs,
      ...
    }:
    {
      # Multi-output directions:
      # - https://www.reddit.com/r/swaywm/comments/k1zl41/thank_you_devs_free_ipad_repurposed_as_a_second/
      # - https://github.com/swaywm/sway/issues/5553
      # - https://wiki.archlinux.org/title/Sway#Create_headless_outputs
      environment.systemPackages = [
        pkgs.wayvnc
        pkgs.waypipe

        (pkgs.callPackage ../../../packages/sway-vnc { })

        pkgs.remmina # cannot type $ (dollar sign)
        pkgs.tigervnc # vncviewer over a headless output
        # realvnc-vnc-viewer  # doesn't pass/locks up on left alt key combinations
        # turbovnc  # Algorithm negotiation fails
      ];
    };
in
{
  # The old user half turns kanshi, nwg-shell and swaync on, and it imports waybar, swaylock,
  # media-keys and swayr. So one Sway flag gave all seven leaves. `includes` reproduces that set.
  # `desktop-sway-nwg-panel` stays out on purpose: the old half sets the panel off.
  kdn.desktop-sway.includes = [
    kdn.desktop-base
    kdn.desktop-sway-kanshi
    kdn.desktop-sway-media-keys
    kdn.desktop-sway-nwg-shell
    kdn.desktop-sway-swaylock
    kdn.desktop-sway-swaync
    kdn.desktop-sway-swayr
    kdn.desktop-sway-waybar
  ];
  kdn.desktop-sway.nixos = nixosTarget;
  kdn.desktop-sway.homeManager = homeTarget;

  # The old `sway/remote` module defaults the Sway flag on, so the include is the same statement.
  # It also carries **no** `apply` gate, unlike its four desktop siblings, so the old tree can
  # install these tools on a machine that runs no Sway at all. The include closes that hole.
  kdn.desktop-sway-remote.includes = [ kdn.desktop-sway ];
  kdn.desktop-sway-remote.nixos = remoteNixosTarget;
}
