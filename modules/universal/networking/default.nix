{
  config,
  lib,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.networking;
in {
  options.kdn.networking = {
    enable = lib.mkEnableOption "kdn's networking setup";
    debug = lib.mkEnableOption "kdn's networking setup debugging";
    iface.default = lib.mkOption {
      type = lib.types.str;
      default = cfg.iface.internal;
      apply = key: cfg.ifaces."${key}";
    };
    iface.internal = lib.mkOption {
      type = lib.types.str;
      apply = key: cfg.ifaces."${key}";
    };
    _managed = lib.mkOption {
      readOnly = true;
      internal = true;
      default = let
        isIfManaged = lib.filterAttrs (key: _: cfg.ifaces."${key}".managed);
      in {
        ifaces = isIfManaged cfg.ifaces;
        bonds = isIfManaged cfg.bonds;
        vlans = isIfManaged cfg.vlans;
      };
    };
    ifaces = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (lib.types.submodule ({name, ...} @ ifaceArgs: let
        ifaceCfg = ifaceArgs.config;
      in {
        options.managed = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        options._key = lib.mkOption {
          internal = true;
          readOnly = true;
          type = lib.types.str;
          default = name;
        };
        options.types = lib.mkOption {
          internal = true;
          readOnly = true;
          default = lib.pipe ["bonds" "vlans"] [
            (map (type: let
              value = cfg."${type}"."${name}" or null;
            in
              if value != null
              then {
                key = type;
                inherit value;
              }
              else {}))
            lib.attrsets.listToAttrs
          ];
        };
        options.name = lib.mkOption {
          type = lib.types.str;
          default = name;
        };
        options.unitPrefix = lib.mkOption {
          type = lib.types.str;
          default = "50";
        };
        options.unitName = lib.mkOption {
          type = lib.types.str;
          default = "${ifaceCfg.unitPrefix}-${ifaceCfg.name}";
        };
        options.mac = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };
        options.selector.mac = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };
        options.dynamicIPClient = lib.mkEnableOption "dynamic IP client (DHCP / RA)";
        options.metric = lib.mkOption {
          type = lib.types.ints.u16;
        };
        options.address = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = {};
        };
      }));
    };

    bonds = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (lib.types.submodule {
        options.children = lib.mkOption {
          type = with lib.types; listOf str;
        };
        options.type = lib.mkOption {
          type = with lib.types; enum ["lacp"];
        };
      });
    };

    vlans = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (lib.types.submodule ({name, ...} @ vlanArgs: {
        options.id = lib.mkOption {
          type = lib.types.ints.u16;
        };
        options.parent = lib.mkOption {
          type = with lib.types; str;
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifTypes ["nixos"] (lib.mkMerge [
      (lib.mkIf cfg.debug {
        systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
      })
      {
        networking.networkmanager.unmanaged = lib.pipe cfg._managed.ifaces [
          builtins.attrValues
          (map (ifaceCfg:
            if ifaceCfg.selector.mac != null
            then "mac:${ifaceCfg.selector.mac}"
            else "interface-name:${ifaceCfg.name}"))
        ];

        systemd.network.networks = lib.pipe cfg._managed.ifaces [
          (lib.attrsets.mapAttrsToList (name: ifaceCfg: {
            "50-${name}" = lib.mkMerge [
              {
                matchConfig = {
                  MACAddress = lib.mkIf (ifaceCfg.selector.mac != null) ifaceCfg.selector.mac;
                  Name = name;
                };
                linkConfig = {
                  # TODO; could probably make this configurable
                  RequiredForOnline = "yes";
                };
                networkConfig = {
                  LinkLocalAddressing = lib.mkIf (cfg._managed.bond."${name}" or null == null) "ipv6";

                  IPv6PrivacyExtensions = true;
                  IPv6LinkLocalAddressGenerationMode = "stable-privacy";
                };

                addresses = lib.pipe ifaceCfg.address [
                  builtins.attrValues
                  (map (addr: {Address = addr;}))
                ];
              }
              (lib.mkIf ifaceCfg.dynamicIPClient {
                networkConfig = {
                  DHCP = true;
                  UseDomains = true;

                  IPv6AcceptRA = true;
                };

                linkConfig.Multicast = true; # required for IPv6AcceptRA to take effect on bond interface
                dhcpV4Config.RouteMetric = ifaceCfg.metric;
                dhcpV6Config.RouteMetric = ifaceCfg.metric;
              })
            ];
          }))
          lib.mkMerge
        ];
        systemd.network.links = lib.pipe cfg._managed.ifaces [
          (lib.attrsets.filterAttrs (name: ifaceCfg: ifaceCfg.selector.mac != null))
          (lib.attrsets.mapAttrsToList (name: ifaceCfg: {
            "00-${name}" = lib.mkMerge [
              {
                matchConfig.PermanentMACAddress = ifaceCfg.selector.mac;
                linkConfig.NamePolicy = "";
                linkConfig.Name = name;
              }
              (lib.mkIf (ifaceCfg.mac != null) {
                linkConfig.MACAddressPolicy = "none";
                linkConfig.MACAddress = ifaceCfg.mac;
              })
            ];
          }))
          lib.mkMerge
        ];
      }
      {
        systemd.network.netdevs = lib.pipe cfg._managed.bonds [
          (lib.attrsets.mapAttrsToList (name: bondCfg: let
            ifaceCfg = cfg.ifaces."${name}";
          in {
            "50-${name}" = {
              netdevConfig.Kind = "bond";
              netdevConfig.Name = ifaceCfg.name;
              bondConfig = lib.mkIf (bondCfg.type == "lacp") {
                Mode = "802.3ad";
                TransmitHashPolicy = lib.mkDefault "encap3+4";
                LACPTransmitRate = lib.mkDefault "fast";
                MIIMonitorSec = lib.mkDefault "100ms";
              };
            };
          }))
          lib.mkMerge
        ];
        systemd.network.networks = lib.pipe cfg._managed.bonds [
          (lib.attrsets.mapAttrsToList (
            name: bondCfg: let
              ifaceCfg = cfg.ifaces."${name}";
            in (map (childName: {
                "50-${childName}".networkConfig.Bond = ifaceCfg.name;
              })
              bondCfg.children)
          ))
          builtins.concatLists
          lib.mkMerge
        ];
      }
      {
        systemd.network.netdevs = lib.pipe cfg._managed.vlans [
          (lib.attrsets.mapAttrsToList (name: vlanCfg: let
            ifaceCfg = cfg.ifaces."${name}";
          in {
            "10-${name}" = {
              netdevConfig.Kind = "vlan";
              netdevConfig.Name = ifaceCfg.name;
              vlanConfig.Id = vlanCfg.id;
            };
          }))
          lib.mkMerge
        ];
        systemd.network.networks = lib.pipe cfg._managed.vlans [
          (lib.attrsets.mapAttrsToList (name: vlanCfg: let
            ifaceCfg = cfg.ifaces."${name}";
          in {
            "50-${vlanCfg.parent}".networkConfig.VLAN = [ifaceCfg.name];
          }))
          lib.mkMerge
        ];
      }
    ]))
  ]);
}
