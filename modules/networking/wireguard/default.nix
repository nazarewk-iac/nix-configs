{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.networking.wireguard;
  getIP = num: pipe cfg.subnet [
    (splitString ".")
    reverseList
    (l: [ (toString ((toInt (head l)) + num)) ] ++ (tail l))
    reverseList
    (concatStringsSep ".")
  ];

  cidr = "${cfg.subnet}/${toString cfg.netmask}";

  activePeers = lib.filterAttrs (n: v: v.active) cfg.peers;
  self = activePeers."${config.networking.hostName}" or { };

  isActive = self.active or false;
  isClient = isActive && !(self.server.enable or false);
  isServer = isActive && (self.server.enable or false);

  preparePeers = filters: lib.pipe activePeers (filters ++ [
    (lib.filterAttrs (n: v: n != config.networking.hostName))
    (builtins.mapAttrs (name: entry: mkMerge [
      (mkIf (!entry.server.enable) {
        allowedIPs = [ "${getIP entry.hostnum}/32" ];
      })
      (mkIf entry.server.enable {
        allowedIPs = [
          cidr
        ];
      })
      entry.cfg
      (self.peersCfg."${name}" or { })
    ]))
    lib.attrValues
  ]);
in
{
  options.nazarewk.networking.wireguard = {
    enable = mkOption {
      type = types.bool;
      default = isClient || isServer;
    };

    interfaceName = mkOption {
      type = types.str;
      default = "wg0";
    };

    subnet = mkOption {
      type = types.str;
      default = "10.100.0.0";
    };

    netmask = mkOption {
      type = types.ints.unsigned;
      default = 24;
    };

    port = mkOption {
      type = types.ints.unsigned;
      default = 51820;
    };

    peers = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          active = mkOption {
            type = types.bool;
            default = true;
          };

          server = {
            enable = mkEnableOption "wireguard server setup";

            externalInterface = mkOption {
              type = types.str;
            };
          };

          hostnum = mkOption {
            type = types.ints.unsigned;
          };

          cfg = mkOption {
            type = types.attrs;
          };

          peersCfg = mkOption {
            type = types.attrsOf types.attrs;
            default = { };
          };
        };
      });
      default = { };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      environment.systemPackages = with pkgs; [
        wireguard-tools
      ];
    }
    (mkIf (isActive) {
      networking.firewall = {
        allowedUDPPorts = [ cfg.port ];
        trustedInterfaces = [ cfg.interfaceName ];
      };

      networking.wireguard.interfaces = {
        # "wg0" is the network interface name. You can name the interface arbitrarily.
        ${cfg.interfaceName} = {
          # Determines the IP address and subnet of the server's end of the tunnel interface.
          ips = [ "${getIP self.hostnum}/${toString cfg.netmask}" ];

          # The port that WireGuard listens to. Must be accessible by the client.
          listenPort = cfg.port;

          privateKeyFile = "/root/wireguard-keys/main/private";
          generatePrivateKeyFile = true;

          peers = preparePeers [
            (lib.filterAttrs (n: v: v.server.enable))
          ];
        };
      };
    })
    (mkIf isServer {
      networking.nat.enable = true;
      networking.nat.externalInterface = self.server.externalInterface;
      networking.nat.internalInterfaces = [ cfg.interfaceName ];

      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

      networking.wireguard.interfaces = {
        ${cfg.interfaceName} = {
          allowedIPsAsRoutes = false;
          # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
          # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
          postSetup = ''
            ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${cidr} -o ${self.server.externalInterface} -j MASQUERADE
          '';

          # This undoes the above command
          postShutdown = ''
            ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${cidr} -o ${self.server.externalInterface} -j MASQUERADE
          '';

          peers = preparePeers [ ];
        };
      };
    })
  ]);
}
