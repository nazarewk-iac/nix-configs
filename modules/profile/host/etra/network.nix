{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.etra.networking;

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
in
{
  options.kdn.profile.host.etra.networking = {
    debug = lib.mkOption {
      type = with lib.types; bool;
    };

    wan.type = lib.mkOption {
      type = with lib.types; enum [ "static" "dhcp" ];
    };
    wan.static.networks = lib.mkOption {
      type = with lib.types; listOf (enum cfg.networks);
    };

    lan.static.networks = lib.mkOption {
      type = with lib.types; listOf (enum cfg.networks);
    };

    reloadOnDropIns = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    networks = lib.mkOption {
      internal = true;
      type = with lib.types; listOf str;
      default =
        let
          pathsJson = pkgs.runCommand "kdn-networks.json"
            { inherit (config.kdn.security.secrets.files.networks) sopsFile; } ''
            ${lib.getExe pkgs.gojq} -cM --yaml-input '.networks | keys' <"$sopsFile" >"$out"
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
      kdn.profile.host.etra.networking.interfaces."enp1s0".role = "wan-primary";
      kdn.profile.host.etra.networking.interfaces."enp2s0".role = "lan";
      kdn.profile.host.etra.networking.interfaces."enp3s0".role = "lan";
    }
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
    (lib.mkIf cfg.debug {
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
    })
    (
      let intervalSec = "1"; in {
        systemd.paths."kdn-systemd-networkd-reload" = {
          description = "reloads systemd-networkd on external configuration changes";
          wantedBy = [ "systemd-networkd.service" ];
          after = [ "systemd-networkd.service" ];
          pathConfig.PathChanged = builtins.map (unit: "/etc/systemd/network/${unit}.d") cfg.reloadOnDropIns;
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
      }
    )
    {
      # WAN
      kdn.profile.host.etra.networking.reloadOnDropIns = [ "00-wan-bond.netdev" "00-wan.network" ];
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
        networkConfig.LinkLocalAddressing = "ipv4";
      };
    })
    (lib.mkIf (cfg.wan.type == "static") {
      systemd.network.networks."00-wan" = {
        networkConfig.DHCP = "no";
        networkConfig.IPv6AcceptRA = "no";
        networkConfig.LinkLocalAddressing = "no";
      };
      # TODO: somehow rollback config after failing to connect to internet?
      sops.templates = lib.pipe cfg.wan.static.networks [
        (builtins.map (name:
          let
            path = "/etc/systemd/network/00-wan.network.d/static-${name}.conf";
            net = ph.networks."${name}";
            isIPv6 = lib.strings.hasInfix ":" net.addresses."${host}";
          in
          [{
            name = path;
            value = {
              inherit path;
              mode = "0644";
              content = ''
                [Network]
                Address=${net.addresses."${host}"}/${net.netmask}
                ${lib.strings.optionalString (net ? gateway) ''
                DNS=${net.gateway}
                Gateway=${net.gateway}
                ''}
              '';
            };
          }]
          ++ lib.lists.optionals (isIPv6 && net ? prefixes) (lib.pipe net.prefixes [
            (lib.attrsets.mapAttrs (prefixName: prefix:
              let
                path = "/etc/systemd/network/00-wan.network.d/static-${name}-prefix-${prefixName}.conf";
              in
              {
                name = path;
                value = {
                  inherit path;
                  mode = "0644";
                  content = ''
                    [Network]
                    Address=${prefix.addresses."${host}"}/${prefix.netmask}

                    [IPv6Prefix]
                    Prefix=${prefix.network}/${prefix.netmask}
                    AddressAutoconfiguration=true
                    OnLink=true
                  '';
                };
              }))
            builtins.attrValues
          ])
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
      kdn.profile.host.etra.networking.reloadOnDropIns = [ "00-lan.netdev" "00-lan.network" ];
      systemd.network.netdevs."00-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "lan";
        };
      };
      systemd.network.networks."00-lan" = {
        matchConfig.Name = "lan";
        bridgeConfig = { };
        # Disable address autoconfig when no IP configuration is required
        #networkConfig.LinkLocalAddressing = "no";
        linkConfig = {
          # or "routable" with IP addresses configured
          RequiredForOnline = "carrier";
        };
        #addresses = [
        #  { Address = "192.168.40.1/23"; }
        #];
      };
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
    { }
  ]);
}
