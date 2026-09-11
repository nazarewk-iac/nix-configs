# The shared schema of the `net-router` aspect family: the derived values and the two option types.
#
# It is one target file of the `net-router` aspect family. ./net-router.nix declares the family
# and ../README.md states the rules.
#
# It is NOT a module. It is a plain function of `{ config, lib, pkgs }`. It declares no option, it
# writes no config and it holds no `imports`. Each target module imports it and inherits the ten
# names below.
#
# ## What it holds
#
# | Concern | Old line range |
# |---|---|
# | `cfg`, `hostname`, the drop-in path helpers, `ports`, `keaTSIGName`, `defaultDNSServers` | 10-34 |
# | `templateType` — a networkd unit template as sections of key-value lists | 72-173 |
# | `netType` — one network: netdev, addressing, DHCP hosts, firewall, prefixes | 175-466 |
# | `mkDebugOption` — a bool option that follows `cfg.debug.all` | 468-473 |
#
# ## What the port changes
#
# 1. The argument list drops the removed special argument. Only `config`, `lib` and `pkgs` remain.
# 2. The two knot shell wrappers (old 36-70) move to ./ddns.nix. They are the only part of the old
#    `let` block that this file leaves out.
# 3. Every other line is verbatim. `cfg` stays a let-binding, so `netType` and `templateType` read
#    `cfg.dhcp-ddns.suffix`, `cfg.unit.prefix` and `cfg.dropin.infix` with no change.
{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.kdn.networking.router;
  hostname = config.kdn.hostName;

  mkDropInDir = unit: "/etc/systemd/network/${unit}.d";
  mkDropInPath = unit: name: "${mkDropInDir unit}/${cfg.dropin.infix}-${name}.conf";

  getInterfaceUnit =
    iface: lib.attrsets.attrByPath [ iface "unit" "name" ] "${cfg.unit.prefix}${iface}" cfg.nets;

  ports.dns.default = 53;
  ports.dns.tls = 853;
  ports.mdns = 5353;
  ports.dhcp.v4-request = 67;
  ports.dhcp.v4-reply = 68;
  ports.dhcp.v6-request = 546;
  ports.dhcp.v6-reply = 547;

  keaTSIGName = "kea.${hostname}";

  defaultDNSServers = lib.pipe cfg.nets [
    builtins.attrValues
    (builtins.filter (netCfg: netCfg.type == "wan" && netCfg.wan.asDefaultDNS))
    (map (netCfg: netCfg.wan.dns))
    builtins.concatLists
  ];

  templateType = lib.types.submodule (
    tpl:
    let
      leafType =
        with lib.types;
        oneOf [
          str
          bool
          int
          path
        ];
      convertToString =
        value:
        (
          {
            bool = builtins.toJSON;
          }
          ."${builtins.typeOf value}" or toString
        )
          value;
      sectionType =
        with lib.types;
        attrsOf (
          attrsOf (
            coercedTo (either (listOf leafType) leafType) (
              value:
              lib.pipe value [
                lib.lists.toList
                (map convertToString)
              ]
            ) (listOf str)
          )
        );
    in
    {
      options.values = lib.mkOption {
        type = sectionType;
        default = { };
      };
      options.sections = lib.mkOption {
        type = with lib.types; attrsOf sectionType;
        default = { };
      };
      options.text = lib.mkOption {
        type = with lib.types; str;
        default = "";
      };

      options._text = lib.mkOption {
        readOnly = true;
        type = with lib.types; str;
        default =
          let
            sections = [
              {
                name = "values";
                value = tpl.config.values;
              }
            ]
            ++ (lib.attrsets.mapAttrsToList lib.attrsets.nameValuePair tpl.config.sections);

            renderSection =
              sectionName: entries:
              lib.pipe entries [
                (lib.attrsets.mapAttrsToList (key: map (value: "${key}=${value}")))
                builtins.concatLists
                (lines: [
                  "[${sectionName}]"
                  lines
                ])
              ];
          in
          lib.pipe sections [
            (map (
              sec:
              lib.pipe sec.value [
                (lib.attrsets.mapAttrsToList renderSection)
                lib.lists.flatten
                (builtins.concatStringsSep "\n")
                (txt: ''
                  ###
                  ## [BEGIN] SECTION: ${sec.name}
                  #

                  ${txt}

                  #
                  ## [END]   SECTION: ${sec.name}
                  ###
                '')
              ]
            ))
            (builtins.concatStringsSep "\n\n\n")
            (txt: ''
              ${txt}

              ${tpl.config.text}
            '')
          ];
      };
    }
  );

  netType = lib.types.submodule (
    { name, ... }@netArgs:
    let
      netCfg = netArgs.config;
    in
    {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = netArgs.name;
        };
        unit.name = lib.mkOption {
          type = with lib.types; str;
          default = "${cfg.unit.prefix}${netCfg.name}";
        };
        type = lib.mkOption {
          type =
            with lib.types;
            enum [
              "wan"
              "lan"
            ];
        };
        netdev.kind = lib.mkOption {
          type =
            with lib.types;
            enum [
              "bond"
              "bridge"
              "vlan"
            ];
          default =
            {
              wan = "bond";
              vlan = "vlan";
            }
            .${netCfg.type} or "bridge";
        };
        netdev.bond.mode = lib.mkOption {
          type =
            with lib.types;
            enum [
              "backup"
              "aggregate"
            ];
          default = "backup";
        };
        vlan.id = lib.mkOption {
          type = with lib.types; ints.between 1 4095;
        };
        interface = lib.mkOption {
          type = with lib.types; str;
          default = netCfg.name;
        };
        interfaces = lib.mkOption {
          type = with lib.types; listOf str;
        };
        forward.to = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };
        forward.from = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };
        lan.uplink = lib.mkOption {
          type = with lib.types; str;
        };
        wan.asDefaultDNS = lib.mkOption {
          type = with lib.types; bool;
          default = false;
        };
        wan.dns = lib.mkOption {
          type = with lib.types; listOf str;
          default = netCfg.wan.gateway;
        };
        wan.gateway = lib.mkOption {
          type = with lib.types; listOf str;
        };
        address = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };
        prefix = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
        };
        domain = lib.mkOption {
          type = with lib.types; nullOr str;
          default =
            if cfg.dhcp-ddns.suffix == null then
              null
            else
              "${netCfg.name}.${config.kdn.hostName}.${cfg.dhcp-ddns.suffix}";
          apply =
            domain:
            assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
              `kdn.networking.router.nets.*.domain` must end with a '.': ${domain}
            '';
            domain;
        };
        template.network = lib.mkOption {
          type = templateType;
          default = { };
        };
        addressing = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              addrArgs:
              let
                addrCfg = addrArgs.config;
              in
              {
                options = {
                  enable = lib.mkOption {
                    type = with lib.types; bool;
                    default = true;
                  };
                  type = lib.mkOption {
                    type =
                      with lib.types;
                      enum [
                        "ipv4"
                        "ipv6"
                      ];
                    default = if lib.strings.hasInfix ":" addrCfg.network then "ipv6" else "ipv4";
                  };
                  subnet-id = lib.mkOption {
                    # see https://kea.readthedocs.io/en/kea-2.7.1/arm/dhcp4-srv.html#ipv4-subnet-identifier
                    # > python -c 'import random; print(random.randint(1, 4294967295))'
                    type = with lib.types; ints.between 1 4294967295;
                  };
                  network = lib.mkOption {
                    type = with lib.types; str;
                  };
                  netmask = lib.mkOption {
                    type = with lib.types; str;
                  };
                  pools = lib.mkOption {
                    type = lib.types.attrsOf (
                      lib.types.submodule (poolArgs: {
                        options = {
                          start = lib.mkOption {
                            type = with lib.types; str;
                          };
                          end = lib.mkOption {
                            type = with lib.types; str;
                          };
                        };
                      })
                    );
                  };
                  hosts = lib.mkOption {
                    type = lib.types.attrsOf (
                      lib.types.submodule (
                        { name, ... }@hostArgs:
                        let
                          hostCfg = hostArgs.config;
                        in
                        {
                          options = {
                            hostname = lib.mkOption {
                              type = with lib.types; str;
                              default = hostArgs.name;
                            };
                            ip = lib.mkOption {
                              type = with lib.types; nullOr str;
                              default = null;
                            };
                            ident = lib.mkOption {
                              type = with lib.types; attrsOf str;
                              default = { };
                              apply =
                                val:
                                val
                                // lib.attrsets.optionalAttrs (val != { } && hostCfg.ip != null) {
                                  ip-address = hostCfg.ip;
                                };
                            };
                            idents = lib.mkOption {
                              type = with lib.types; listOf (attrsOf str);
                              default = [ ];
                              apply = value: value ++ lib.lists.optional (hostCfg.ident != { }) hostCfg.ident;
                            };
                          };
                        }
                      )
                    );
                    default = { };
                  };
                };
              }
            )
          );
          default = { };
        };
        ra.implementation = lib.mkOption {
          type =
            with lib.types;
            enum [
              "networkd"
              #"corerad"
              #"kea"
            ];
          default = "networkd";
        };
        firewall = {
          trusted = lib.mkOption {
            type = with lib.types; bool;
            default = false;
          };
          allowedTCPPorts = lib.mkOption {
            type = with lib.types; listOf port;
            default = [ ];
            apply = ports: lib.unique (builtins.sort builtins.lessThan ports);
          };

          allowedTCPPortRanges = lib.mkOption {
            type = with lib.types; listOf (attrsOf port);
            default = [ ];
          };

          allowedUDPPorts = lib.mkOption {
            type = with lib.types; listOf port;
            default = [ ];
            apply = ports: lib.unique (builtins.sort builtins.lessThan ports);
          };

          allowedUDPPortRanges = lib.mkOption {
            type = with lib.types; listOf (attrsOf port);
            default = [ ];
          };
        };
      };
      config = lib.mkMerge [
        {
          template.network.values.Network = {
            Address = lib.pipe netCfg.addressing [
              builtins.attrValues
              (map (addrCfg: "${addrCfg.hosts."${hostname}".ip}/${addrCfg.netmask}"))
              (l: netCfg.address ++ l)
              lib.lists.unique
            ];
          };
        }
        (lib.mkIf (netCfg.type == "wan") {
          template.network.values.Network = {
            DNS = netCfg.wan.dns;
            Gateway = netCfg.wan.gateway;
          };
          template.network.sections = lib.attrsets.mapAttrs' (name: prefix: {
            name = "prefix-${name}";
            value.IPv6Prefix = {
              Prefix = prefix;
              OnLink = true;
              AddressAutoconfiguration = false;
              Assign = false;
            };
          }) netCfg.prefix;
        })
        (lib.mkIf (netCfg.type == "lan") (
          lib.mkMerge [
            {
              forward.to = [ netCfg.lan.uplink ];
              firewall = {
                allowedTCPPorts = [
                  ports.mdns
                ]
                ++ builtins.attrValues ports.dns;
                allowedUDPPorts = [
                  ports.mdns
                ]
                ++ builtins.attrValues ports.dns
                ++ builtins.attrValues ports.dhcp;
              };
              template.network.sections = lib.mkMerge [
                (lib.attrsets.mapAttrs' (name: prefix: {
                  name = "prefix-${name}";
                  value.IPv6Prefix = {
                    Prefix = prefix;
                    OnLink = true;
                    AddressAutoconfiguration = true;
                    Assign = false;
                  };
                }) netCfg.prefix)
              ];
            }
          ]
        ))
      ];
    }
  );

  mkDebugOption =
    args:
    lib.mkOption {
      type = with lib.types; bool;
      default = args.default or cfg.debug.all;
    };
in
{
  inherit
    hostname
    mkDropInDir
    mkDropInPath
    getInterfaceUnit
    ports
    keaTSIGName
    defaultDNSServers
    templateType
    netType
    mkDebugOption
    ;
}
