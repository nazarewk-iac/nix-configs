{
  lib,
  pkgs,
  config,
  ...
}: let
  defaultPort = 51820;

  sopsSecrets = config.kdn.security.secrets.sops.secrets.default.netbird;

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
        secrets = lib.mkOption {
          readOnly = true;
          default = let
            secrets = config.kdn.security.secrets.sops.secrets.default.netbird;
          in
            if secrets ? "${nbCfg.secretKey}"
            then secrets."${nbCfg.secretKey}"
            else null;
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
          value = lib.mkIf (nbCfg.secrets != null) (lib.mkMerge [
            {
              after = ["kdn-secrets.target"];
              requires = ["kdn-secrets.target"];
            }
            (lib.mkIf (nbCfg.secrets ? "${nbCfg.type}".setup-key) {
              serviceConfig.LoadCredential = ["setup-key:${nbCfg.secrets."${nbCfg.type}".setup-key.path}"];
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

                main() {
                  print_status | ${lib.getExe pkgs.gnused} 's/^/STATUS:INIT: /g'
                  while refresh_status | grep --quiet 'Disconnected' ; do
                    sleep 1
                  done
                  print_status | ${lib.getExe pkgs.gnused} 's/^/STATUS:WAIT: /g'

                  if print_status | grep --quiet 'NeedsLogin' ; then
                    echo "Using keyfile $(cut -b1-8 <"$keyFile")" >&2
                    "$nb" up --setup-key-file="$keyFile"
                  fi
                }

                main "$@"
              '';
            })
            (lib.mkIf (nbCfg.secrets ? env) {
              serviceConfig.LoadCredential = ["env:${nbCfg.secrets.env.path}"];
              serviceConfig.EnvironmentFile = "-%d/env";
            })
          ]);
        }))
        builtins.listToAttrs
      ];
    })
    /*
    TODO: instance-switcher script:
      1. confirm whether it's currently active
      2. turn off all instances (`netbird.target`?)
      3. start the selected instance
      4. add a second "proxy" CLI `netbird` to determine which instance is active and run against it?
    */
  ]);
}
