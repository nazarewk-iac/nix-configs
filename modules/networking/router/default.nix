{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.networking.router;

  mkDropInDir = unit: "/etc/systemd/network/${unit}.d";
  mkDropInPath = unit: name: "${mkDropInDir unit}/${cfg.dropin.infix}-${name}.conf";

  getInterfaceUnit = iface: lib.attrsets.attrByPath [ iface "unit" "name" ] "${cfg.unit.prefix}${iface}" cfg.nets;

  ports.dns.default = 53;
  ports.dns.tls = 853;
  ports.mdns = 5353;
  ports.dhcp.v4-request = 67;
  ports.dhcp.v4-reply = 68;
  ports.dhcp.v6-request = 546;
  ports.dhcp.v6-reply = 547;

  templateType = lib.types.submodule (tpl:
    let
      leafType = with lib.types; oneOf [ str bool int path ];
      toString = value: (
        {
          bool = builtins.toJSON;
        }."${builtins.typeOf value}" or builtins.toString
      ) value;
      sectionType = with lib.types; attrsOf (attrsOf (coercedTo
        (either (listOf leafType) leafType)
        (value: lib.pipe value [
          lib.lists.toList
          (builtins.map toString)
        ])
        (listOf str)
      ));
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
        readOnly = true;
        type = with lib.types; str;
        default =
          let
            sections = [{ name = "values"; value = tpl.config.values; }] ++ (lib.attrsets.mapAttrsToList lib.attrsets.nameValuePair tpl.config.sections);

            renderSection = sectionName: entries: lib.pipe entries [
              (lib.attrsets.mapAttrsToList (key: builtins.map (value: "${key}=${value}")))
              builtins.concatLists
              (lines: [ "[${sectionName}]" lines ])
            ];
          in
          lib.pipe sections [
            (builtins.map (sec: lib.pipe sec.value [
              (lib.attrsets.mapAttrsToList renderSection)
              lib.lists.flatten
              (sections: [
                "###"
                "## [BEGIN] SECTION: ${sec.name}"
                "#"
                ""
              ] ++ sections ++ [
                ""
                "#"
                "## [END  ] SECTION: ${sec.name}"
                "###"
              ])
              (builtins.concatStringsSep "\n")
            ]))
            (builtins.concatStringsSep "\n\n\n")
          ];
      };
    });
in
{
  options.kdn.networking.router = {
    enable = lib.mkEnableOption "systemd-networkd based router";

    debug = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };

    dropin.infix = lib.mkOption {
      type = with lib.types; str;
      # insert `cut -c-8 </proc/sys/kernel/random/uuid` for easier identification of managed files
      default = "kdn-router-35f45554";
    };

    unit.prefix = lib.mkOption {
      type = with lib.types; str;
      default = "50-";
    };

    reloadOnDropIns = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    forwardings = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule (fwArgs: {
        options.from = lib.mkOption {
          type = with lib.types; str;
        };
        options.to = lib.mkOption {
          type = with lib.types; str;
        };
      }));
      default = [ ];
    };

    nets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@netArgs:
        let netCfg = netArgs.config; in {
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
              type = with lib.types; enum [ "wan" "lan" ];
            };
            netdev.kind = lib.mkOption {
              type = with lib.types; enum [ "bond" "bridge" "vlan" ];
              default = { wan = "bond"; vlan = "vlan"; }.${netCfg.type} or "bridge";
            };
            vlan.id = lib.mkOption {
              type = with lib.types; ints.between 1 4095;
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
            wan.dns = lib.mkOption {
              type = with lib.types; listOf str;
            };
            wan.gateway = lib.mkOption {
              type = with lib.types; listOf str;
            };
            address = lib.mkOption {
              type = with lib.types; listOf str;
            };
            prefix = lib.mkOption {
              type = with lib.types; attrsOf str;
              default = { };
            };
            template.network = lib.mkOption {
              type = templateType;
              default = { };
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
                Address = netCfg.address;
              };
            }
            (lib.mkIf (netCfg.type == "wan") {
              template.network.values.Network = {
                DNS = netCfg.wan.dns;
                Gateway = netCfg.wan.gateway;
              };
              template.network.sections = lib.attrsets.mapAttrs'
                (name: prefix: {
                  name = "prefix-${name}";
                  value.IPv6Prefix = {
                    Prefix = prefix;
                    OnLink = true;
                    AddressAutoconfiguration = false;
                    Assign = false;
                  };
                })
                netCfg.prefix;
            })
            (lib.mkIf (netCfg.type == "lan") {
              forward.to = [ netCfg.lan.uplink ];
              template.network.values = {
                DHCPServer = {
                  # this value is not supported yet by NixOS
                  PersistLeases = true;
                };
              };
              template.network.sections = lib.attrsets.mapAttrs'
                (name: prefix: {
                  name = "prefix-${name}";
                  value.IPv6Prefix = {
                    Prefix = prefix;
                    OnLink = true;
                    AddressAutoconfiguration = true;
                    Assign = false;
                  };
                })
                netCfg.prefix;

              firewall =
                let
                in
                {
                  allowedTCPPorts = [
                    ports.mdns
                  ]
                  ++ builtins.attrValues ports.dns
                  ;
                  allowedUDPPorts = [
                    ports.mdns
                  ]
                  ++ builtins.attrValues ports.dns
                  ++ builtins.attrValues ports.dhcp
                  ;
                };
            })
          ];
        }));
      default = { };
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      networking.useNetworkd = true;
      networking.useDHCP = false;
      networking.networkmanager.enable = false;
      systemd.network.enable = true;

      environment.persistence."sys/data".directories = [
        { directory = "/var/lib/systemd/network"; user = "systemd-network"; group = "systemd-network"; mode = "0755"; }
      ];

      systemd.network.config.networkConfig = {
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6PrivacyExtensions = true;
        SpeedMeter = true;
        SpeedMeterIntervalSec = 1;
        # When true, systemd-networkd will remove routes that are not configured in .network files
        #ManageForeignRoutes = false;
      };
    }
    {
      networking.nftables.enable = true;
      networking.firewall.enable = true;
      networking.firewall.allowPing = true;
      networking.firewall.filterForward = true;
      networking.firewall.logRefusedPackets = lib.mkDefault false;
      networking.firewall.logRefusedConnections = true;
      networking.firewall.pingLimit = "60/minute burst 5 packets";

      kdn.networking.router.forwardings = [
        { from = "nb-priv"; to = "lan"; }
      ];

      # more verbose logging in `systemd-networkd`, doesn't seem to generate much logs at all
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";

      networking.firewall.extraForwardRules = ''
        ${lib.strings.concatMapStringsSep "\n" (fwd:
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
    (lib.mkIf cfg.debug {
      networking.firewall.logRefusedPackets = true;
      networking.firewall.rejectPackets = true;

      networking.nftables.tables =
        let
          mkTable =
            { rule
            , name
            , family ? "ip6"
            , priority ? "filter"
            , chains ? [
                # "ingress" # doesn't seem to work
                "prerouting"
                "input"
                "forward"
                "output"
                "postrouting"
              ]
            }: lib.pipe chains [
              (builtins.map (hook: ''
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
    (
      let debounceSec = "3"; in {
        systemd.paths."kdn-systemd-networkd-reload" = {
          description = "reloads systemd-networkd on external configuration changes";
          wantedBy = [ "systemd-networkd.service" ];
          after = [ "systemd-networkd.service" ];
          pathConfig.PathChanged = builtins.map mkDropInDir cfg.reloadOnDropIns;
          pathConfig.TriggerLimitIntervalSec = "${debounceSec}s";
          pathConfig.TriggerLimitBurst = 1;
        };
        systemd.services."kdn-systemd-networkd-reload" = {
          description = "reloads systemd-networkd on external configuration changes";
          serviceConfig.Type = "oneshot";
          script = ''
            set -xeEuo pipefail
            PATH="${lib.makeBinPath (with pkgs; [ coreutils systemd ])}:$PATH"

            sleep ${debounceSec}
            systemctl try-reload-or-restart systemd-networkd.service
          '';
        };
        system.activationScripts.renderSecrets.deps = [ "kdnRouterCleanDropIns" ];
        system.activationScripts.kdnRouterCleanDropIns =
          let
            existing = lib.pipe config.sops.templates [
              builtins.attrValues
              (builtins.map (tpl: tpl.path))
              (builtins.filter (lib.strings.hasPrefix "/etc/systemd/network"))
              (builtins.map (path: [ "!" "-path" path ]))
              lib.lists.flatten
            ];
          in
          ''
            echo 'Cleaning up managed systemd-networkd drop-ins...'
            ${lib.getExe pkgs.findutils} \
              /etc/systemd/network -mindepth 2 -maxdepth 2 \
              -type f -name '*${cfg.dropin.infix}*.conf' \
              ${lib.escapeShellArgs existing} \
              -printf '> removed: %p\n' -delete
          '';
      }
    )
    {
      networking.firewall.trustedInterfaces = lib.pipe cfg.nets [
        builtins.attrValues
        (builtins.filter (netCfg: netCfg.firewall.trusted))
        (builtins.map (netCfg: netCfg.name))
      ];
      networking.firewall.interfaces = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: {
          "${netCfg.name}" = {
            inherit (netCfg.firewall)
              allowedTCPPorts
              allowedTCPPortRanges
              allowedUDPPorts
              allowedUDPPortRanges
              ;
          };
        }))
        lib.mkMerge
      ];
      kdn.networking.router.forwardings = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg:
          builtins.map (to: { from = netCfg.name; inherit to; }) netCfg.forward.to
          ++ builtins.map (from: { inherit from; to = netCfg.name; }) netCfg.forward.from
        ))
        builtins.concatLists
        lib.lists.unique
      ];
      kdn.networking.router.reloadOnDropIns = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: [ "${netCfg.name}.netdev" "${netCfg.name}.network" ]))
        builtins.concatLists
        lib.lists.unique
      ];
      systemd.network.netdevs = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: {
          "${netCfg.unit.name}" = {
            # see https://wiki.archlinux.org/title/Systemd-networkd#Bonding_a_wired_and_wireless_interface
            netdevConfig = {
              Kind = netCfg.netdev.kind;
              Name = netCfg.name;
            };
            bondConfig = lib.mkIf (netCfg.netdev.kind == "bond") {
              Mode = "active-backup";
              PrimaryReselectPolicy = "always";
              MIIMonitorSec = "1s";
            };
            vlanConfig = lib.mkIf (netCfg.netdev.kind == "vlan") {
              Id = netCfg.vlan.id;
            };
          };
        }))
        lib.mkMerge
      ];
      systemd.network.networks = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: lib.mkMerge [
          {
            "${netCfg.unit.name}" = lib.mkMerge [
              {
                matchConfig.Name = netCfg.name;
                linkConfig = {
                  Multicast = true;
                  RequiredForOnline = "routable";
                };
                networkConfig = {
                  DHCP = lib.mkDefault false;
                  IPv6AcceptRA = lib.mkDefault false;
                  LinkLocalAddressing = "ipv6";

                  IPv6PrivacyExtensions = true;
                  IPv6LinkLocalAddressGenerationMode = "stable-privacy";
                };
              }
              (lib.mkIf (netCfg.type == "wan") {
                networkConfig = {
                  IPMasquerade = "ipv4";
                  IPv6SendRA = false;
                  MulticastDNS = false;
                };
              })
              (lib.mkIf (netCfg.type == "lan") {
                networkConfig = {
                  # IPv4
                  DHCPServer = true;
                  IPMasquerade = "ipv4";
                  # IPv6
                  # for DHCPv6-PD to work I would need to have `IPv6AcceptRA=true` on `wan`
                  DHCPPrefixDelegation = false;
                  IPv6AcceptRA = false;
                  IPv6SendRA = true;
                  # misc
                  MulticastDNS = true;
                  #Gateway = "_ipv6ra"; # doesn't seem to change anything
                };
                dhcpServerConfig = {
                  EmitDNS = true;
                  PoolOffset = 32;
                };
                ipv6SendRAConfig = {
                  Managed = true;
                  EmitDNS = true;
                  UplinkInterface = netCfg.lan.uplink;
                };
              })
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
          (lib.mkIf (builtins.elem netCfg.netdev.kind [ "bond" "bridge" ]) (lib.pipe netCfg.interfaces [
            (lib.lists.imap0 (idx: iface: {
              name = getInterfaceUnit iface;
              value = lib.mkMerge [
                { matchConfig.Name = iface; }
                (lib.mkIf (netCfg.netdev.kind == "bond") {
                  networkConfig = {
                    Bond = netCfg.name;
                    PrimarySlave = idx == 0;
                  };
                })
                (lib.mkIf (netCfg.netdev.kind == "bridge") {
                  networkConfig = {
                    Bridge = netCfg.name;
                  };
                  linkConfig = {
                    RequiredForOnline = "enslaved";
                  };
                })
              ];
            }))
            builtins.listToAttrs
          ]))
          (lib.mkIf (netCfg.netdev.kind == "vlan") (lib.pipe netCfg.interfaces [
            (builtins.map (parent: {
              name = getInterfaceUnit parent;
              value = {
                networkConfig.VLAN = [ netCfg.name ];
              };
            }))
            builtins.listToAttrs
          ]))
        ]))
        lib.mkMerge
      ];
      sops.templates = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg:
          let path = mkDropInPath "${netCfg.unit.name}.network" "50-template"; in {
            "${path}" = {
              inherit path;
              mode = "0644";
              content = netCfg.template.network.text;
            };
          }))
        lib.mkMerge
      ];
    }
  ]);
}
