{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.networking.router;

  # TODO: make the IPv6 WAN accessible from LAN
  # TODO: make the IPv6 LAN pingable from WAN

  wanInterfaces = lib.pipe cfg.interfaces [
    builtins.attrValues
    (builtins.filter (iface: lib.lists.any (r: r == iface.role) [ "wan" "wan-primary" ]))
  ];
  lanInterfaces = lib.pipe cfg.interfaces [
    builtins.attrValues
    (builtins.filter (iface: lib.lists.any (r: r == iface.role) [ "lan" ]))
  ];

  ph.networks = config.kdn.security.secrets.placeholders.default.networks;
  host = config.networking.hostName;

  mkDropInDir = unit: "/etc/systemd/network/${unit}.d";
  # insert `cut -c-8 </proc/sys/kernel/random/uuid` for easier identification of managed files
  mkDropInFileName = name: "kdn-router-35f45554-${name}.conf";
  mkDropInPath = unit: name: "${mkDropInDir unit}/${mkDropInFileName name}";

  mkAddressLines = net: host: lib.pipe net [
    (lib.attrsets.attrByPath [ "addresses" host ] { })
    builtins.attrValues
    (builtins.map (address: "Address=${address}/${net.netmask}"))
    (builtins.concatStringsSep "\n")
  ];
  mkPrefixAddressLines = net: host: lib.pipe net [
    (lib.attrsets.attrByPath [ "prefixes" ] { })
    builtins.attrValues
    (builtins.map (prefix: mkAddressLines prefix host))
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
            { inherit (config.kdn.security.secrets.files.networks) sopsFile; } ''
            ${lib.getExe pkgs.gojq} -cM --yaml-input '.networks | with_entries(.value |= keys)' <"$sopsFile" >"$out"
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

      # https://gist.github.com/mweinelt/b78f7046145dbaeab4e42bf55663ef44
      # Enable forwarding between all interfaces, restrictions between
      # individual links are enforced by firewalling.
      boot.kernel.sysctl = {
        "net.ipv6.conf.all.forwarding" = 1;
        "net.ipv4.ip_forward" = 1;
      };

      # When true, systemd-networkd will remove routes that are not configured in .network files
      systemd.network.config.networkConfig.ManageForeignRoutes = false;
    }
    {
      networking.firewall.enable = true;
      networking.nftables.enable = true;
      networking.firewall.trustedInterfaces = [ "lan" ];
    }
    (lib.mkIf cfg.debug {
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
    })
    (
      let intervalSec = "3"; in {
        systemd.paths."kdn-systemd-networkd-reload" = {
          description = "reloads systemd-networkd on external configuration changes";
          wantedBy = [ "systemd-networkd.service" ];
          after = [ "systemd-networkd.service" ];
          pathConfig.PathChanged = builtins.map mkDropInDir cfg.reloadOnDropIns;
          pathConfig.TriggerLimitIntervalSec = "${intervalSec}s";
          pathConfig.TriggerLimitBurst = 1;
        };
        systemd.services."kdn-systemd-networkd-reload" = {
          description = "reloads systemd-networkd on external configuration changes";
          serviceConfig.Type = "oneshot";
          script = ''
            set -xeEuo pipefail

            sleep ${intervalSec}
            ${lib.getExe' pkgs.systemd "systemctl"} reload systemd-networkd.service
          '';
        };
        system.activationScripts.renderSecrets.deps = [ "kdnRouterCleanDropIns" ];
        system.activationScripts.kdnRouterCleanDropIns = ''
          echo 'Cleaning up managed systemd-networkd drop-ins...'
          ${lib.getExe pkgs.findutils} /etc/systemd/network -mindepth 2 -maxdepth 2 -type f -name '${mkDropInFileName "*"}' -printf '> removed: %p\n' -delete
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
        networkConfig.BindCarrier = builtins.map (iface: iface.name) wanInterfaces;
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
                ${mkPrefixAddressLines net host}
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
          DHCP = "no";
          DHCPServer = "yes";
          IPMasquerade = "ipv4";
          # IPv6
          # for DHCPv6-PD to work I would need to have `IPv6AcceptRA=true` on `wan`
          DHCPPrefixDelegation = false;
          #IPv6AcceptRA = false;
          IPv6SendRA = true;
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          IPv6PrivacyExtensions = true;
        };
        linkConfig = {
          RequiredForOnline = "routable";
        };
        dhcpServerConfig = {
          EmitDNS = true;
          PoolOffset = 32;
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
          (lib.lists.optional (net ? network) {
            name = path;
            value = {
              inherit path;
              mode = "0644";
              content = ''
                [Network]
                ${mkAddressLines net host}

                ${lib.strings.optionalString isIPv4 ''
                [DHCPServer]
                ServerAddress=${net.gateway}
                ''}
              '';
            };
          }) ++ lib.lists.optionals (isIPv6 && net ? prefixes) (lib.pipe net.prefixes [
            (lib.attrsets.mapAttrs (prefixName: prefix:
              let
                path = mkDropInPath "00-lan.network" "static-${name}-prefix-${prefixName}";
              in
              {
                name = path;
                value = {
                  inherit path;
                  mode = "0644";
                  content = ''
                    [Network]
                    ${mkAddressLines prefix host}

                    [IPv6Prefix]
                    Prefix=${prefix.network}/${prefix.netmask}
                    AddressAutoconfiguration=true
                    OnLink=true
                    Assign=true
                  '';
                };
              }))
            builtins.attrValues
          ])
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
