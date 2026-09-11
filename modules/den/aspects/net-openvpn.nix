# The OpenVPN wrapper of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/openvpn/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs any number of OpenVPN 2 instances from a per-instance directory under
# `/etc/kdn/openvpn/<instance>`. Each instance keeps its certificate and its `config.ovpn` there, and
# the service reads them from that working directory. It also turns `openvpn3` on, and it puts a
# `kdn-openvpn-setup` command on the path. That command moves a downloaded profile into the
# per-instance directory, names the instance, and locks the directory down to root.
#
# It renders four things per instance:
#
#   * a `services.openvpn.servers.<instance>` entry with the generated config, the `up` script and
#     the `down` script;
#   * a `systemd.services.openvpn-<instance>` entry that sets the working directory;
#   * an optional route handler, for an instance that takes over the routes itself;
#   * an optional debug hook that appends one JSON line per OpenVPN event.
#
# ## The route handler
#
# `routes.ignore` adds `route-noexec`, so OpenVPN pushes no route itself. The generated `route-up`
# script then walks the `route_network_<n>` variables OpenVPN exports, and it adds each route with
# `ip route add`. The `down` script removes them again. This lets an instance keep a route out of the
# main table.
#
# ## The debug hook
#
# `debug` writes one JSON line per event to `/tmp/openvpn/<instance>/started-at-<date>.jsonl`. Each
# line holds the date, the positional arguments and the whole environment. It is a diagnostic tool:
# the environment of an OpenVPN hook holds the pushed options, and no other source shows them.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module puts the `kdn-openvpn-setup` package outside its context guard, so the command
# reaches a Darwin host and a Home Manager user too. Every service effect stays in the `nixos`
# target, exactly as the old guard states.
#
# ## What the port changes
#
# 1. **`enable` goes, and the data is the switch for the instances.** `instances` defaults to an
#    empty set, so an adopter that names none gets no service and no unit. `programs.openvpn3` and
#    the setup command stay unconditional, because they are the point of the inclusion.
# 2. **`debug` stays a plain flag.** It is not an `enable` for this aspect, and it stays `false`.
# 3. **The setup script loses the `lib.kdn` helper — the drop-in part.** The old module builds the
#    command with `lib.kdn.shell.writeShellScript`, and `lib.kdn` needs this repository's own
#    library. A plain consumer has no such library. So this aspect calls
#    `pkgs.writeShellApplication` itself, and it strips the shebang line and the `set -eEuo pipefail`
#    line first — the same two lines the helper strips. A mid-file shebang would reach shellcheck in
#    the check phase.
# 4. **The `openvpn3` patch becomes an option.** The old module always adds an overlay that patches
#    `openvpn3`, because an `#include` is missing in one nixpkgs revision and the test build fails.
#    An overlay makes the consumer evaluate nixpkgs a second time, and a fixed nixpkgs needs no
#    patch. So the port declares `kdn.networking.openvpn.patchOpenvpn3`, and it keeps `true` as the
#    default. See https://github.com/NixOS/nixpkgs/issues/349012
# 5. **The package goes through the native option per class.** ../common/filter-packages.nix drops a
#    package the platform cannot build, and it warns.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The per-instance `enable` flag sits inside an
#    `attrsOf submodule`, so the option walk cannot reach it.
# 3. **No custom module argument.** Each target module takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # It repeats the two strips of the repository's own shell helper, so a plain consumer needs no
  # extra library.
  setupScript =
    pkgs:
    let
      dropFirst = line: lines: if (builtins.head lines) == line then (builtins.tail lines) else lines;
    in
    pkgs.writeShellApplication {
      name = "kdn-openvpn-setup";
      runtimeInputs = with pkgs; [ xkcdpass ];
      text = pkgs.lib.trivial.pipe ./net-openvpn/kdn-openvpn-setup.sh [
        builtins.readFile
        (pkgs.lib.strings.splitString "\n")
        (dropFirst "#!/usr/bin/env bash")
        (dropFirst "set -eEuo pipefail")
        (dropFirst "")
        (builtins.concatStringsSep "\n")
      ];
    };

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } [ (setupScript pkgs) ];

  declaration =
    { lib, ... }:
    {
      options.kdn.networking.openvpn.debug = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Append one JSON line per OpenVPN event to `/tmp/openvpn/<instance>/started-at-<date>.jsonl`.
          Each line holds the date, the arguments and the whole environment of the hook.
        '';
      };

      options.kdn.networking.openvpn.patchOpenvpn3 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Add an overlay that patches `openvpn3` with an extra `#include`. Without it the unit test
          build fails on some nixpkgs revisions. See
          https://github.com/NixOS/nixpkgs/issues/349012

          Turn it off on a nixpkgs that already carries the fix. An overlay makes the consumer
          evaluate nixpkgs a second time, so the flag also saves evaluation time.
        '';
      };

      options.kdn.networking.openvpn.instances = lib.mkOption {
        default = { };
        description = ''
          One entry per OpenVPN 2 instance. Each instance reads its own `config.ovpn` from
          `/etc/kdn/openvpn/<instance>`, so put the profile there with `kdn-openvpn-setup`.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Run this instance's service. The config file renders either way.";
            };
            options.debug = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Turn the JSON debug hook on for this instance alone.";
            };
            options.config = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = "Extra OpenVPN directives. They follow the `config config.ovpn` line.";
            };
            options.routes.ignore = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = true;
              description = ''
                Add `route-noexec`, so OpenVPN installs no pushed route. The generated `route-up`
                script then installs each pushed route itself, and the `down` script removes it.
              '';
            };
            options.routes.add = lib.mkOption {
              default = [ ];
              description = "Extra static routes. Each entry renders one `route` directive.";
              type = lib.types.listOf (
                lib.types.submodule {
                  options.network = lib.mkOption {
                    type = lib.types.str;
                    example = "192.0.2.0";
                    description = "The network address of this route.";
                  };
                  options.netmask = lib.mkOption {
                    type = lib.types.str;
                    default = "255.255.255.0";
                    description = "The netmask of this route.";
                  };
                }
              );
            };
            options.scripts =
              let
                opt = description: {
                  type = lib.types.lines;
                  default = "";
                  inherit description;
                };
              in
              {
                up = lib.mkOption (opt "Extra shell lines for the OpenVPN `up` hook.");
                tls-verify = lib.mkOption (opt "Extra shell lines for the OpenVPN `tls-verify` hook.");
                ipchange = lib.mkOption (opt "Extra shell lines for the OpenVPN `ipchange` hook.");
                route-up = lib.mkOption (opt "Extra shell lines for the OpenVPN `route-up` hook.");
                route-pre-down = lib.mkOption (opt "Extra shell lines for the OpenVPN `route-pre-down` hook.");
                down = lib.mkOption (opt "Extra shell lines for the OpenVPN `down` hook.");
              };
          }
        );
      };
    };
in
{
  kdn.net-openvpn.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.networking.openvpn;

      mkOpenVPNConfig =
        instance: instanceConfig:
        let
          joinNonEmpty =
            entries:
            lib.trivial.pipe entries [
              lib.lists.flatten
              (builtins.filter (v: v != ""))
              (builtins.concatStringsSep "\n")
            ];

          debugScript =
            let
              script = pkgs.writeShellScript "openvpn-debug-info" ''
                directory="/tmp/openvpn/''${PWD##*/}"
                shift
                date="$(${pkgs.coreutils}/bin/date --utc --date="@$daemon_start_time" +'%Y%m%d-%H%M%S')"
                output="$directory/started-at-$date.jsonl"
                ${pkgs.coreutils}/bin/mkdir -p "''${output%/*}"
                ${pkgs.jq}/bin/jq -cn '{
                  date: (now|todateiso8601),
                  argv: $ARGS.positional,
                  env: env,
                }' --args -- "$@" >> "$output"
              '';
            in
            lib.optionalString (cfg.debug || instanceConfig.debug) "${script}";

          mkOptionalScript =
            type: txt:
            let
              content = joinNonEmpty [
                instanceConfig.scripts."${type}"
                txt
              ];
              line = "${type} ${pkgs.writeShellScript "openvpn-${instance}-${type}" content}";
            in
            lib.optionalString (content != "") line;

          routes_handler =
            name: command:
            let
              resolveVar = name: required: ''
                var="${name}_$idx"
                var="''${!var:-}"
                ${lib.optionalString required ''[ -n "$var" ] || return 0''}
                local ${name}="$var"
              '';
            in
            ''
              ${name}() {
                local idx="$1"
                local var

                ${resolveVar "route_network" true}
                ${resolveVar "route_netmask" true}
                ${resolveVar "route_gateway" false}

                echo "${command}" >&2
                ${command}
                "${name}" "$((idx + 1))" || return 1
              }
              "${name}" 1
            '';
        in
        {
          config = ''
            # already running in /etc/kdn/openvpn/${instance}
            config config.ovpn
            ${instanceConfig.config}
            ${lib.optionalString instanceConfig.routes.ignore "route-noexec"}
            ${joinNonEmpty (map (route: "route ${route.network} ${route.netmask}") instanceConfig.routes.add)}
            # up handled by the nixpkgs module
            ${mkOptionalScript "tls-verify" [
              debugScript
            ]}
            ${mkOptionalScript "ipchange" [
              debugScript
            ]}
            ${mkOptionalScript "route-up" [
              (lib.optional instanceConfig.routes.ignore (
                routes_handler "add-routes" ''${pkgs.iproute2}/bin/ip route add "$route_network/$route_netmask" via "$route_gateway" dev "$dev"''
              ))
              debugScript
            ]}
            ${mkOptionalScript "route-pre-down" [
              debugScript
            ]}
            # down handled by the nixpkgs module
          '';
          up = joinNonEmpty [
            instanceConfig.scripts.up
            debugScript
          ];
          down = joinNonEmpty [
            instanceConfig.scripts.down
            (lib.optional instanceConfig.routes.ignore (
              routes_handler "del-routes" ''${pkgs.iproute2}/bin/ip route del "$route_network/$route_netmask" via "$route_gateway" dev "$dev"''
            ))
            debugScript
          ];
          autoStart = lib.mkDefault false;
        };

      mkServiceConfig =
        instance: instanceConfig:
        lib.nameValuePair "openvpn-${instance}" {
          inherit (instanceConfig) enable;
          serviceConfig.WorkingDirectory = "/etc/kdn/openvpn/${instance}";
        };
    in
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          environment.systemPackages = filtered lib pkgs;
          programs.openvpn3.enable = true;

          services.openvpn.servers = lib.attrsets.mapAttrs mkOpenVPNConfig cfg.instances;
          systemd.services = lib.attrsets.mapAttrs' mkServiceConfig cfg.instances;
        }
        (lib.mkIf cfg.patchOpenvpn3 {
          nixpkgs.overlays = [
            (final: prev: {
              # see https://github.com/NixOS/nixpkgs/issues/349012#issuecomment-2424719649
              openvpn3 = prev.openvpn3.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [
                  ./net-openvpn/fix-tests.patch
                ];
              });
            })
          ];
        })
      ];
    };

  kdn.net-openvpn.darwin =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];
      config.environment.systemPackages = filtered lib pkgs;
    };

  kdn.net-openvpn.homeManager =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];
      config.home.packages = filtered lib pkgs;
    };
}
