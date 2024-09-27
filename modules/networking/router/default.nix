{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.networking.router;
  hostname = config.networking.hostName;

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

  knotKeys = config.kdn.security.secrets.placeholders.default.knot-dns.keys;
  keaTSIGName = "kea.${hostname}";

  defaultDNSServers = lib.pipe cfg.nets [
    builtins.attrValues
    (builtins.filter (netCfg: netCfg.type == "wan" && netCfg.wan.asDefaultDNS))
    (builtins.map (netCfg: netCfg.wan.dns))
    builtins.concatLists
  ];

  kdn-router-knot-setup-zone = pkgs.writeShellApplication {
    name = "kdn-router-knot-setup-zone";
    runtimeInputs = [
      config.services.knot.package
    ] ++ (with pkgs; [
      coreutils
      gnused
    ]);
    runtimeEnv.TSIG_KEY_PATH = config.sops.templates."knot/sops-key.admin.conf".path;
    runtimeEnv.KNOT_ADDR = cfg.knot.localAddress;
    runtimeEnv.KNOT_PORT = builtins.toString cfg.knot.localPort;
    runtimeEnv.PUBLIC_IPV4_PATH = cfg.addr.public.ipv4.path;
    runtimeEnv.PUBLIC_IPV6_PATH = cfg.addr.public.ipv6.path;
    text = builtins.readFile ./kdn-router-knot-setup-zone.sh;
  };

  kdn-router-knot-ddns-update = pkgs.writeShellApplication {
    name = "kdn-router-knot-ddns-update";
    runtimeInputs = [
      config.services.knot.package
    ] ++ (with pkgs; [
      coreutils
      gnused
    ]);
    runtimeEnv.TSIG_KEY_PATH = config.sops.templates."knot/sops-key.admin.conf".path;
    runtimeEnv.KNOT_ADDR = cfg.knot.localAddress;
    runtimeEnv.KNOT_PORT = builtins.toString cfg.knot.localPort;
    text = builtins.readFile ./kdn-router-knot-ddns-update.sh;
  };

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
        type = with lib.types; str;
        default = "";
      };

      options._text = lib.mkOption {
        readOnly = true;
        type = with lib.types; str;
        default =
          let
            sections =
              [{ name = "values"; value = tpl.config.values; }]
              ++ (lib.attrsets.mapAttrsToList lib.attrsets.nameValuePair tpl.config.sections)
            ;

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
            ]))
            (builtins.concatStringsSep "\n\n\n")
            (txt: ''
              ${txt}

              ${tpl.config.text}
            '')
          ];
      };
    });

  netType = lib.types.submodule ({ name, ... }@netArgs:
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
        netdev.bond.mode = lib.mkOption {
          type = with lib.types; enum [ "backup" "aggregate" ];
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
        };
        prefix = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
        };
        domain = lib.mkOption {
          type = with lib.types; nullOr str;
          default =
            if cfg.dhcp-ddns.suffix == null then null
            else "${netCfg.name}.${config.networking.hostName}.${cfg.dhcp-ddns.suffix}";
          apply = domain:
            assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
              `kdn.networking.router.nets.*.domain` must end with a '.': ${domain}
            ''; domain;
        };
        template.network = lib.mkOption {
          type = templateType;
          default = { };
        };
        addressing = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule (addrArgs:
            let addrCfg = addrArgs.config; in {
              options = {
                enable = lib.mkOption {
                  type = with lib.types; bool;
                  default = true;
                };
                type = lib.mkOption {
                  type = with lib.types; enum [ "ipv4" "ipv6" ];
                  default = if lib.strings.hasInfix ":" addrCfg.network then "ipv6" else "ipv4";
                };
                id = lib.mkOption {
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
                  type = lib.types.attrsOf (lib.types.submodule (poolArgs: {
                    options = {
                      start = lib.mkOption {
                        type = with lib.types; str;
                      };
                      end = lib.mkOption {
                        type = with lib.types; str;
                      };
                    };
                  }));
                };
                hosts = lib.mkOption {
                  type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@hostArgs: {
                    options = {
                      hostname = lib.mkOption {
                        type = with lib.types; str;
                        default = hostArgs.name;
                      };
                      ip = lib.mkOption {
                        type = with lib.types; str;
                      };
                      ident = lib.mkOption {
                        type = with lib.types; attrsOf str;
                        default = { };
                      };
                    };
                  }));
                  default = { };
                };
              };
            }));
          default = { };
        };
        ra.implementation = lib.mkOption {
          type = with lib.types; enum [
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
            Address = netCfg.address ++ lib.pipe netCfg.addressing [
              builtins.attrValues
              (builtins.map (addrCfg: ''${addrCfg.hosts."${hostname}".ip}/${addrCfg.netmask}''))
            ];
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
        (lib.mkIf (netCfg.type == "lan") (lib.mkMerge [
          {
            forward.to = [ netCfg.lan.uplink ];
            firewall =
              let
              in
              {
                allowedTCPPorts =
                  [
                    ports.mdns
                  ]
                  ++ builtins.attrValues ports.dns
                ;
                allowedUDPPorts =
                  [
                    ports.mdns
                  ]
                  ++ builtins.attrValues ports.dns
                  ++ builtins.attrValues ports.dhcp
                ;
              };
            template.network.sections = lib.mkMerge [
              (lib.attrsets.mapAttrs'
                (name: prefix: {
                  name = "prefix-${name}";
                  value.IPv6Prefix = {
                    Prefix = prefix;
                    OnLink = true;
                    AddressAutoconfiguration = true;
                    Assign = false;
                  };
                })
                netCfg.prefix)
            ];
          }
        ]))
      ];
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

    addr.public.ipv4.path = lib.mkOption {
      type = with lib.types; path;
    };
    addr.public.ipv6.path = lib.mkOption {
      type = with lib.types; path;
    };

    dhcpv4.implementation = lib.mkOption {
      type = with lib.types; enum [
        "networkd"
        "kea"
      ];
      default = "kea";
    };
    dhcpv6.implementation = lib.mkOption {
      type = with lib.types; enum [
        null
        "networkd"
        "kea"
      ];
      default = null;
    };

    kea.dhcp4.settings = lib.mkOption {
      type = pkgs.jsonTemplate.type;
      default = { };
    };
    kea.dhcp6.settings = lib.mkOption {
      type = pkgs.jsonTemplate.type;
      default = { };
    };
    kea.dhcp-ddns.settings = lib.mkOption {
      type = pkgs.jsonTemplate.type;
      default = { };
    };
    kea.ctrl-agent.settings = lib.mkOption {
      type = pkgs.jsonTemplate.type;
      default = { };
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
      type = lib.types.attrsOf netType;
      default = { };
    };

    domains = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@domainArgs: {
        options = {
          name = lib.mkOption {
            readOnly = true;
            type = with lib.types; str;
            default = domainArgs.name;
            apply = domain:
              assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
                `kdn.networking.router.domains` must end with a '.', invalid enty: ${domain}
              ''; domain;
          };
        };
      }));
      default = { };
    };

    dhcp-ddns.suffix = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };

    knot.localAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.1";
    };
    knot.localPort = lib.mkOption {
      type = with lib.types; port;
      default = 53;
    };
    knot.localPortTLS = lib.mkOption {
      type = with lib.types; port;
      default = 853;
    };

    knot.listens = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      apply = value: lib.pipe value [
        (v: [ (if cfg.knot.localPort == 53 then cfg.knot.localAddress else "${cfg.knot.localAddress}@${builtins.toString cfg.knot.localPort}") ] ++ v)
        lib.lists.unique
      ]
      ;
    };

    knot.configDir = lib.mkOption {
      type = with lib.types; path;
      default = "/etc/knot/knot.conf.d";
    };
    knot.dataDir = lib.mkOption {
      type = with lib.types; path;
      default = "/var/lib/knot";
    };

    coredns.localAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.2";
    };

    kresd.logLevel = lib.mkOption {
      type = with lib.types; enum [
        "info"
        "debug"
      ];
      default = "info";
    };

    kresd.interfaces = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    kresd.localAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.3";
    };

    kresd.rewrites = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@rewriteArgs: {
        options = {
          to = lib.mkOption {
            type = with lib.types; str;
            default = name;
          };

          from = lib.mkOption {
            type = with lib.types; str;
          };

          upstreams = lib.mkOption {
            type = with lib.types; listOf str;
          };
        };
      }));
    };
    kresd.defaultUpstream = lib.mkOption {
      type = with lib.types; nullOr (enum [ "systemd-resolved" "google" "cloudflare" "quad9" ]);
      default = "systemd-resolved";
    };

    kresd.upstreams = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule (upstreamArgs: {
        options = {
          enable = lib.mkOption {
            type = with lib.types; bool;
            default = true;
          };
          description = lib.mkOption {
            type = with lib.types; str;
          };
          nameservers = lib.mkOption {
            type = with lib.types; listOf str;
          };
          nameserversRaw = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ ];
          };
          domains = lib.mkOption {
            type = with lib.types; nullOr (listOf str);
            default = null;
          };
          type = lib.mkOption {
            type = with lib.types; enum [ "STUB" "FORWARD" "TLS_FORWARD" ];
          };
          flags = lib.mkOption {
            type = with lib.types; listOf (enum [
              # see https://knot-resolver.readthedocs.io/en/stable/lib.html#c.kr_qflags
              "NO_IPV6"
              "NO_EDNS"
              "NO_0X20" # DNS lettercase randomization
              "NO_CACHE"
            ]);
            default = [ ];
          };
          auth = lib.mkOption {
            type = with lib.types; attrsOf str;
            default = { };
          };
        };
      }));
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
      services.resolved.dnssec = "allow-downgrade";
      networking.nameservers = defaultDNSServers;
    }
    {
      networking.nftables.enable = true;
      networking.firewall.enable = true;
      networking.firewall.allowPing = true;
      networking.firewall.filterForward = true;
      networking.firewall.logRefusedPackets = lib.mkDefault false;
      networking.firewall.logRefusedConnections = lib.mkDefault true;
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
      kdn.networking.router.kresd.logLevel = "debug";
      networking.firewall.logRefusedPackets = true;
      networking.firewall.rejectPackets = true;
      systemd.services.systemd-resolved.environment.SYSTEMD_LOG_LEVEL = "debug";

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
    {
      # reloading on drop-ins
      systemd.services."systemd-networkd" = {
        reloadTriggers = lib.pipe config.sops.templates [
          builtins.attrValues
          (builtins.map (tpl: tpl.path))
          (builtins.filter (lib.strings.hasPrefix "/etc/systemd/network"))
        ];
        reload = ''
          set -x
          ${lib.getExe' pkgs.systemd "networkctl"} reload
        '';
      };
    }
    {
      # cleaning up managed files
      kdn.managed.infix.kdn-router = cfg.dropin.infix;
      kdn.managed.directories = [
        { path = "/etc/systemd/network"; mindepth = 2; maxdepth = 2; }
        "/etc/knot-resolver"
        cfg.knot.configDir
      ];
    }
    {
      # Kea DHCPv4
      services.kea = {
        dhcp4.enable = true;
      };
      kdn.networking.router = {
        kea.dhcp4.settings = lib.pipe cfg.nets [
          builtins.attrValues
          (builtins.filter (netCfg: netCfg.type == "lan"))
          (builtins.map (netCfg: {
            interfaces-config.interfaces = [ netCfg.interface ];
            subnet4 = lib.pipe netCfg.addressing [
              builtins.attrValues
              (builtins.filter (addrCfg: addrCfg.enable && addrCfg.type == "ipv4"))
              (builtins.map (addrCfg: {
                id = addrCfg.id;
                interface = netCfg.interface;
                subnet = with addrCfg; "${network}/${netmask}";
                pools = lib.pipe addrCfg.pools [
                  builtins.attrValues
                  (builtins.map (pool: { pool = with pool; "${start} - ${end}"; }))
                ];
                option-data = [
                  { name = "domain-name"; data = netCfg.domain; }
                  { name = "domain-name-servers"; data = addrCfg.hosts."${hostname}".ip; }
                  { name = "domain-search"; data = netCfg.domain; }
                  { name = "routers"; data = addrCfg.hosts."${hostname}".ip; }
                ];
                reservations = lib.pipe addrCfg.hosts [
                  builtins.attrValues
                  (builtins.filter (host: host.ident != { }))
                  (builtins.map (host: host.ident // {
                    hostname = host.hostname;
                    ip-address = host.ip;
                  }))
                ];
                ddns-send-updates = true;
                ddns-qualifying-suffix = netCfg.domain;
              }))
            ];
          }))
          (p: p ++ [{
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
              name = "/var/lib/private/kea/dhcp4.leases";
            };
            loggers = [{
              name = "kea-dhcp4";
              severity = if cfg.debug then "DEBUG" else "INFO";
              debuglevel = 99;
              output_options = [{ output = "stderr"; }];
            }];
          }])
          lib.mkMerge
        ];
      };
    }
    {
      # kea configuration plumbing
      services.kea = {
        ctrl-agent.configFile = config.sops.templates."kea/ctrl-agent.conf".path;
        dhcp-ddns.configFile = config.sops.templates."kea/dhcp-ddns.conf".path;
        dhcp4.configFile = config.sops.templates."kea/dhcp4.conf".path;
        dhcp6.configFile = config.sops.templates."kea/dhcp6.conf".path;
      };
      systemd.services = lib.mkMerge [
        (lib.mkIf config.services.kea.ctrl-agent.enable {
          kea-ctrl-agent.restartTriggers = [ config.sops.templates."kea/ctrl-agent.conf".path ];
        })
        (lib.mkIf config.services.kea.dhcp-ddns.enable {
          # TODO: this doesn't seem to work?
          kea-dhcp-ddns-server.restartTriggers = [ config.sops.templates."kea/dhcp-ddns.conf".path ];
        })
        (lib.mkIf config.services.kea.dhcp4.enable {
          kea-dhcp4-server.restartTriggers = [ config.sops.templates."kea/dhcp4.conf".path ];
        })
        (lib.mkIf config.services.kea.dhcp6.enable {
          kea-dhcp6-server.restartTriggers = [ config.sops.templates."kea/dhcp6.conf".path ];
        })
      ];
      sops.templates."kea/dhcp6.conf" = {
        mode = "0444";
        content = builtins.readFile (pkgs.jsonTemplate.generate "kea-dhcp6.conf" {
          Dhcp6 = cfg.kea.dhcp6.settings;
        });
      };
      sops.templates."kea/ctrl-agent.conf" = {
        mode = "0444";
        content = builtins.readFile (pkgs.jsonTemplate.generate "kea-ctrl-agent.conf" {
          Control-agent = cfg.kea.ctrl-agent.settings;
        });
      };
      sops.templates."kea/dhcp-ddns.conf" = {
        mode = "0444";
        content = builtins.readFile (pkgs.jsonTemplate.generate "kea-dhcp-ddns.conf" {
          DhcpDdns = cfg.kea.dhcp-ddns.settings;
        });
      };
      sops.templates."kea/dhcp4.conf" = {
        mode = "0444";
        content = builtins.readFile (pkgs.jsonTemplate.generate "kea-dhcp4.conf" {
          Dhcp4 = cfg.kea.dhcp4.settings;
        });
      };
    }
    {
      # kresd DNS resolver
      environment.systemPackages = [
        config.services.knot.package # contains `kdig`
      ];
      services.kresd.enable = true;
      services.kresd.listenPlain = [ ];
      services.kresd.package = (pkgs.knot-resolver.override {
        extraFeatures = true;
      }).overrideAttrs (old: {
        buildInputs = old.buildInputs ++ (with pkgs.luajitPackages; [
          luafilesystem
        ]);
      });
      kdn.networking.router.kresd.interfaces = lib.pipe cfg.nets [
        builtins.attrValues
        (builtins.filter (netCfg: netCfg.type == "lan"))
        (builtins.map (netCfg: netCfg.interface))
      ];

      # logging functions are available at https://gitlab.nic.cz/knot/knot-resolver/-/blob/v5.7.4/daemon/lua/sandbox.lua.in#L63
      services.kresd.extraConfig = builtins.readFile ./kresd.conf.lua;
      systemd.services."kresd@".environment.KRESD_CONF_DIR = "/etc/knot-resolver";
      systemd.services."kresd@".restartTriggers = lib.pipe config.sops.templates [
        builtins.attrValues
        (builtins.map (tpl: tpl.path))
        (builtins.filter (lib.strings.hasPrefix "/etc/knot-resolver"))
      ];
      environment.persistence."sys/data".directories = [
        { directory = "/var/lib/knot-resolver"; user = "knot-resolver"; group = "knot-resolver"; mode = "0770"; }
      ];
      environment.persistence."sys/cache".directories = [
        { directory = "/var/cache/knot-resolver"; user = "knot-resolver"; group = "knot-resolver"; mode = "0770"; }
      ];
    }
    {
      services.kresd.extraConfig = lib.pipe [
        "log_level(${builtins.toJSON cfg.kresd.logLevel})"
        (lib.pipe cfg.kresd.upstreams [
          (builtins.map (upstreamCfg:
            let
              toLuaTable = value: lib.pipe value [
                (builtins.concatStringsSep ", ")
                (e: "{${e}}")
              ];
              toLuaStringList = list: toLuaTable (builtins.map builtins.toJSON list);
              authArgsList = lib.attrsets.mapAttrsToList (key: value: "${key}=${builtins.toJSON value}") upstreamCfg.auth;

              nameserverEntries = upstreamCfg.nameserversRaw ++ builtins.map builtins.toJSON upstreamCfg.nameservers;
              tlsNameserversArg = lib.pipe nameserverEntries [
                (builtins.map (ns: lib.pipe ns [
                  (ns: [ ns ] ++ authArgsList)
                  (prev: if builtins.length prev > 1 then toLuaTable prev else builtins.head prev)
                ]))
                toLuaTable
              ];
              domainsArg = lib.pipe upstreamCfg.domains [
                (builtins.map builtins.toJSON)
                toLuaTable
              ];
              descriptionSnippet = lib.pipe upstreamCfg.description [
                (lib.strings.splitString "\n")
                (builtins.map (line: "-- ${line}"))
                (builtins.concatStringsSep "\n")
              ];
              policyFilter = if upstreamCfg.domains == null then "all" else "suffix";
              actionArgs =
                if upstreamCfg.type == "TLS_FORWARD"
                then tlsNameserversArg
                else toLuaTable nameserverEntries;

              domainPolicyArgs = lib.lists.optional (upstreamCfg.domains != null) "policy.todnames(${domainsArg})";
            in
            builtins.concatStringsSep "\n" (
              [
                descriptionSnippet
              ]
              ++ lib.optionals (upstreamCfg.flags != [ ]) [
                "policy.add(policy.${policyFilter}("
                (builtins.concatStringsSep ", " (
                  [ "  policy.FLAGS(${toLuaStringList upstreamCfg.flags})" ] ++ domainPolicyArgs
                ))
                "))"
              ]
              ++ lib.optionals (nameserverEntries != [ ]) [
                "policy.add(policy.${policyFilter}("
                (builtins.concatStringsSep ", " (
                  [ "  policy.${upstreamCfg.type}(${actionArgs})" ] ++ domainPolicyArgs
                ))
                "))"
              ]
            )))
        ])
        ''net.listen(${builtins.toJSON cfg.kresd.localAddress}, 53, { kind = 'dns', freebind = true })''
        (builtins.map (iface: ''net.listen(net[${builtins.toJSON iface}], 53, { kind = 'dns', freebind = true })'') cfg.kresd.interfaces)
      ] [
        lib.lists.flatten
        lib.mkMerge
      ];
      sops.templates = let path = "/etc/knot-resolver/kresd.conf.d/50-${cfg.dropin.infix}-template.conf"; in {
        "${path}" = {
          inherit path;
          mode = "0640";
          owner = "knot-resolver";
          group = "knot-resolver";
          content = lib.pipe [
          ] [
            lib.lists.flatten
            (builtins.concatStringsSep "\n")
          ];
        };
      };
    }
    (
      let
        d2Domains = lib.pipe cfg.nets [
          (lib.attrsets.mapAttrsToList (_: netCfg: netCfg.domain))
          lib.lists.unique
          (builtins.sort builtins.lessThan)
        ];
      in
      {
        # knot-dns
        services.knot.enable = true;
        services.knot.checkConfig = false; # doesn't allow some stuff like referencing keys
        systemd.services.knot.restartTriggers = lib.pipe config.sops.templates [
          builtins.attrValues
          (builtins.map (tpl: tpl.path))
          (builtins.filter (lib.strings.hasPrefix cfg.knot.configDir))
        ];
        services.knot.extraArgs = [
          "-v"
        ];
        services.knot.keyFiles = [
          # this will land at the beginning of file instead of `settings.include` somewhere in the middle
          "${cfg.knot.configDir}/*.conf"
        ];
        services.knot.settings = {
          server.listen = cfg.knot.listens;
          server.listen-tls =
            builtins.map
              (listener: {
                "${cfg.knot.localAddress}@${builtins.toString cfg.knot.localPort}" = "${cfg.knot.localAddress}@${builtins.toString cfg.knot.localPortTLS}";
              }."${listener}" or listener)
              cfg.knot.listens;
          server.listen-quic =
            builtins.map
              (listener: {
                "${cfg.knot.localAddress}@${builtins.toString cfg.knot.localPort}" = "${cfg.knot.localAddress}@${builtins.toString cfg.knot.localPortTLS}";
              }."${listener}" or listener)
              cfg.knot.listens;
          log = [{
            target = "syslog";
            any = "debug";
          }];
          mod-dnstap = [
            {
              id = "debug";
              sink = "/run/knot/dnstap.debug.tap";
              log-queries = "on";
              log-responses = "on";
              responses-with-queries = "on";
            }
          ];
          template = [{
            id = "default";
            global-module = [
              "mod-stats"
              #"mod-dnstap/debug"
            ];
          }];
          zone = lib.attrsets.mapAttrsToList
            (_: domainCfg: {
              domain = domainCfg.name;
              template = "default";
              acl = [ "admin" ] ++ lib.pipe d2Domains [
                (builtins.filter (domain: domain == domainCfg.name))
                (builtins.map (domain: "dhcp-ddns:${domain}"))
              ];
            })
            cfg.domains;
          acl = [
            {
              id = "admin";
              key = "admin";
              action = [
                "query"
                #"notify"
                #"transfer"
                "update"
              ];
            }
          ] ++ (builtins.map
            (domain: {
              id = "dhcp-ddns:${domain}";
              key = keaTSIGName;
              action = [
                "query"
                "update"
              ];

              update-owner = "name";
              update-owner-match = "sub";
              update-owner-name = [
                "${domain}."
              ];
            })
            d2Domains);
        };
        environment.etc."${lib.strings.removePrefix "/etc" cfg.knot.configDir}/.keep".text = "";
        environment.persistence."sys/data".directories = [
          { directory = cfg.knot.dataDir; user = "knot"; group = "knot"; mode = "0700"; }
        ];
        kdn.networking.router.kresd.upstreams = [{
          description = "local knot-dns";
          type = "STUB";
          nameservers = [ "${cfg.knot.localAddress}@${builtins.toString cfg.knot.localPort}" ];
          domains = lib.pipe cfg.domains [ builtins.attrValues (builtins.map (domainCfg: domainCfg.name)) ];
        }];
        sops.templates = lib.pipe knotKeys [
          (lib.attrsets.mapAttrsToList (id: keyCfg: {
            name = "knot/sops-key.${id}.conf";
            value = {
              path = "${cfg.knot.configDir}/sops-keys.${cfg.dropin.infix}.${id}.conf";
              owner = "knot";
              group = "knot";
              mode = "0400";
              content = ''
                # ${keyCfg.algorithm}:${id}:${keyCfg.secret}
                key:
                - id: ${id}
                  algorithm: ${keyCfg.algorithm}
                  secret: ${keyCfg.secret}
              '';
            };
          }))
          builtins.listToAttrs
        ];

        services.kea.dhcp-ddns.enable = true;
        kdn.networking.router = {
          kea.dhcp4.settings = {
            dhcp-ddns.enable-updates = true;
            ddns-override-client-update = true;
            ddns-replace-client-name = "when-not-present";
            ddns-send-updates = false;
            ddns-update-on-renew = true;
          };
          kea.dhcp-ddns.settings = {
            dns-server-timeout = 500;
            tsig-keys = [{
              name = keaTSIGName;
              algorithm = knotKeys.${keaTSIGName}.algorithm;
              secret = knotKeys.${keaTSIGName}.secret;
            }];
            loggers = [{
              name = "kea-dhcp-ddns";
              severity = if cfg.debug then "DEBUG" else "INFO";
              debuglevel = 99;
              output_options = [{ output = "stderr"; }];
            }];
            forward-ddns.ddns-domains = lib.pipe d2Domains [
              (builtins.map (domain: {
                name = "${lib.strings.removeSuffix "." domain}.";
                key-name = keaTSIGName;
                dns-servers = [{
                  ip-address = cfg.knot.localAddress;
                  port = cfg.knot.localPort;
                }];
              }))
            ];
            reverse-ddns.ddns-domains = [
              # TODO: add this https://kea.readthedocs.io/en/kea-2.2.0/arm/ddns.html#adding-reverse-ddns
            ];
          };
        };
        kdn.networking.router.domains = lib.pipe d2Domains [
          (builtins.map (domain: { name = domain; value = { }; }))
          builtins.listToAttrs
        ];
        systemd.services."kdn-knot-init" = {
          description = "Initialize knot's zonefiles";
          wantedBy = [ "knot.service" ];
          after = [ "knot.service" ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          serviceConfig.ExecStart = lib.pipe d2Domains [
            (builtins.map (domain: lib.strings.escapeShellArgs [
              (lib.getExe kdn-router-knot-setup-zone)
              "${cfg.knot.dataDir}/${domain}zone"
              domain
            ]))
          ]
          ++ lib.pipe cfg.nets [
            (lib.attrsets.mapAttrsToList (_: netCfg:
              (lib.attrsets.mapAttrsToList
                (_: addrCfg:
                  (lib.attrsets.mapAttrsToList
                    (host: hostCfg: lib.strings.escapeShellArgs [
                      (lib.getExe kdn-router-knot-ddns-update)
                      hostCfg.hostname
                      netCfg.domain
                      (if addrCfg.type == "ipv4" then "A" else "AAAA")
                      hostCfg.ip
                      "30"
                    ])
                    addrCfg.hosts)
                )
                netCfg.addressing)
            ))
            lib.flatten
          ]
          ;
        };
      }
    )
    {
      services.knot.package = pkgs.knot-dns.overrideAttrs (old: {
        /*
        TODO: remove after knot-dns 3.4.1 release
        listening on link-local address will be supported in not-yet-released 3.4.1 version
        so we're using 3.4 branch before release
        */
        src = pkgs.fetchFromGitLab {
          domain = "gitlab.nic.cz";
          owner = "knot";
          repo = "knot-dns";
          rev = "add8125a347215b8dc3a76d6fb2160620428eada";
          hash = "sha256-2vsKqRX8WH54W0TImCaMnpwSztkLkzCTBHKBPDdk5CM=";
        };
        # dnstap support
        configureFlags = old.configureFlags
          ++ [ "--with-module-dnstap" "--enable-dnstap" ]
        ;
        buildInputs = old.buildInputs
          ++ (with pkgs; [ fstrm protobufc ])
        ;
      });
    }
    {
      # Firewall/forwarding
      networking.firewall.trustedInterfaces = lib.pipe cfg.nets [
        builtins.attrValues
        (builtins.filter (netCfg: netCfg.firewall.trusted))
        (builtins.map (netCfg: netCfg.interface))
      ];
      networking.firewall.interfaces = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: {
          "${netCfg.interface}" = {
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
          builtins.map (to: { from = netCfg.interface; inherit to; }) netCfg.forward.to
          ++ builtins.map (from: { inherit from; to = netCfg.interface; }) netCfg.forward.from
        ))
        builtins.concatLists
        lib.lists.unique
      ];
    }
    {
      # systemd-networkd + drop-ins
      systemd.network.netdevs = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: {
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
                TransmitHashPolicy = "layer3+4";
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
        }))
        lib.mkMerge
      ];
      systemd.network.networks = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg: lib.mkMerge [
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
              (lib.mkIf (netCfg.type == "lan") (lib.mkMerge [
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
              ]))
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
              mkInterfaces = kind: ifaceCfg: lib.mkIf (netCfg.netdev.kind == kind) (lib.pipe netCfg.interfaces [
                (lib.lists.imap0 (idx: iface: {
                  name = getInterfaceUnit iface;
                  value = lib.mkMerge [
                    { matchConfig.Name = lib.mkDefault iface; }
                    (ifaceCfg idx iface)
                  ];
                }))
                builtins.listToAttrs
              ]);
            in
            lib.mkMerge [
              (mkInterfaces "bridge" (idx: iface: {
                networkConfig.Bridge = netCfg.interface;
                linkConfig.RequiredForOnline = "enslaved";
              }))
              (mkInterfaces "bond" (idx: iface: {
                networkConfig = lib.mkMerge [
                  {
                    Bond = netCfg.interface;
                  }
                  (lib.mkIf (netCfg.netdev.bond.mode == "backup") {
                    PrimarySlave = idx == 0;
                  })
                ];
              }))
              (mkInterfaces "vlan" (idx: iface: {
                networkConfig.VLAN = [ netCfg.interface ];
              }))
            ]
          )
        ]))
        lib.mkMerge
      ];
      sops.templates = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg:
          let path = mkDropInPath "${netCfg.unit.name}.network" "50-template"; in {
            "${path}" = {
              inherit path;
              mode = "0644";
              content = netCfg.template.network._text;
            };
          }))
        lib.mkMerge
      ];
    }
    (lib.mkIf (cfg.kresd.rewrites != { }) {
      # TODO: watch out for kresd 6.0+ version for native support of rewrites
      kdn.service.coredns.enable = true;
      kdn.service.coredns.rewrites = builtins.mapAttrs
        (_: rewriteCfg: {
          inherit (rewriteCfg) from to upstreams;
          binds = [ cfg.coredns.localAddress ];
          port = 53;
        })
        cfg.kresd.rewrites;
      kdn.networking.router.kresd.upstreams = lib.pipe cfg.kresd.rewrites [
        (lib.attrsets.mapAttrsToList (_: rewriteCfg: {
          description = "redirect to ${rewriteCfg.to} from ${rewriteCfg.from}";
          type = "STUB";
          nameservers = [ cfg.coredns.localAddress ];
          domains = [ rewriteCfg.to ];
        }))
        lib.mkBefore
      ];
    })
    (lib.mkIf (cfg.kresd.defaultUpstream != null) {
      kdn.networking.router.kresd.upstreams =
        let
          upstreams = {
            systemd-resolved = {
              description = "systemd-resolved";
              type = "STUB";
              nameservers = [ "127.0.0.53" ];
            };
            quad9 = {
              description = "Quad9";
              type = "TLS_FORWARD";
              nameservers = [
                "2620:fe::fe"
                "2620:fe::10"
                "9.9.9.9"
                "9.9.9.10"
              ];
              auth.hostname = "dns.quad9.net";
            };
            cloudflare = {
              description = "Cloudflare";
              type = "TLS_FORWARD";
              nameservers = [
                "2606:4700:4700::1111"
                "2606:4700:4700::1001"
                "1.1.1.1"
                "1.0.0.1"
              ];
              auth.hostname = "cloudflare-dns.com";
            };
            google = {
              description = "Google";
              type = "TLS_FORWARD";
              auth.hostname = "dns.google";
              nameservers = [
                "2001:4860:4860::8888"
                "2001:4860:4860::8844"
                "8.8.8.8"
                "8.8.4.4"
              ];
            };
          };
        in
        lib.mkAfter [
          upstreams."${cfg.kresd.defaultUpstream}"
        ];
    })
  ]);
}
