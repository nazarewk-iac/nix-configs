{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.networking.wireguard;
  getIP = num:
    lib.pipe cfg.subnet [
      (lib.splitString ".")
      lib.reverseList
      (l: [(builtins.toString ((lib.toInt (lib.head l)) + num))] ++ (lib.tail l))
      lib.reverseList
      (lib.concatStringsSep ".")
    ];

  cidr = "${cfg.subnet}/${toString cfg.netmask}";

  activePeers = lib.filterAttrs (n: v: v.active) cfg.peers;
  self = activePeers."${config.networking.hostName}" or {};

  isActive = self.active or false;
  isClient = isActive && !(self.server.enable or false);
  isServer = isActive && (self.server.enable or false);

  preparePeers = filters:
    lib.trivial.pipe activePeers (filters
      ++ [
        (lib.filterAttrs (n: v: n != config.networking.hostName))
        (builtins.mapAttrs (name: entry:
          lib.mkMerge [
            (lib.mkIf (!entry.server.enable) {
              allowedIPs = ["${getIP entry.hostnum}/32"];
            })
            (lib.mkIf entry.server.enable {
              allowedIPs = [
                cidr
              ];
            })
            entry.cfg
            (self.peersCfg."${name}" or {})
          ]))
        lib.attrValues
      ]);
in {
  options.kdn.networking.wireguard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = isClient || isServer;
    };

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "wg0";
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.100.0.0";
    };

    netmask = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 24;
    };

    port = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 51810;
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          active = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };

          server = {
            enable = lib.mkEnableOption "wireguard server setup";

            externalInterface = lib.mkOption {
              type = lib.types.str;
            };
          };

          hostnum = lib.mkOption {
            type = lib.types.ints.unsigned;
          };

          cfg = lib.mkOption {
            type = lib.types.attrs;
          };

          peersCfg = lib.mkOption {
            type = lib.types.attrsOf lib.types.attrs;
            default = {};
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        wireguard-tools
      ];
    }
    (lib.mkIf isActive {
      # see https://github.com/NixOS/nixpkgs/issues/180175#issuecomment-1186152020
      networking.networkmanager.unmanaged = ["interface-name:${cfg.interfaceName}"];

      networking.firewall = {
        allowedUDPPorts = [cfg.port];
        trustedInterfaces = [cfg.interfaceName];
      };

      networking.wireguard.interfaces = {
        # "wg0" is the network interface name. You can name the interface arbitrarily.
        ${cfg.interfaceName} = {
          # Determines the IP address and subnet of the server's end of the tunnel interface.
          ips = ["${getIP self.hostnum}/${toString cfg.netmask}"];

          # The port that WireGuard listens to. Must be accessible by the client.
          listenPort = cfg.port;

          privateKeyFile = "/root/wireguard-keys/main/private";
          generatePrivateKeyFile = true;

          peers = preparePeers [
            (lib.filterAttrs (n: v: v.server.enable))
          ];
        };
      };
      environment.persistence."usr/config".users.root.directories = [
        {
          directory = "wireguard-keys";
          mode = "0700";
        }
      ];
    })
    (lib.mkIf isServer {
      networking.nat.enable = true;
      networking.nat.externalInterface = self.server.externalInterface;
      networking.nat.internalInterfaces = [cfg.interfaceName];

      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

      networking.wireguard.interfaces = {
        ${cfg.interfaceName} = {
          # TODO: add manual routes creation and teardown, eg: ip r add 10.0.0.0/24 dev wg0 scope link
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

          peers = preparePeers [];
        };
      };
    })
  ]);
}
