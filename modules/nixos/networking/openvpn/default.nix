{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.networking.openvpn;

  mkOpenVPNConfig = instance: instanceConfig: let
    joinNonEmpty = entries:
      lib.trivial.pipe entries [
        lib.lists.flatten
        (builtins.filter (v: v != ""))
        (builtins.concatStringsSep "\n")
      ];

    debugScript = let
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

    mkOptionalScript = type: txt: let
      content = joinNonEmpty [instanceConfig.scripts."${type}" txt];
      line = "${type} ${pkgs.writeShellScript "openvpn-${instance}-${type}" content}";
    in
      lib.optionalString (content != "") line;

    routes_handler = name: command: let
      resolveVar = name: required: ''
        var="${name}_$idx"
        var="''${!var:-}"
        ${lib.optionalString required ''[ -n "$var" ] || return 0''}
        local ${name}="$var"
      '';
    in ''
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
  in {
    config = ''
      # already running in /etc/kdn/openvpn/${instance}
      config config.ovpn
      ${instanceConfig.config}
      ${lib.optionalString instanceConfig.routes.ignore "route-noexec"}
      ${joinNonEmpty (builtins.map (route: "route ${route.network} ${route.netmask}") instanceConfig.routes.add)}
      # up handled by NixOS module
      ${mkOptionalScript "tls-verify" [
        debugScript
      ]}
      ${mkOptionalScript "ipchange" [
        debugScript
      ]}
      ${mkOptionalScript "route-up" [
        (lib.optional instanceConfig.routes.ignore (routes_handler "add-routes" ''${pkgs.iproute2}/bin/ip route add "$route_network/$route_netmask" via "$route_gateway" dev "$dev"''))
        debugScript
      ]}
      ${mkOptionalScript "route-pre-down" [
        debugScript
      ]}
      # down handled by NixOS module
    '';
    up = joinNonEmpty [instanceConfig.scripts.up debugScript];
    down = joinNonEmpty [
      instanceConfig.scripts.down
      (lib.optional instanceConfig.routes.ignore (routes_handler "del-routes" ''${pkgs.iproute2}/bin/ip route del "$route_network/$route_netmask" via "$route_gateway" dev "$dev"''))
      debugScript
    ];
    autoStart = lib.mkDefault false;
  };

  mkServiceConfig = instance: instanceConfig:
    lib.nameValuePair "openvpn-${instance}" {
      inherit (instanceConfig) enable;
      serviceConfig.WorkingDirectory = "/etc/kdn/openvpn/${instance}";
    };
in {
  options.kdn.networking.openvpn = {
    enable = lib.mkEnableOption "OpenVPN setup wrapper";
    debug = lib.mkEnableOption "OpenVPN debugging JSONs at /tmp/openvpn/<instance>/<date>.jsonl";
    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          debug = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          config = lib.mkOption {
            type = lib.types.lines;
            default = "";
          };
          routes.ignore = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          routes.add = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                network = lib.mkOption {
                  type = lib.types.str;
                };
                netmask = lib.mkOption {
                  type = lib.types.str;
                  default = "255.255.255.0";
                };
              };
            });
            default = [];
          };
          scripts = let
            opt = lib.mkOption {
              type = lib.types.lines;
              default = "";
            };
          in {
            up = opt;
            tls-verify = opt;
            ipchange = opt;
            route-up = opt;
            route-pre-down = opt;
            down = opt;
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    programs.openvpn3.enable = true;

    services.openvpn.servers = lib.attrsets.mapAttrs mkOpenVPNConfig cfg.instances;
    systemd.services = lib.attrsets.mapAttrs' mkServiceConfig cfg.instances;

    nixpkgs.overlays = [
      (final: prev: {
        # see https://github.com/NixOS/nixpkgs/issues/349012#issuecomment-2424719649
        openvpn3 = prev.openvpn3.overrideAttrs (old: {
          patches =
            (old.patches or [])
            ++ [
              ./fix-tests.patch # point to wherever you have this file, or use something like `fetchpatch`
            ];
        });
      })
    ];

    environment.systemPackages = [
      (lib.kdn.shell.writeShellScript pkgs ./bin/kdn-openvpn-setup.sh {
        runtimeInputs = with pkgs; [xkcdpass];
      })
    ];
  };
}
