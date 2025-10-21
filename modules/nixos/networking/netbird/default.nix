{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.networking.netbird;
  activeCfgs = lib.pipe config.kdn.networking.netbird.clients [
    builtins.attrValues
    (builtins.filter (nbCfg: nbCfg.enable))
  ];
in
{
  options.kdn.networking.netbird = {
    useOwnPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    admins = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    default.users = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    default.environment = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
    };
    default.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
  };
  options.kdn.networking.netbird.clients = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }@nbArgs:
        let
          nbCfg = nbArgs.config;
        in
        {
          options = {
            enable = lib.mkOption {
              type = with lib.types; bool;
              default = cfg.default.enable;
            };
            name = lib.mkOption {
              type = with lib.types; str;
              default = name;
            };
            serviceName = lib.mkOption {
              type = with lib.types; str;
              default = "netbird-${name}";
            };
            userName = lib.mkOption {
              type = with lib.types; str;
              default = nbCfg.serviceName;
            };
            groupName = lib.mkOption {
              type = with lib.types; str;
              default = nbCfg.serviceName;
            };
            interface = lib.mkOption {
              readOnly = true;
              default = "nb-${name}";
            };

            secretKey = lib.mkOption {
              type = with lib.types; str;
              default = nbCfg.name;
            };
            secrets = lib.mkOption {
              readOnly = true;
              default =
                let
                  secrets = config.kdn.security.secrets.sops.secrets.default.netbird;
                in
                if secrets ? "${nbCfg.secretKey}" then secrets."${nbCfg.secretKey}" else null;
            };

            idx = lib.mkOption {
              type = with lib.types; ints.between 0 20;
            };

            port = lib.mkOption {
              type = with lib.types; port;
              # 0 for picking a random available port on v0.50.2+
              default =
                let
                  version = config.services.netbird.package.version;
                in
                if lib.strings.hasPrefix "0." version && lib.strings.versionOlder version "0.50.2" then
                  51820 - nbCfg.idx
                else
                  0;
            };

            localAddress = lib.mkOption {
              type = with lib.types; str;
              default = "127.5.18.${builtins.toString (20 - nbCfg.idx)}";
            };

            type = lib.mkOption {
              type =
                with lib.types;
                enum [
                  "ephemeral"
                  "permanent"
                ];
              default = "permanent";
            };

            users = lib.mkOption {
              type = with lib.types; listOf str;
              default = cfg.default.users;
              apply =
                users:
                lib.pipe users [
                  (u: u ++ cfg.admins)
                  (builtins.sort builtins.lessThan)
                  lib.lists.uniqueStrings
                ];
            };
            environment = lib.mkOption {
              type = with lib.types; attrsOf str;
              default = { };
            };

            systemd.enable = lib.mkOption {
              type = with lib.types; bool;
              default = false;
            };

            resolvesDomains = lib.mkOption {
              type = with lib.types; nullOr (listOf str);
              default = null;
            };
          };
        }
      )
    );
  };

  config = lib.mkIf (config.kdn.networking.netbird.clients != { }) (
    lib.mkMerge [
      (lib.mkIf cfg.useOwnPackages {
        # inlined packages
        services.netbird.package = lib.mkDefault pkgs.kdn.netbird;
        services.netbird.ui.package = lib.mkDefault pkgs.kdn.netbird-ui;
        services.netbird.server.signal.package = lib.mkDefault pkgs.kdn.netbird-signal;
        services.netbird.server.management.package = lib.mkDefault pkgs.kdn.netbird-management;
        services.netbird.server.dashboard.package = lib.mkDefault pkgs.kdn.netbird-dashboard;
      })
      {
        # TODO: add/switch to `network-online.target` instead of `network.target` to properly initialize

        environment.systemPackages = with pkgs; [
          wireguard-tools
        ];

        systemd.targets.netbird =
          let
            services = builtins.map (nbCfg: "${nbCfg.serviceName}.service") activeCfgs;
          in
          {
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
              environment =
                builtins.mapAttrs (_: lib.mkOverride 1100) cfg.default.environment
                // builtins.mapAttrs (_: lib.mkDefault) nbCfg.environment;
            };
          }))
          builtins.listToAttrs
        ];

        systemd.network.networks = lib.pipe activeCfgs [
          (builtins.filter (nbCfg: nbCfg.systemd.enable))
          (builtins.map (nbCfg: {
            name = "40-kdn-netbird-${nbCfg.interface}";
            value = {
              matchConfig.Name = nbCfg.interface;
              linkConfig = {
                ActivationPolicy = "manual";
              };
              dns = [ nbCfg.localAddress ];
              domains = lib.mkIf (nbCfg.resolvesDomains != null) nbCfg.resolvesDomains;
              routingPolicyRules = [
                {
                  # 105:    from all lookup main suppress_prefixlength 0
                  Priority = 105; # 105:
                  Table = "main";
                  SuppressPrefixLength = 0;
                }
                {
                  # 110:    not from all fwmark 0x1bd00 lookup 7120
                  Priority = 110; # 110:
                  InvertRule = true; # not from all
                  FirewallMark = 113920; # fwmark 0x1bd00
                  Table = 7120; # lookup 7120
                }
              ];
            };
          }))
          builtins.listToAttrs
        ];
        kdn.hw.disks.persist."usr/data".directories = lib.pipe activeCfgs [
          (builtins.map (nbCfg: {
            directory = "/var/lib/${nbCfg.serviceName}";
            user = nbCfg.userName;
            group = nbCfg.groupName;
            mode = "0700";
          }))
        ];

        users.groups = lib.pipe activeCfgs [
          (builtins.map (nbCfg: lib.attrsets.nameValuePair nbCfg.groupName { members = nbCfg.users; }))
          builtins.listToAttrs
        ];
      }
      (lib.mkIf config.kdn.security.secrets.allowed {
        services.netbird.clients = lib.pipe config.kdn.networking.netbird.clients [
          builtins.attrValues
          (builtins.map (nbCfg: {
            name = nbCfg.name;
            value = lib.mkIf (nbCfg.secrets != null && nbCfg.secrets ? "${nbCfg.type}".setup-key) {
              login.enable = true;
              login.systemdDependencies = [ "kdn-secrets.target" ];
              login.setupKeyFile = nbCfg.secrets."${nbCfg.type}".setup-key.path;
            };
          }))
          builtins.listToAttrs
        ];
        systemd.services = lib.pipe activeCfgs [
          (builtins.map (nbCfg: {
            name = nbCfg.serviceName;
            value = lib.mkIf (nbCfg.secrets != null) (
              lib.mkMerge [
                (lib.mkIf (nbCfg.secrets ? env) {
                  serviceConfig.LoadCredential = [ "env:${nbCfg.secrets.env.path}" ];
                  serviceConfig.EnvironmentFile = "-%d/env";
                })
              ]
            );
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
    ]
  );
}
