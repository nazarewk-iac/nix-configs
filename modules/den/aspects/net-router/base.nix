# The base router: the net graph, systemd-networkd, the firewall, NAT and the debug tree.
#
# It is one target module of the `net-router` aspect family. ./net-router.nix declares the family
# and ../README.md states the rules.
#
# ## What it holds
#
# | Concern | Old line range |
# |---|---|
# | `debug.*` switches, `dropin.infix`, `unit.prefix` | 479-503 |
# | `forwardings` and `nets` | 545-562 |
# | `dhcp-ddns.suffix` | 588-591 |
# | the `templates` option | new, see below |
# | networkd base, resolved, nameservers, one persist bucket | 800-827 |
# | the secrets target order over 7 services | 828-844 |
# | the pcscd circular-dependency fix | 845-855 |
# | firewall and nftables base, forward rules from `forwardings` | 856-878 |
# | the networkd, resolved and firewall debug switches, two ICMPv6 log tables | 882-931 |
# | the networkd reload watcher | 932-941 |
# | the managed-file cleanup of `/etc/systemd/network` | 942-954 |
# | firewall and forward rules derived from `nets` | 1556-1593 |
# | networkd netdevs, networks and the per-net drop-in template | 1594-1760 |
#
# `dhcp-ddns.suffix` stays here because `netType` in ./schema.nix reads it, and `nets` is a base
# option. The DDNS target only acts on the value.
#
# ## What the port changes
#
# 1. The old `config` head becomes a plain `lib.mkMerge`. Inclusion is the switch, so the outer
#    `enable` guard and the platform guard both go. Every inner `lib.mkIf` stays.
# 2. The old top-level `enable` option goes, for the same reason.
# 3. The dead `dhcpv4.implementation` and `dhcpv6.implementation` options go.
# 4. The `sops.templates` write of old line 1744 becomes `kdn.networking.router.templates`. The new
#    option publishes the same submodule keys, so a consumer maps the set with one line.
# 5. The `kdn.fs.watch.enable` line of old line 801 goes. The aspect `includes` covers it.
# 6. The old cleanup list names three directories. This file keeps `/etc/systemd/network` only.
#    The DNS target adds the resolver directory and the DDNS target adds the knot directory.
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
    mkDropInPath
    getInterfaceUnit
    defaultDNSServers
    netType
    mkDebugOption
    ;
in
{
  imports = [
    ../../common/host-name.nix
    ../../common/persist.nix
  ];

  options.kdn.networking.router = {
    debug.all = lib.mkEnableOption "debug everything by default";
    debug.kresd = mkDebugOption { };
    debug.resolved = mkDebugOption { };
    # more verbose logging in `systemd-networkd`, doesn't seem to generate much logs at all
    debug.networkd = mkDebugOption { default = true; };
    debug.firewall = mkDebugOption { };
    debug.firewall-refused = mkDebugOption { default = with cfg.debug; firewall; };
    debug.firewall-icmpv6 = mkDebugOption { default = with cfg.debug; firewall; };
    debug.dhcp = mkDebugOption { };
    debug.dns = mkDebugOption { };
    debug.ddns = mkDebugOption { default = with cfg.debug; dns; };
    debug.kea-dhcp4 = mkDebugOption { default = with cfg.debug; dhcp; };
    debug.knot = mkDebugOption { default = with cfg.debug; ddns || dns; };
    debug.kea-dhcp-ddns = mkDebugOption { default = with cfg.debug; ddns || dhcp; };

    dropin.infix = lib.mkOption {
      type = with lib.types; str;
      # insert `cut -c-8 </proc/sys/kernel/random/uuid` for easier identification of managed files
      default = "kdn-router-35f45554";
    };

    unit.prefix = lib.mkOption {
      type = with lib.types; str;
      default = "50-";
    };

    forwardings = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (fwArgs: {
          options.from = lib.mkOption {
            type = with lib.types; str;
          };
          options.to = lib.mkOption {
            type = with lib.types; str;
          };
        })
      );
      default = [ ];
    };

    nets = lib.mkOption {
      type = lib.types.attrsOf netType;
      default = { };
    };

    dhcp-ddns.suffix = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };

    templates = lib.mkOption {
      description = ''
        Every secret-bearing file the router needs, in the shape of a secret renderer's own template
        option. The aspect writes this set and it reads each `path`. It renders nothing itself.

        A consumer maps the set into its own renderer with one line:

            sops.templates = config.kdn.networking.router.templates;

        The submodule mirrors the sops-nix template submodule key for key, so that line needs no
        translation. An adopter who uses a different renderer reads the same keys.
      '';
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options.name = lib.mkOption {
              type = lib.types.singleLineStr;
              default = config._module.args.name;
              description = "Name of the rendered file.";
            };
            options.path = lib.mkOption {
              type = lib.types.singleLineStr;
              default = "/run/secrets/rendered/${config.name}";
              description = "Path the renderer writes the file to.";
            };
            options.content = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = "Content of the file, with a placeholder per secret.";
            };
            options.mode = lib.mkOption {
              type = lib.types.singleLineStr;
              default = "0400";
              description = "Permission mode of the rendered file, in octal.";
            };
            options.owner = lib.mkOption {
              type = lib.types.nullOr lib.types.singleLineStr;
              default = null;
              description = "Owner of the rendered file.";
            };
            options.group = lib.mkOption {
              type = lib.types.nullOr lib.types.singleLineStr;
              default = null;
              description = "Group of the rendered file.";
            };
            options.restartUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Units the renderer restarts when the file changes.";
            };
            options.reloadUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Units the renderer reloads when the file changes.";
            };
          }
        )
      );
    };
  };

  config = lib.mkMerge [
    {
      networking.useDHCP = lib.mkDefault false;
      networking.networkmanager.enable = false;
      systemd.network.enable = true;

      kdn.disks.persist."sys/data".directories = [
        {
          directory = "/var/lib/systemd/network";
          user = "systemd-network";
          group = "systemd-network";
          mode = "0755";
        }
      ];

      systemd.network.config.networkConfig = {
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6PrivacyExtensions = true;
        SpeedMeter = true;
        SpeedMeterIntervalSec = 1;
        ManageForeignRoutes = false; # drops `ip route` on start since version 246
        ManageForeignRoutingPolicyRules = false; # drops `ip rule` on start  since version 249
        ManageForeignNextHops = false; # drops `ip nexthop` on start  since version 256
      };
      services.resolved.settings.Resolve.DNSSEC = "allow-downgrade";
      networking.nameservers = defaultDNSServers;
    }
    (
      let
        services = map (name: "${name}.service") [
          "kdn-knot-init"
          "knot"
          "kresd@"
          "systemd-networkd"
          "systemd-resolved"
          "kea-dhcp-ddns-server"
          "kea-dhcp4-server"
        ];
      in
      {
        systemd.targets.kdn-secrets.before = services;
        systemd.targets.kdn-secrets.wantedBy = services;
      }
    )
    # The old module writes this fix with no condition. The port adds the `pcscd` guard, because
    # inclusion is now the switch. A consumer that includes this aspect and runs no smart-card
    # daemon would otherwise get a `pcscd.service` stub with no `ExecStart`.
    (lib.mkIf config.services.pcscd.enable {
      # fixes circular dependency on systemd-resolved
      systemd.services.pcscd.unitConfig.DefaultDependencies = false;
      systemd.services.pcscd.after = [
        "local-fs.target"
      ];
      systemd.sockets.pcscd.unitConfig.DefaultDependencies = false;
      systemd.sockets.pcscd.after = [
        "local-fs.target"
      ];
    })
    {
      networking.nftables.enable = true;
      networking.firewall.enable = true;
      networking.firewall.allowPing = true;
      networking.firewall.filterForward = true;
      networking.firewall.logRefusedPackets = lib.mkDefault false;
      networking.firewall.logRefusedConnections = lib.mkDefault true;
      networking.firewall.pingLimit = "60/minute burst 5 packets";

      networking.firewall.extraForwardRules = ''
        ${lib.strings.concatMapStringsSep "\n" (
          fwd:
          ''meta iifname ${fwd.from} meta oifname ${fwd.to} accept comment "allow traffic from ${fwd.from} to ${fwd.to}"''
        ) cfg.forwardings}

        ${lib.optionalString config.networking.firewall.logRefusedConnections ''
          # Refused IPv4 connections get logged in the input filter due to NAT.
          # For IPv6 connections destined for some address in our LAN we end up
          # in the forward filter instead, so we log them here.
          tcp flags syn / fin,syn,rst,ack log level info prefix "refused connection: "
        ''}
      '';
    }
    (lib.mkIf cfg.debug.networkd {
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
    })
    (lib.mkIf cfg.debug.resolved {
      systemd.services.systemd-resolved.environment.SYSTEMD_LOG_LEVEL = "debug";
    })
    (lib.mkIf cfg.debug.firewall-refused {
      networking.firewall.logRefusedPackets = true;
      networking.firewall.rejectPackets = true;
    })
    (lib.mkIf cfg.debug.firewall-icmpv6 {
      networking.nftables.tables =
        let
          mkTable =
            {
              rule,
              name,
              family ? "ip6",
              priority ? "filter",
              chains ? [
                # "ingress" # doesn't seem to work
                "prerouting"
                "input"
                "forward"
                "output"
                "postrouting"
              ],
            }:
            lib.pipe chains [
              (map (hook: ''
                chain ${hook} {
                  type filter hook ${hook} priority ${priority}; policy accept;
                  ${rule} log level info prefix "[name=${name}][family=${family}][hook=${hook}]: "
                }
              ''))
              (builtins.concatStringsSep "\n")
              (content: { inherit family content; })
            ];
        in
        {
          logging-icpmv6-echo = mkTable {
            name = "ICMPv6:echo";
            rule = "icmpv6 type { echo-request, echo-reply }";
          };
          logging-icpmv6-ndp = mkTable {
            name = "ICMPv6:NDP";
            rule = "icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert }";
          };
        };
    })
    {
      # reloading networkd on drop-ins
      kdn.fs.watch.instances.systemd-networkd-reload = {
        files = [ "/etc/systemd/network" ];
        exec = [
          (lib.getExe' pkgs.systemd "networkctl")
          "reload"
        ];
      };
    }
    {
      # cleaning up managed files
      kdn.managed.infix.kdn-router = cfg.dropin.infix;
      kdn.managed.directories = [
        {
          path = "/etc/systemd/network";
          mindepth = 2;
          maxdepth = 2;
        }
      ];
    }
    {
      # Firewall/forwarding
      networking.firewall.trustedInterfaces = lib.pipe cfg.nets [
        builtins.attrValues
        (builtins.filter (netCfg: netCfg.firewall.trusted))
        (map (netCfg: netCfg.interface))
      ];
      networking.firewall.interfaces = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (
          _: netCfg: {
            "${netCfg.interface}" = {
              inherit (netCfg.firewall)
                allowedTCPPorts
                allowedTCPPortRanges
                allowedUDPPorts
                allowedUDPPortRanges
                ;
            };
          }
        ))
        lib.mkMerge
      ];
      kdn.networking.router.forwardings = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (
          _: netCfg:
          map (to: {
            from = netCfg.interface;
            inherit to;
          }) netCfg.forward.to
          ++ map (from: {
            inherit from;
            to = netCfg.interface;
          }) netCfg.forward.from
        ))
        builtins.concatLists
        lib.lists.unique
      ];
    }
    {
      # systemd-networkd + drop-ins
      systemd.network.netdevs = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (
          _: netCfg: {
            "${netCfg.unit.name}" = lib.mkMerge [
              {
                # see https://wiki.archlinux.org/title/Systemd-networkd#Bonding_a_wired_and_wireless_interface
                netdevConfig = {
                  Kind = netCfg.netdev.kind;
                  Name = netCfg.interface;
                };
              }
              (lib.mkIf (netCfg.netdev.kind == "bond" && netCfg.netdev.bond.mode == "backup") {
                bondConfig = {
                  Mode = "active-backup";
                  PrimaryReselectPolicy = "always";
                  MIIMonitorSec = "1s";
                };
              })
              (lib.mkIf (netCfg.netdev.kind == "bond" && netCfg.netdev.bond.mode == "aggregate") {
                bondConfig = {
                  Mode = "802.3ad";
                  TransmitHashPolicy = "encap3+4";
                  LACPTransmitRate = "fast";
                  MIIMonitorSec = "100ms";
                };
              })
              (lib.mkIf (netCfg.netdev.kind == "vlan") {
                vlanConfig = {
                  Id = netCfg.vlan.id;
                };
              })
            ];
          }
        ))
        lib.mkMerge
      ];
      systemd.network.networks = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (
          _: netCfg:
          lib.mkMerge [
            {
              "${netCfg.unit.name}" = lib.mkMerge [
                {
                  matchConfig.Name = netCfg.interface;
                  linkConfig = {
                    Multicast = true;
                    RequiredForOnline = "routable";
                  };
                  networkConfig = {
                    DHCPServer = lib.mkDefault false;
                    DHCP = lib.mkDefault false;
                    IPv6AcceptRA = lib.mkDefault false;
                    IPv6SendRA = lib.mkDefault false;
                    MulticastDNS = lib.mkDefault false;
                    LinkLocalAddressing = "ipv6";

                    IPv6PrivacyExtensions = lib.mkDefault true;
                    IPv6LinkLocalAddressGenerationMode = lib.mkDefault "stable-privacy";
                  };
                }
                (lib.mkIf (netCfg.type == "wan") {
                  networkConfig = {
                    IPMasquerade = "ipv4";
                  };
                })
                (lib.mkIf (netCfg.type == "lan") (
                  lib.mkMerge [
                    {
                      networkConfig = {
                        IPMasquerade = "ipv4";
                        MulticastDNS = true;
                      };
                    }
                    (lib.mkIf (netCfg.ra.implementation == "networkd") {
                      networkConfig = {
                        # for DHCPv6-PD to work I would need to have `IPv6AcceptRA=true` on `wan`
                        DHCPPrefixDelegation = false;
                        IPv6SendRA = true;
                      };
                      ipv6SendRAConfig = {
                        Managed = true;
                        EmitDNS = true;
                        UplinkInterface = netCfg.lan.uplink;
                      };
                    })
                  ]
                ))
                (lib.mkIf (netCfg.netdev.kind == "bond") {
                  networkConfig = {
                    BindCarrier = builtins.concatStringsSep " " netCfg.interfaces;
                  };
                })
                (lib.mkIf (netCfg.netdev.kind == "bridge") {
                  networkConfig = {
                    ConfigureWithoutCarrier = true;
                  };
                })
              ];
            }
            (
              let
                mkInterfaces =
                  kind: ifaceCfg:
                  lib.mkIf (netCfg.netdev.kind == kind) (
                    lib.pipe netCfg.interfaces [
                      (lib.lists.imap0 (
                        idx: iface: {
                          name = getInterfaceUnit iface;
                          value = lib.mkMerge [
                            { matchConfig.Name = lib.mkDefault iface; }
                            (ifaceCfg idx iface)
                          ];
                        }
                      ))
                      builtins.listToAttrs
                    ]
                  );
              in
              lib.mkMerge [
                (mkInterfaces "bridge" (
                  idx: iface: {
                    networkConfig.Bridge = netCfg.interface;
                    linkConfig.RequiredForOnline = "enslaved";
                  }
                ))
                (mkInterfaces "bond" (
                  idx: iface: {
                    networkConfig = lib.mkMerge [
                      {
                        Bond = netCfg.interface;
                      }
                      (lib.mkIf (netCfg.netdev.bond.mode == "backup") {
                        PrimarySlave = idx == 0;
                      })
                    ];
                  }
                ))
                (mkInterfaces "vlan" (
                  idx: iface: {
                    networkConfig.VLAN = [ netCfg.interface ];
                  }
                ))
              ]
            )
          ]
        ))
        lib.mkMerge
      ];
      kdn.networking.router.templates = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (
          _: netCfg:
          let
            _path = mkDropInPath "${netCfg.unit.name}.network" "50-template";
          in
          {
            "${_path}" = {
              path = _path;
              mode = "0644";
              content = netCfg.template.network._text;
            };
          }
        ))
        lib.mkMerge
      ];
    }
  ];
}
