# Kea DHCPv4 and DHCPv6 of the router.
#
# It is one target module of the `net-router` aspect family. ./net-router.nix declares the family
# and ../README.md states the rules.
#
# ## What it holds
#
# | Concern | Old line range |
# |---|---|
# | The `kea.dhcp4.settings` and `kea.dhcp6.settings` options | 532-539 |
# | The DHCPv4 service, and the settings built from `cfg.nets` | 955-1046 |
# | The `kea/dhcp4.conf` template, and the DHCPv4 config file | 1059-1070 |
# | The `kea/dhcp6.conf` template, and the DHCPv6 config file | 1071-1082 |
#
# ## What the port changes
#
# 1. S1: the `config` head is a plain `lib.mkMerge` list. The old `enable` guard and the old
#    platform guard both go.
# 2. S5: the two option types read `jsonTemplate.type`, so no package overlay is needed.
# 3. S6: `jsonTemplate.generateText` replaces the old generate-plus-read pair. It returns a
#    string, so the `builtins.readFile` wrapper goes.
# 4. S7: the aspect writes `kdn.networking.router.templates.<name>`. A consumer maps that set into
#    its own secret renderer.
# 5. S8: each config file path reads `cfg.templates.<name>.path`.
# 6. S13: the `cfg.debug.kea-dhcp4` severity test stays verbatim.
#
# ## What it reads from a sibling
#
# `base.nix` declares `cfg.nets`, `cfg.templates` and `cfg.debug.kea-dhcp4`. The aspect `includes`
# supplies them.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kdn.networking.router;
  schema = import ./schema.nix { inherit config lib pkgs; };
  inherit (schema)
    hostname
    ;
  jsonTemplate = import ./json-template.nix { inherit lib pkgs; };
in
{
  imports = [ ../../common/host-name.nix ];

  options.kdn.networking.router = {
    kea.dhcp4.settings = lib.mkOption {
      type = jsonTemplate.type;
      default = { };
    };
    kea.dhcp6.settings = lib.mkOption {
      type = jsonTemplate.type;
      default = { };
    };
  };

  config = lib.mkMerge [
    {
      # Kea DHCPv4
      services.kea = {
        dhcp4.enable = true;
      };
      kdn.networking.router = {
        kea.dhcp4.settings = lib.pipe cfg.nets [
          builtins.attrValues
          (builtins.filter (netCfg: netCfg.type == "lan"))
          (map (netCfg: {
            interfaces-config.interfaces = [ netCfg.interface ];
            subnet4 = lib.pipe netCfg.addressing [
              builtins.attrValues
              (builtins.filter (addrCfg: addrCfg.enable && addrCfg.type == "ipv4"))
              (map (addrCfg: {
                id = addrCfg.subnet-id;
                interface = netCfg.interface;
                subnet = with addrCfg; "${network}/${netmask}";
                pools = lib.pipe addrCfg.pools [
                  builtins.attrValues
                  (map (pool: {
                    pool = with pool; "${start} - ${end}";
                  }))
                ];
                option-data = [
                  {
                    name = "domain-name";
                    data = netCfg.domain;
                  }
                  {
                    name = "domain-name-servers";
                    data = addrCfg.hosts."${hostname}".ip;
                  }
                  {
                    name = "domain-search";
                    data = netCfg.domain;
                  }
                  {
                    name = "routers";
                    data = addrCfg.hosts."${hostname}".ip;
                  }
                ];
                reservations = lib.pipe addrCfg.hosts [
                  (lib.attrsets.mapAttrsToList (
                    _: host:
                    map (
                      ident:
                      ident
                      // {
                        hostname = host.hostname;
                      }
                    ) host.idents
                  ))
                  lib.lists.flatten
                ];
                ddns-send-updates = true;
                ddns-qualifying-suffix = netCfg.domain;
              }))
            ];
          }))
          (
            p:
            p
            ++ [
              {
                allocator = lib.mkDefault "random";
                # leases will be valid for 1h
                valid-lifetime = 1 * 60 * 60;
                # clients should renew every 30m
                renew-timer = 30 * 60;
                # clients should start looking for other servers after 45h
                rebind-timer = 45 * 60;
                lease-database = {
                  type = "memfile";
                  persist = true;
                  name = "/var/lib/kea/dhcp4.leases";
                };
                loggers = [
                  {
                    name = "kea-dhcp4";
                    severity = if cfg.debug.kea-dhcp4 then "DEBUG" else "INFO";
                    debuglevel = 99;
                    output_options = [ { output = "stderr"; } ];
                  }
                ];
              }
            ]
          )
          lib.mkMerge
        ];
      };
    }
    {
      kdn.networking.router.templates."kea/dhcp4.conf" = {
        mode = "0444";
        reloadUnits = [ "kea-dhcp4-server.service" ];
        content = jsonTemplate.generateText {
          Dhcp4 = cfg.kea.dhcp4.settings;
        };
      };
      services.kea.dhcp4.configFile = cfg.templates."kea/dhcp4.conf".path;
    }
    {
      kdn.networking.router.templates."kea/dhcp6.conf" = {
        mode = "0444";
        reloadUnits = [ "kea-dhcp6-server.service" ];
        content = jsonTemplate.generateText {
          Dhcp6 = cfg.kea.dhcp6.settings;
        };
      };
      services.kea.dhcp6.configFile = cfg.templates."kea/dhcp6.conf".path;
    }
  ];
}
