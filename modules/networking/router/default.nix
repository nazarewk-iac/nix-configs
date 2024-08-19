{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.networking.router;

  # TODO: make the IPv6 WAN accessible from LAN
  # TODO: make the IPv6 LAN pingable from WAN

  /* TODO: make IPv6 forwarding work?
      - https://matrix.to/#/!tCyGickeVqkHsYjWnh:nixos.org/$WCyFnH_26PJX4lcbTDohzInJv0PLJRQzPKt4qFMeOJo?via=nixos.org&via=matrix.org&via=tchncs.de
      - https://git.sr.ht/~r-vdp/nixos-config/tree/f595662416269797ee2c917822133b5ae5119672/item/hosts/beelink/network.nix#L245
      - rules in the snippet above
  */

  wanInterfaces = lib.pipe cfg.interfaces [
    builtins.attrValues
    (builtins.filter (iface: lib.lists.any (r: r == iface.role) [ "wan" "wan-primary" ]))
  ];
  lanInterfaces = lib.pipe cfg.interfaces [
    builtins.attrValues
    (builtins.filter (iface: lib.lists.any (r: r == iface.role) [ "lan" ]))
  ];

  ph = config.kdn.security.secrets.placeholders.networking;
  host = config.networking.hostName;

  mkDropInDir = unit: "/etc/systemd/network/${unit}.d";
  # insert `cut -c-8 </proc/sys/kernel/random/uuid` for easier identification of managed files
  mkDropInFileName = name: "kdn-router-35f45554-${name}.conf";
  mkDropInPath = unit: name: "${mkDropInDir unit}/${mkDropInFileName name}";

  mkAddressLines = net: host: lib.pipe net [
    (lib.attrsets.attrByPath [ "addresses" host ] { })
    builtins.attrValues
    (builtins.map (address: "Address=${address}"))
    (builtins.concatStringsSep "\n")
  ];
in
{
  options.kdn.networking.router = {
    enable = lib.mkEnableOption "systemd-networkd based router";

    debug = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };

    wan.type = lib.mkOption {
      type = with lib.types; enum [ "static" "dhcp" ];
    };
    wan.static.networks = lib.mkOption {
      type = with lib.types; listOf (enum cfg.networks.wan);
    };

    lan.static.networks = lib.mkOption {
      type = with lib.types; listOf (enum cfg.networks.lan);
    };

    reloadOnDropIns = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    networks = lib.mkOption {
      internal = true;
      type = with lib.types; attrsOf (listOf str);
      default =
        let
          pathsJson = pkgs.runCommand "kdn-networks.json"
            { inherit (config.kdn.security.secrets.files.networking) sopsFile; } ''
            ${lib.getExe pkgs.gojq} -cM --yaml-input '.networking.networks | with_entries(.value |= keys)' <"$sopsFile" >"$out"
          '';
        in
        lib.pipe pathsJson [
          builtins.readFile
          builtins.fromJSON
        ];
    };
    interfaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@ifaceArgs: {
        options.name = lib.mkOption {
          type = with lib.types; str;
          default = ifaceArgs.name;
        };
        options.role = lib.mkOption {
          type = with lib.types; enum [ "wan" "wan-primary" "lan" ];
        };
        options.primary = lib.mkOption {
          type = with lib.types; bool;
          default = false;
        };
      }));
      default = { };
    };
  };
  config = lib.mkIf config.kdn.profile.host.etra.enable (lib.mkMerge [
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
      networking.firewall.trustedInterfaces = [ "lan" ];

      networking.firewall.extraForwardRules = ''
        meta iifname . meta oifname {
          lan . wan,
          wan . lan,
        } accept comment "allow traffic from internal networks to the WAN"

        ${lib.optionalString config.networking.firewall.logRefusedConnections ''
          # Refused IPv4 connections get logged in the input filter due to NAT.
          # For IPv6 connections destined for some address in our LAN we end up
          # in the forward filter instead, so we log them here.
          tcp flags syn / fin,syn,rst,ack log level info prefix "refused connection: "
        ''}
      '';
    }
    (lib.mkIf cfg.debug {
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
      networking.firewall.logRefusedPackets = true;
      networking.firewall.rejectPackets = true;

      networking.nftables.tables =
        let
          mkTable = family: priority: chains: lib.pipe chains [
            (builtins.map (hook: ''
              chain ${hook} {
                type filter hook ${hook} priority ${priority}; policy accept;
                icmpv6 type { echo-request, echo-reply } log level info prefix "[ICMPv6:echo@${family}@${hook}]: "
              }
            ''))
            (builtins.concatStringsSep "\n")
            (content: { inherit family content; })
          ];
        in
        {
          icmp6-logging-ip6 = mkTable "ip6" "filter" [
            # "ingress" # doesn't seem to work
            "prerouting"
            "input"
            "forward"
            "output"
            "postrouting"
          ];
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
              -type f -name '${mkDropInFileName "*"}' \
              ${lib.escapeShellArgs existing} \
              -printf '> removed: %p\n' -delete
          '';
      }
    )
    {
      # WAN
      kdn.networking.router.reloadOnDropIns = [ "00-wan-bond.netdev" "00-wan.network" ];
      systemd.network.netdevs."00-wan-bond" = {
        # see https://wiki.archlinux.org/title/Systemd-networkd#Bonding_a_wired_and_wireless_interface
        netdevConfig.Kind = "bond";
        netdevConfig.Name = "wan";
        bondConfig.Mode = "active-backup";
        bondConfig.PrimaryReselectPolicy = "always";
        bondConfig.MIIMonitorSec = "1s";
      };
      systemd.network.networks."00-wan" = {
        matchConfig.Name = "wan";
        networkConfig = {
          BindCarrier = builtins.map (iface: iface.name) wanInterfaces;
          IPMasquerade = "ipv4";
        };
        linkConfig.RequiredForOnline = "routable";
      };
    }
    (lib.mkIf (cfg.wan.type == "dhcp") {
      systemd.network.networks."00-wan" = {
        networkConfig.DHCP = "ipv4";
        networkConfig.IPv6AcceptRA = "yes";
        networkConfig.IPv6SendRA = "no";
        networkConfig.LinkLocalAddressing = "ipv4";
      };
    })
    (lib.mkIf (cfg.wan.type == "static") {
      systemd.network.networks."00-wan" = {
        networkConfig.DHCP = "no";
        networkConfig.IPv6AcceptRA = "no";
        networkConfig.IPv6SendRA = "no";
        networkConfig.LinkLocalAddressing = "no";
      };
      # TODO: somehow rollback config after failing to connect to internet?
      sops.templates = lib.pipe cfg.wan.static.networks [
        (builtins.map (name:
          let
            path = mkDropInPath "00-wan.network" "static-${name}";
            net = ph.networks.wan."${name}";
            isIPv6 = lib.strings.hasInfix ":" net.network;
          in
          lib.lists.optional (net ? network) {
            name = path;
            value = {
              inherit path;
              mode = "0644";
              content = ''
                [Network]
                ${mkAddressLines net host}
                ${lib.strings.optionalString (net ? gateway) ''
                DNS=${net.gateway}
                Gateway=${net.gateway}
                ''}
              '';
            };
          }
        ))
        lib.lists.flatten
        builtins.listToAttrs
      ];
    })
    {
      systemd.network.networks = lib.pipe wanInterfaces [
        (builtins.map (iface: {
          name = "10-${iface.name}-${iface.role}";
          value = {
            matchConfig.Name = iface.name;
            networkConfig.Bond = "wan";
            networkConfig.PrimarySlave = iface.role == "wan-primary";
          };
        }))
        builtins.listToAttrs
      ];
    }
    {
      # LAN
      kdn.networking.router.reloadOnDropIns = [ "00-lan.netdev" "00-lan.network" ];
      systemd.network.netdevs."00-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "lan";
        };
      };
      systemd.network.networks."00-lan" = {
        matchConfig.Name = "lan";
        bridgeConfig = { };

        networkConfig = {
          ConfigureWithoutCarrier = true;
          # IPv4
          DHCP = false;
          DHCPServer = true;
          IPMasquerade = "ipv4";
          # IPv6
          # for DHCPv6-PD to work I would need to have `IPv6AcceptRA=true` on `wan`
          DHCPPrefixDelegation = false;
          IPv6AcceptRA = false;
          IPv6SendRA = true;
          IPv6PrivacyExtensions = true;
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          # misc
          MulticastDNS = true;
        };
        linkConfig = {
          RequiredForOnline = "routable";
          Multicast = true;
        };
        dhcpServerConfig = {
          EmitDNS = true;
          PoolOffset = 32;
        };
        ipv6SendRAConfig = {
          Managed = true;
          EmitDNS = true;
          UplinkInterface = "wan";
        };
      };
      sops.templates = lib.pipe cfg.lan.static.networks [
        (builtins.map (name:
          let
            path = mkDropInPath "00-lan.network" "static-${name}";
            net = ph.networks.lan."${name}";
            isIPv6 = lib.strings.hasInfix ":" net.network;
            isIPv4 = !isIPv6;
          in
          {
            name = path;
            value = {
              inherit path;
              mode = "0644";
              content = ''
                [Network]
                ${mkAddressLines net host}

                ${lib.strings.optionalString (isIPv4 && net ? gateway) ''
                [DHCPServer]
                ServerAddress=${net.gateway}
                ''}

                ${lib.pipe net [
                  (lib.attrsets.attrByPath [ "advertised-prefixes" ] { })
                  builtins.attrValues
                  (builtins.filter (prefix: lib.strings.hasInfix ":" prefix.network))
                  (builtins.map ( prefix: ''
                [IPv6Prefix]
                Prefix=${prefix.network}/${prefix.netmask}
                AddressAutoconfiguration=true
                OnLink=true
                Assign=true
                  ''))
                  (builtins.concatStringsSep "\n")
                ]}
              '';
            };
          }
        ))
        lib.lists.flatten
        builtins.listToAttrs
      ];
    }
    {
      systemd.network.networks = lib.pipe lanInterfaces [
        (builtins.map (iface: {
          name = "10-${iface.name}-${iface.role}";
          value = {
            matchConfig.Name = iface.name;
            networkConfig.Bridge = [ "lan" ];
            linkConfig.RequiredForOnline = "enslaved";
          };
        }))
        builtins.listToAttrs
      ];
    }
  ]);
}
