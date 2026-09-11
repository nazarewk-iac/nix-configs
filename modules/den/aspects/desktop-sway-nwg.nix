# The nwg-shell family, as two den aspects. It ports `desktop/sway/home-manager/nwg-shell` and its
# `nwg-panel` sub-module.
#
# The old modules stay in place and keep working. This file is the parallel den implementation.
#
# ## Two aspects, one file
#
#   * `desktop-sway-nwg-shell` — the eight small nwg programs: the bar, the display editor, the dock,
#     the application drawer, the welcome window, the look editor, the menu and the wrapper.
#   * `desktop-sway-nwg-panel` — the nwg-panel status bar, its JSON configuration and its user
#     service.
#
# One file serves both, because they come from one upstream project family and from one source
# directory. A reader who changes one usually reads the other. `../lib.nix` maps both names to this
# file, as it already does for the `fs-*` and the `toolset-*` names.
#
# ## Class list: `homeManager`
#
# Every nwg program runs in the user session, and every option below is a Home Manager option. So
# each aspect holds one target.
#
# ## What the port changes
#
# 1. **Inclusion replaces two `enable` flags.** The old modules key on the sway `enable` flag, and
#    the panel keys on the shell flag as well. A den aspect has no `enable`, so the aspect list
#    carries both choices. **The panel is a separate aspect for that reason**: the old tree turns the
#    panel off on every host with the note "it seems to often hang up", and in den you get the same
#    result when you leave the panel aspect out of the list.
# 2. **The options move under `kdn`.** The old modules declare `services.nwg-shell*`, outside the
#    `kdn` prefix. The one enforced aspect rule walks the `kdn` attribute only, so an option outside
#    it is invisible to the check. Both aspects now declare under `kdn.<aspect name>`.
# 3. **The eight components become one `attrsOf submodule`.** The old module declares eight fixed
#    option sets, each one with its own `enable`. A fixed `enable` at a reachable path breaks the
#    aspect rule; an `enable` inside an `attrsOf submodule` does not, because the option walk stops
#    at the `components` option itself. The eight names come from a `config` definition, not from the
#    option `default`, so a consumer that disables one component keeps the other seven.
# 4. **The internal helper option goes.** The old module publishes its component factory through a
#    `readOnly`, `internal` option and reads it back. `mkComponent` is a plain `let` binding here.
# 5. **The panel style assignment goes.** The old module reads a CSS file **out of the built
#    package**, so the evaluation has to build nwg-panel first. Nothing reads the value back:
#    measured 2026-09-11 with a grep of the whole tree. The option stays, with an empty default, so a
#    consumer can still state a style.
# 6. **The native option replaces the cross-platform package list.** Every package goes to
#    `home.packages`, through ../common/filter-packages.nix.
# 7. **A platform guard replaces the parent-kind guard.** The old modules emit their config only
#    under a NixOS parent. den has no such guard, so each target reads
#    `pkgs.stdenv.hostPlatform.isLinux`. Every nwg program is a Wayland program, and nixpkgs refuses
#    each one on `aarch64-darwin`. Measured 2026-09-11.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 and change 3 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The eight small nwg programs. The name doubles as the package name: `bar` names `pkgs.nwg-bar`.
  shellComponents = [
    "bar"
    "displays"
    "dock"
    "drawer"
    "hello"
    "look"
    "menu"
    "wrapper"
  ];

  # One component: a switch and a package. The submodule reads its own attribute name, so the package
  # default needs no repeat of the name.
  mkComponentType =
    { lib, pkgs }:
    lib.types.submodule (
      { name, ... }:
      {
        options.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = ''
            Install this component. A component of the family is small, so all of them are on by
            default.
          '';
        };

        options.package = lib.mkOption {
          type = lib.types.package;
          default = pkgs."nwg-${name}";
          defaultText = lib.literalExpression ''pkgs."nwg-''${name}"'';
          description = ''
            The package of this component. The default follows the attribute name.
          '';
        };
      }
    );

  # The panel configuration arrives as a JSON list, and a list merges badly: a consumer cannot change
  # one entry of it. So the read turns the list into an attribute set, by panel name, and it adds two
  # keys — `order` keeps the original sequence, and `enable` lets a consumer drop one panel.
  panelConfigToNix =
    { lib }:
    output:
    lib.pipe output [
      (lib.lists.imap0 (
        idx: panel:
        lib.nameValuePair panel.name (
          panel
          // {
            order = lib.mkDefault (idx * 100);
            enable = lib.mkDefault true;
          }
        )
      ))
      builtins.listToAttrs
    ];

  # The write turns the attribute set back into the list nwg-panel reads. It drops a disabled panel,
  # it sorts by `order`, and it removes the two keys nwg-panel does not know.
  panelConfigToJSON =
    { lib }:
    input:
    lib.pipe input [
      builtins.attrValues
      (builtins.filter (panel: panel.enable or true))
      (builtins.sort (a: b: builtins.lessThan a.order b.order))
      (map (
        panel:
        builtins.removeAttrs panel [
          "enable"
          "order"
        ]
      ))
    ];

  shellHomeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway-nwg-shell;
      swayCfg = config.kdn.desktop-sway;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [
        ../common/desktop-sway.nix
        ../common/persist.nix
      ];

      options.kdn.desktop-sway-nwg-shell.components = lib.mkOption {
        type = lib.types.attrsOf (mkComponentType {
          inherit lib pkgs;
        });
        default = { };
        example = lib.literalExpression ''
          {
            dock.enable = false;
          }
        '';
        description = ''
          The nwg-shell components, by short name. The `config` of this aspect names all eight of
          them, so a definition here changes one component and keeps the others.
        '';
      };

      options.kdn.desktop-sway-nwg-shell.drawer.opts = lib.mkOption {
        type =
          with lib.types;
          attrsOf (oneOf [
            str
            true
          ]);
        default = { };
        example = {
          fm = "nemo";
        };
        description = ''
          The command-line options of nwg-drawer, by name. A `true` value gives a flag with no value.
          See https://github.com/nwg-piotr/nwg-drawer

          The drawer needs two values that no other component needs, so they sit next to
          `components` instead of inside it.
        '';
        apply =
          opts:
          lib.pipe opts [
            (lib.attrsets.mapAttrsToList (
              name: value: [ "-${name}" ] ++ lib.optional (builtins.typeOf value == "string") value
            ))
            lib.lists.flatten
          ];
      };

      options.kdn.desktop-sway-nwg-shell.drawer.exec = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = toString (
          pkgs.writeScript "nwg-drawer-launch" ''
            ${lib.getExe cfg.components.drawer.package} ${builtins.concatStringsSep " " cfg.drawer.opts}
          ''
        );
        defaultText = lib.literalMD "a script that starts nwg-drawer with `opts`";
        description = ''
          The path of a script that starts the drawer with the options above. A sway keybinding reads
          it.
        '';
      };

      config = lib.mkMerge [
        # The eight names live here, not in the option default. See change 3 in the header.
        { kdn.desktop-sway-nwg-shell.components = lib.genAttrs shellComponents (_: { }); }

        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
          lib.mkMerge [
            {
              # The family expects one notification daemon, and swaync is the one it works with. The
              # `desktop-sway-swaync` aspect adds the keybinding and the D-Bus service file.
              services.swaync.enable = true;

              home.packages = filterPackages (
                lib.pipe cfg.components [
                  (lib.filterAttrs (_: component: component.enable))
                  builtins.attrValues
                  (map (component: component.package))
                ]
              );

              kdn.desktop-sway-nwg-shell.drawer.opts.wm = ''"$XDG_CURRENT_DESKTOP"'';
            }
            {
              # nwg-drawer pins
              kdn.disks.persist."usr/config".files =
                lib.optional cfg.components.drawer.enable ".cache/nwg-pin-cache";
            }
            (lib.mkIf cfg.components.displays.enable {
              wayland.windowManager.sway.extraConfig = ''
                include ~/.config/sway/outputs
                include ~/.config/sway/workspaces
              '';
              kdn.disks.persist."usr/config".files = [
                ".config/nwg-displays/config"
                ".config/sway/outputs"
                ".config/sway/workspaces"
              ];
              wayland.windowManager.sway.config.keybindings = {
                "${swayCfg.keys.super}+P" = "exec ${lib.getExe cfg.components.displays.package}";
              };
            })
          ]
        ))
      ];
    };

  panelHomeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway-nwg-panel;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.desktop-sway-nwg-panel.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.nwg-panel;
        defaultText = lib.literalExpression "pkgs.nwg-panel";
        description = "The nwg-panel package.";
      };

      options.kdn.desktop-sway-nwg-panel.config = lib.mkOption {
        type = (pkgs.formats.json { }).type;
        default = { };
        example = lib.literalExpression ''
          {
            panel-top.enable = false;
          }
        '';
        description = ''
          The panels, by name. Each entry takes an `order` and an `enable` key on top of the keys
          nwg-panel knows. The `apply` sorts the entries by `order`, it drops a disabled entry, and
          it returns the list nwg-panel reads.
        '';
        apply = panelConfigToJSON { inherit lib; };
      };

      options.kdn.desktop-sway-nwg-panel.style = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          The CSS of the panel.

          The old module fills this from a file inside the built package, and nothing reads the value
          back. That read forces a build during the evaluation, so this port drops it. See change 5
          in the header.
        '';
      };

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
        lib.mkMerge [
          {
            kdn.desktop-sway-nwg-panel.config = lib.pipe ./desktop-sway-nwg/nwg-panel-config.json [
              builtins.readFile
              builtins.fromJSON
              (panelConfigToNix { inherit lib; })
            ];
          }
          {
            home.packages = filterPackages (
              [ cfg.package ]
              ++ (with pkgs; [
                # gopsuinfo serves the executor modules of the panel.
                # TODO: the tray icon of an electron program is missing.
                #   See https://github.com/nwg-piotr/nwg-panel/issues/224
                gopsuinfo
              ])
            );

            kdn.desktop-sway-nwg-panel.config.panel-top.output = lib.mkForce "All";
            kdn.desktop-sway-nwg-panel.config.panel-bottom.output = lib.mkForce "All";

            systemd.user.services.nwg-panel = {
              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
              Unit = {
                Description = "nwg-panel: GTK3-based panel for sway window manager";
                Documentation = "https://github.com/nwg-piotr/nwg-panel";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session-pre.target" ];
                ConditionEnvironment = "WAYLAND_DISPLAY";
              };
              Service = {
                Type = "simple";
                # nwg-panel writes its own configuration file at run time, so the file cannot be a
                # symlink into the store. This step compares the live file with the managed one and
                # replaces it when the two differ.
                ExecStartPre = lib.getExe (
                  pkgs.writeShellApplication {
                    name = "nwg-panel-set-configs";
                    runtimeInputs = with pkgs; [
                      diffutils
                      jq
                    ];
                    runtimeEnv.config_path = "${config.xdg.configHome}/nwg-panel/config";
                    runtimeEnv.calendar_path = "${config.xdg.configHome}/nwg-panel/calendar.json";
                    runtimeEnv.managed_config_path = pkgs.runCommand "nwg-panel.config.json" {
                      # see https://github.com/NixOS/nixpkgs/blob/92678837b311e85ab8d9f94bf6755c6ecb0f569f/pkgs/pkgs-lib/formats.nix#L64-L70
                      nativeBuildInputs = with pkgs; [ jq ];
                      value = builtins.toJSON cfg.config;
                      passAsFile = [ "value" ];
                    } ''jq -S . "$valuePath"> $out'';
                    text = ''
                      tempdir="$(mktemp -d /tmp/nwg-panel-set-configs.XXXXXX)"
                      trap 'rm -rf "$tempdir" || :' EXIT
                      mkdir -p "$tempdir"
                      test -e "$calendar_path" || jq -n '{}' >"$calendar_path"
                      if test -e "$config_path" ; then
                        jq -S '.' "$config_path" > "$tempdir/config.json"
                      else
                        jq -n '{}' >"$config_path"
                      fi
                      if ! diff "$managed_config_path" "$tempdir/config.json" ; then
                        echo "current config has changed, replacing with managed"
                        cp "$managed_config_path" "$config_path"
                      fi
                      rm -r "$tempdir"
                    '';
                  }
                );
                ExecStart = lib.getExe cfg.package;
                Restart = "on-failure";
              };
            };
          }
        ]
      );
    };
in
{
  kdn.desktop-sway-nwg-shell.homeManager = shellHomeTarget;
  kdn.desktop-sway-nwg-panel.homeManager = panelHomeTarget;
}
