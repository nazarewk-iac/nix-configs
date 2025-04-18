{
  lib,
  pkgs,
  config,
  ...
}: let
  defaultPort = 51820;

  cfgs = config.kdn.networking.netbird;

  activeCfgs = lib.pipe config.kdn.networking.netbird [
    builtins.attrValues
    (builtins.filter (nbCfg: nbCfg.enable))
  ];
in {
  options.kdn.networking.netbird = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...} @ nbArgs: let
      nbCfg = nbArgs.config;
    in {
      options = {
        enable = lib.mkOption {
          type = with lib.types; bool;
          default = true;
        };
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };
        serviceName = lib.mkOption {
          type = with lib.types; str;
          default = "netbird-${name}";
        };

        secretKey = lib.mkOption {
          type = with lib.types; str;
          default = nbCfg.name;
        };
        secret = lib.mkOption {
          readOnly = true;
          default = config.kdn.security.secrets.sops.secrets.default.netbird."${nbCfg.secretKey}"."${nbCfg.type}";
        };

        idx = lib.mkOption {
          type = with lib.types; ints.between 0 20;
        };

        port = lib.mkOption {
          type = with lib.types; port;
          default = defaultPort - nbCfg.idx;
        };

        localAddress = lib.mkOption {
          type = with lib.types; str;
          default = "127.5.18.${builtins.toString (20 - nbCfg.idx)}";
        };

        type = lib.mkOption {
          type = with lib.types; enum ["ephemeral" "permanent"];
          default = "permanent";
        };
      };
    }));
  };

  config = lib.mkIf (config.kdn.networking.netbird != {}) (lib.mkMerge [
    {
      # TODO: add/switch to `network-online.target` instead of `network.target` to properly initialize

      environment.systemPackages = with pkgs; [
        wireguard-tools
      ];

      systemd.targets.netbird = let
        services = builtins.map (nbCfg: "${nbCfg.serviceName}.service") activeCfgs;
      in {
        wants = services;
        after = services;
        unitConfig.PropagatesStopTo = services;
      };
    }
    {
      /*
         TODO: does it need opening up the ports at all?
      /*
      networking.firewall.interfaces = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          name = nbCfg.interface;
          value = {
            allowedUDPPorts = [53 5353];
          };
        }))
        builtins.listToAttrs
      ];
      */
      services.netbird.clients = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          name = nbCfg.name;
          value = {
            port = nbCfg.port;
            dns-resolver.address = nbCfg.localAddress;
          };
        }))
        builtins.listToAttrs
      ];
      kdn.networking.router.kresd.rewrites = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          name = "${nbCfg.name}.nb.net.int.kdn.im.";
          value = {
            from = "netbird.cloud.";
            upstreams = [nbCfg.localAddress];
          };
        }))
        builtins.listToAttrs
      ];
      kdn.hw.disks.persist."usr/data".directories = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          directory = "/var/lib/${nbCfg.serviceName}";
          user = nbCfg.serviceName;
          group = nbCfg.serviceName;
          mode = "0700";
        }))
      ];
    }
    (lib.mkIf config.kdn.security.secrets.allowed {
      systemd.services = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          name = nbCfg.serviceName;
          value = {
            after = ["kdn-secrets.target"];
            requires = ["kdn-secrets.target"];
            serviceConfig.LoadCredential = [
              "setup-key:${nbCfg.secret.setup-key.path}"
            ];
            environment.NB_SETUP_KEY_FILE = "%d/setup-key";
            postStart = ''
              set -x
              nb='${lib.getExe config.services.netbird.clients."${nbCfg.name}".wrapper}'
              keyFile="''${NB_SETUP_KEY_FILE:-"/run/credentials/${nbCfg.serviceName}.service/setup-key"}"
              fetch_status() {
                status="$("$nb" status 2>&1)"
              }
              print_status() {
                test -n "$status" || refresh_status
                cat <<EOF
              $status
              EOF
              }
              refresh_status() {
                fetch_status
                print_status
              }
              print_status | ${lib.getExe pkgs.gnused} 's/^/STATUS:INIT: /g'
              while refresh_status | grep --quiet 'Disconnected' ; do
                sleep 1
              done
              print_status | ${lib.getExe pkgs.gnused} 's/^/STATUS:WAIT: /g'

              if print_status | grep --quiet 'NeedsLogin' ; then
                echo "Using keyfile $(cut -b1-8 <"$keyFile")" >&2
                "$nb" up --setup-key-file="$keyFile"
              fi
            '';
          };
        }))
        builtins.listToAttrs
      ];
    })
  ]);
}
