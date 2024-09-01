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
                dns = lib.mkOption {
                  type = with lib.types; listOf str;
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
          ];
          default = "networkd";
        };
        dns.implementation = lib.mkOption {
          type = with lib.types; enum [
            null
            #"knot-dns"
            #"knot-resolver"
            #"corerad"
          ];
          default = null;
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
      system.activationScripts.renderSecrets.deps = [ "kdnRouterCleanDropIns" ];
      system.activationScripts.kdnRouterCleanDropIns =
        let
          directories = [
            "/etc/systemd/network"
            "/etc/knot-resolver"
          ];
          existing = lib.pipe config.sops.templates [
            builtins.attrValues
            (builtins.map (tpl: tpl.path))
            (builtins.filter (path: builtins.any (dir: lib.strings.hasPrefix dir path) directories))
            (builtins.map (path: [ "!" "-path" path ]))
            lib.lists.flatten
          ];
        in
        ''
          echo 'Cleaning up managed drop-ins...'
          ${lib.getExe pkgs.findutils} \
            ${builtins.concatStringsSep " " directories} \
            -mindepth 2 -maxdepth 2 \
            -type f -name '*${cfg.dropin.infix}*' \
            ${lib.escapeShellArgs existing} \
            -printf '> removed: %p\n' -delete
        '';
    }
    {
      # Kea DHCPv4
      # TODO:
      services.kea = {
        dhcp4.enable = true;
      };
      kdn.networking.router = {
        kea.dhcp4.settings = lib.pipe cfg.nets [
          builtins.attrValues
          (builtins.filter (netCfg: netCfg.type == "lan"))
          (builtins.map (netCfg: {
            interfaces-config.interfaces = [ netCfg.name ];
            subnet4 = lib.pipe netCfg.addressing [
              builtins.attrValues
              (builtins.filter (addrCfg: addrCfg.enable && addrCfg.type == "ipv4"))
              (builtins.map (addrCfg: {
                id = addrCfg.id;
                interface = netCfg.name;
                subnet = with addrCfg; "${network}/${netmask}";
                pools = lib.pipe addrCfg.pools [
                  builtins.attrValues
                  (builtins.map (pool: { pool = with pool; "${start} - ${end}"; }))
                ];
                option-data = [
                  { name = "routers"; data = addrCfg.hosts."${hostname}".ip; }
                  { name = "domain-name-servers"; data = addrCfg.hosts."${hostname}".ip; }
                ];
                reservations = lib.pipe addrCfg.hosts [
                  builtins.attrValues
                  (builtins.filter (host: host.ident != { }))
                  (builtins.map (host: host.ident // {
                    hostname = host.hostname;
                    ip-address = host.ip;
                  }))
                ];
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
          }])
          lib.mkMerge
        ];
      };
    }
    {
      # kea configuration plumbing
      services.kea = {
        dhcp4.configFile = config.sops.templates."kea/dhcp4.conf".path;
        dhcp6.configFile = config.sops.templates."kea/dhcp6.conf".path;
        ctrl-agent.configFile = config.sops.templates."kea/ctrl-agent.conf".path;
        dhcp-ddns.configFile = config.sops.templates."kea/dhcp-ddns.conf".path;
      };
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
      # knot authoritative DNS server 
      environment.systemPackages = [
        config.services.knot.package # contains `kdig`
      ];
    }
    {
      # kresd DNS resolver
      services.kresd.enable = true;
      services.kresd.package = (pkgs.knot-resolver.override {
        extraFeatures = true;
      }).overrideAttrs (old: {
        buildInputs = old.buildInputs ++ (with pkgs.luajitPackages; [
          luafilesystem
        ]);
      });

      services.kresd.extraConfig = ''
        -- credits to https://github.com/hectorm/hblock-resolver/blob/188d074b41e98d88136d620b4014f743ce55ab2a/config/knot-resolver/kresd.conf

        -- Main configuration of Knot Resolver.
        -- Refer to manual: https://knot-resolver.readthedocs.io/en/latest/daemon.html#configuration

        -- Load configuration from kresd.conf.d/ directory

        local lfs = require('lfs')
        local conf_dir = env.KRESD_CONF_DIR .. '/kresd.conf.d'

        if lfs.attributes(conf_dir) ~= nil then
          local conf_files = {}
          for entry in lfs.dir(conf_dir) do
            if entry:sub(-5) == '.conf' then
              table.insert(conf_files, entry)
            end
          end
          table.sort(conf_files)
          for i = 1, #conf_files do
            dofile(conf_dir .. '/' .. conf_files[i])
          end
        end
      '';
      systemd.services."kresd@".environment.KRESD_CONF_DIR = "/etc/knot-resolver";
      systemd.services."kresd@".restartTriggers = lib.pipe config.sops.templates [
        builtins.attrValues
        (builtins.map (tpl: tpl.path))
        (builtins.filter (lib.strings.hasPrefix "/etc/knot-resolver"))
      ];

      sops.templates = lib.pipe cfg.nets [
        (lib.attrsets.mapAttrsToList (_: netCfg:
          let path = "/etc/knot-resolver/kresd.conf.d/50-${cfg.dropin.infix}-template-network-${netCfg.name}.conf"; in {
            "${path}" = {
              inherit path;
              mode = "0640";
              owner = "knot-resolver";
              group = "knot-resolver";
              content =
                let
                  ips = [ ]
                    ++ (builtins.map
                    (addr: lib.pipe addr [
                      # remove everything after the last `/`
                      (lib.strings.splitString "/")
                      lib.lists.init
                      (builtins.concatStringsSep "/")
                    ])
                    netCfg.address)
                    ++ (lib.pipe netCfg.addressing [
                    builtins.attrValues
                    (builtins.map (addrCfg: addrCfg.hosts."${hostname}".ip))
                  ])
                  ;

                  lines =
                    [
                      # forward to resolved for now
                      # TODO: replace it with knot-dns
                      "policy.add(policy.all(policy.STUB({'127.0.0.53'})))"
                      # TODO: already listening on it?
                      #''net.listen(net['nb-priv'], 53, { kind = 'dns', freebind = true })''
                    ]
                    ++ builtins.map (ip: ''net.listen('${ip}', 53, { kind = 'dns', freebind = true })'') ips;
                in
                builtins.concatStringsSep "\n" lines;
            };
          }))
        (l: l ++ [
          (
            let path = "/etc/knot-resolver/kresd.conf.d/50-${cfg.dropin.infix}-template.conf"; in {
              "${path}" = {
                inherit path;
                mode = "0640";
                owner = "knot-resolver";
                group = "knot-resolver";
                content = ''
                  policy.add(policy.all(policy.STUB({'127.0.0.53'})))
                '';
              };
            }
          )
        ])
        lib.mkMerge
      ];
      environment.persistence."sys/data".directories = [
        { directory = "/var/lib/knot-resolver"; user = "knot-resolver"; group = "knot-resolver"; mode = "0770"; }
      ];
      environment.persistence."sys/cache".directories = [
        { directory = "/var/cache/knot-resolver"; user = "knot-resolver"; group = "knot-resolver"; mode = "0770"; }
      ];
    }
    {
      # Firewall/forwarding
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
                Name = netCfg.name;
              };
            }
            (lib.mkIf (netCfg.netdev.kind == "bond") {
              bondConfig = {
                Mode = "active-backup";
                PrimaryReselectPolicy = "always";
                MIIMonitorSec = "1s";
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
                matchConfig.Name = netCfg.name;
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
                networkConfig.Bridge = netCfg.name;
                linkConfig.RequiredForOnline = "enslaved";
              }))
              (mkInterfaces "bond" (idx: iface: {
                networkConfig.Bond = netCfg.name;
                networkConfig.PrimarySlave = idx == 0;
              }))
              (mkInterfaces "vlan" (idx: iface: {
                networkConfig.VLAN = [ netCfg.name ];
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
  ]);
}
