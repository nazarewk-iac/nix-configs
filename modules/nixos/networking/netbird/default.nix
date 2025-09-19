{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.networking.netbird;
  activeCfgs = lib.pipe config.kdn.networking.netbird.clients [
    builtins.attrValues
    (builtins.filter (nbCfg: nbCfg.enable))
  ];
in {
  options.kdn.networking.netbird = {
    useOwnPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    defaultUsers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
    adminUsers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
  };
  options.kdn.networking.netbird.clients = lib.mkOption {
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
        userName = lib.mkOption {
          type = with lib.types; str;
          default = nbCfg.serviceName;
        };
        groupName = lib.mkOption {
          type = with lib.types; str;
          default = nbCfg.serviceName;
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
          # 0 for picking a random available port on v0.50.2+
          default = let
            version = config.services.netbird.package.version;
          in
            if lib.strings.hasPrefix "0." version && lib.strings.versionOlder version "0.50.2"
            then 51820 - nbCfg.idx
            else 0;
        };

        localAddress = lib.mkOption {
          type = with lib.types; str;
          default = "127.5.18.${builtins.toString (20 - nbCfg.idx)}";
        };

        type = lib.mkOption {
          type = with lib.types; enum ["ephemeral" "permanent"];
          default = "permanent";
        };

        users = lib.mkOption {
          type = with lib.types; listOf str;
          default = cfg.defaultUsers;
          apply = users:
            lib.pipe users [
              (u: u ++ cfg.adminUsers)
              (builtins.sort builtins.lessThan)
              lib.lists.uniqueStrings
            ];
        };
      };
    }));
  };

  config = lib.mkIf (config.kdn.networking.netbird.clients != {}) (lib.mkMerge [
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
      kdn.hw.disks.persist."usr/data".directories = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          directory = "/var/lib/${nbCfg.serviceName}";
          user = nbCfg.userName;
          group = nbCfg.groupName;
          mode = "0700";
        }))
      ];

      users.groups = lib.pipe activeCfgs [
        (builtins.map (nbCfg: lib.attrsets.nameValuePair nbCfg.groupName {members = nbCfg.users;}))
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
            login.systemdDependencies = ["kdn-secrets.target"];
            login.setupKeyFile = nbCfg.secrets."${nbCfg.type}".setup-key.path;
          };
        }))
        builtins.listToAttrs
      ];
      systemd.services = lib.pipe activeCfgs [
        (builtins.map (nbCfg: {
          name = nbCfg.serviceName;
          value = lib.mkIf (nbCfg.secrets != null) (lib.mkMerge [
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
