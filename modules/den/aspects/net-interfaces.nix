# The interface graph of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It states every network interface of one machine as data, and it renders systemd-networkd units
# from that data. Three option sets hold the data: `ifaces`, `bonds` and `vlans`. An entry with
# `managed = false` stays out of every render, so a consumer names an interface and still leaves the
# unit to another module.
#
# It writes four things:
#
#   * `networking.networkmanager.unmanaged` — one entry per managed interface, by MAC or by name.
#   * `systemd.network.links` — a `00-<name>` link per interface with a MAC selector. It renames the
#     interface, and it sets a new MAC address when the entry names one.
#   * `systemd.network.netdevs` — a `50-<name>` bond and a `10-<name>` VLAN.
#   * `systemd.network.networks` — a `50-<name>` network per interface, plus the bond membership and
#     the VLAN parent link.
#
# ## Class list: `nixos`
#
# systemd-networkd is Linux only, and the old module puts every effect behind a `nixos` guard.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. Every option defaults to an empty set, so an
#    adopter that names no interface gets an empty render and no NetworkManager entry.
# 2. **`debug` stays a plain flag.** It raises the networkd log level. It is not an `enable` for this
#    aspect, and it stays `false` by default.
# 3. **Nothing else changes.** The option names, the unit names and the render logic are the old
#    ones.
#
# DECISION TO REVISE: the old module reads `cfg._managed.bond."${name}" or null`, and `_managed`
# holds `bonds`, never `bond`. So the `or` always answers null, and every managed interface gets
# `LinkLocalAddressing = "ipv6"` — a bond member included. This port keeps that behaviour, so no
# existing host changes. Fix it in a separate commit, with one host build per bond host.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The per-interface `managed` and
#    `dynamicIPClient` flags sit inside an `attrsOf submodule`, so the option walk reaches neither.
# 3. **No custom module argument.** The target module takes `config` and `lib` only.
{ ... }:
{
  kdn.net-interfaces.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.networking;
    in
    {
      options.kdn.networking.debug = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Raise the systemd-networkd log level to `debug`.";
      };

      options.kdn.networking.iface.default = lib.mkOption {
        type = lib.types.str;
        default = cfg.iface.internal;
        defaultText = lib.literalExpression "config.kdn.networking.iface.internal";
        description = ''
          The key of the default interface. The `apply` turns the key into that interface's own
          configuration, so a reader gets the entry and not the name.
        '';
        apply = key: cfg.ifaces."${key}";
      };

      options.kdn.networking.iface.internal = lib.mkOption {
        type = lib.types.str;
        example = "lan0";
        description = ''
          The key of the internal interface. The `apply` turns the key into that interface's own
          configuration.

          It carries no default, so a read throws when the consumer names none. Nothing in this
          aspect reads it.
        '';
        apply = key: cfg.ifaces."${key}";
      };

      options.kdn.networking._managed = lib.mkOption {
        readOnly = true;
        internal = true;
        description = "The three data sets, filtered down to the managed entries.";
        default =
          let
            isIfManaged = lib.filterAttrs (key: _: cfg.ifaces."${key}".managed);
          in
          {
            ifaces = isIfManaged cfg.ifaces;
            bonds = isIfManaged cfg.bonds;
            vlans = isIfManaged cfg.vlans;
          };
      };

      options.kdn.networking.ifaces = lib.mkOption {
        default = { };
        description = "One entry per network interface of this machine.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@ifaceArgs:
            let
              ifaceCfg = ifaceArgs.config;
            in
            {
              options.managed = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Render a unit for this interface. `false` leaves it to another module.";
              };
              options._key = lib.mkOption {
                internal = true;
                readOnly = true;
                type = lib.types.str;
                default = name;
                description = "The attribute name of this entry.";
              };
              options.types = lib.mkOption {
                internal = true;
                readOnly = true;
                description = "The bond entry and the VLAN entry that share this interface name.";
                default =
                  lib.pipe
                    [
                      "bonds"
                      "vlans"
                    ]
                    [
                      (map (
                        type:
                        let
                          value = cfg."${type}"."${name}" or null;
                        in
                        if value != null then
                          {
                            key = type;
                            inherit value;
                          }
                        else
                          { }
                      ))
                      lib.attrsets.listToAttrs
                    ];
              };
              options.name = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "The interface name the kernel shows.";
              };
              options.unitPrefix = lib.mkOption {
                type = lib.types.str;
                default = "50";
                description = "The numeric prefix of this interface's own unit name.";
              };
              options.unitName = lib.mkOption {
                type = lib.types.str;
                default = "${ifaceCfg.unitPrefix}-${ifaceCfg.name}";
                defaultText = lib.literalExpression ''"''${unitPrefix}-''${name}"'';
                description = "The unit name of this interface.";
              };
              options.mac = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = "The MAC address to set on this interface. `null` keeps the hardware one.";
              };
              options.selector.mac = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = ''
                  The permanent MAC address that names this interface. When set, the render matches on
                  it and renames the interface.
                '';
              };
              options.dynamicIPClient = lib.mkOption {
                type = lib.types.bool;
                default = false;
                example = true;
                description = "Run a dynamic IP client on this interface: DHCP plus IPv6 router advertisement.";
              };
              options.metric = lib.mkOption {
                type = lib.types.ints.u16;
                example = 1024;
                description = ''
                  The route metric of this interface. The dynamic IP client reads it, so an entry with
                  `dynamicIPClient = true` must name it.
                '';
              };
              options.address = lib.mkOption {
                type = with lib.types; attrsOf str;
                default = { };
                example = {
                  v4 = "192.0.2.10/24";
                };
                description = "The static addresses of this interface, keyed by a name of the consumer's choice.";
              };
            }
          )
        );
      };

      options.kdn.networking.bonds = lib.mkOption {
        default = { };
        description = "One entry per bond interface. The attribute name matches an `ifaces` entry.";
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.children = lib.mkOption {
              type = with lib.types; listOf str;
              description = "The interface names this bond takes as members.";
            };
            options.type = lib.mkOption {
              type =
                with lib.types;
                enum [
                  "lacp"
                ];
              description = "The bond mode. `lacp` renders mode `802.3ad`.";
            };
          }
        );
      };

      options.kdn.networking.vlans = lib.mkOption {
        default = { };
        description = "One entry per VLAN interface. The attribute name matches an `ifaces` entry.";
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.id = lib.mkOption {
              type = lib.types.ints.u16;
              example = 10;
              description = "The VLAN id.";
            };
            options.parent = lib.mkOption {
              type = with lib.types; str;
              example = "lan0";
              description = "The interface name that carries this VLAN.";
            };
          }
        );
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.debug {
          systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
        })
        {
          networking.networkmanager.unmanaged = lib.pipe cfg._managed.ifaces [
            builtins.attrValues
            (map (
              ifaceCfg:
              if ifaceCfg.selector.mac != null then
                "mac:${ifaceCfg.selector.mac}"
              else
                "interface-name:${ifaceCfg.name}"
            ))
          ];

          systemd.network.networks = lib.pipe cfg._managed.ifaces [
            (lib.attrsets.mapAttrsToList (
              name: ifaceCfg: {
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
                      (map (addr: {
                        Address = addr;
                      }))
                    ];
                  }
                  (lib.mkIf ifaceCfg.dynamicIPClient {
                    networkConfig = {
                      DHCP = true;
                      UseDomains = true;

                      IPv6AcceptRA = true;
                    };

                    # Multicast is required before IPv6AcceptRA takes effect on a bond interface.
                    linkConfig.Multicast = true;
                    dhcpV4Config.RouteMetric = ifaceCfg.metric;
                    ipv6AcceptRAConfig.RouteMetric = ifaceCfg.metric;
                  })
                ];
              }
            ))
            lib.mkMerge
          ];
          systemd.network.links = lib.pipe cfg._managed.ifaces [
            (lib.attrsets.filterAttrs (name: ifaceCfg: ifaceCfg.selector.mac != null))
            (lib.attrsets.mapAttrsToList (
              name: ifaceCfg: {
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
              }
            ))
            lib.mkMerge
          ];
        }
        {
          systemd.network.netdevs = lib.pipe cfg._managed.bonds [
            (lib.attrsets.mapAttrsToList (
              name: bondCfg:
              let
                ifaceCfg = cfg.ifaces."${name}";
              in
              {
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
              }
            ))
            lib.mkMerge
          ];
          systemd.network.networks = lib.pipe cfg._managed.bonds [
            (lib.attrsets.mapAttrsToList (
              name: bondCfg:
              let
                ifaceCfg = cfg.ifaces."${name}";
              in
              (map (childName: {
                "50-${childName}".networkConfig.Bond = ifaceCfg.name;
              }) bondCfg.children)
            ))
            builtins.concatLists
            lib.mkMerge
          ];
        }
        {
          systemd.network.netdevs = lib.pipe cfg._managed.vlans [
            (lib.attrsets.mapAttrsToList (
              name: vlanCfg:
              let
                ifaceCfg = cfg.ifaces."${name}";
              in
              {
                "10-${name}" = {
                  netdevConfig.Kind = "vlan";
                  netdevConfig.Name = ifaceCfg.name;
                  vlanConfig.Id = vlanCfg.id;
                };
              }
            ))
            lib.mkMerge
          ];
          systemd.network.networks = lib.pipe cfg._managed.vlans [
            (lib.attrsets.mapAttrsToList (
              name: vlanCfg:
              let
                ifaceCfg = cfg.ifaces."${name}";
              in
              {
                "50-${vlanCfg.parent}".networkConfig.VLAN = [ ifaceCfg.name ];
              }
            ))
            lib.mkMerge
          ];
        }
      ];
    };
}
