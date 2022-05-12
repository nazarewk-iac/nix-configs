{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.networking.wireguard;
  getIP = num: pipe cfg.subnet [
    (splitString ".")
    reverseList
    (l: [ (toString num) ] ++ (tail l))
    reverseList
    (concatStringsSep ".")
  ];

  ip = getIP cfg.hostnum;
  cidr = "${cfg.subnet}/${toString cfg.netmask}";
in
{
  options.nazarewk.networking.wireguard = {
    enable = mkOption {
      type = types.bool;
      default = cfg.client.enable || cfg.server.enable;
    };

    server = {
      enable = mkEnableOption "wireguard server setup";

      externalInterface = mkOption {
        type = types.str;
        default = "eth0";
      };

      address = mkOption {
        type = types.str;
      };

      pubKey = mkOption {
        type = types.str;
      };
    };

    client = {
      enable = mkEnableOption "wireguard client setup";
    };

    hostnum = mkOption {
      type = types.ints.unsigned;
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

          hostnum = mkOption {
            type = types.ints.unsigned;
          };

          cfg = mkOption {
            type = types.attrs;
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
    (mkIf (cfg.client.enable || cfg.server.enable) {
      networking.firewall = {
        allowedUDPPorts = [ cfg.port ];
      };

      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

      networking.wireguard.interfaces = {
        # "wg0" is the network interface name. You can name the interface arbitrarily.
        ${cfg.interfaceName} = {
          # Determines the IP address and subnet of the server's end of the tunnel interface.
          ips = [ "${ip}/${toString cfg.netmask}" ];

          # The port that WireGuard listens to. Must be accessible by the client.
          listenPort = cfg.port;

          privateKeyFile = "/root/wireguard-keys/main/private";
          generatePrivateKeyFile = true;

          peers = lib.pipe cfg.peers [
            (lib.filterAttrs (n: v: v.active && n != config.networking.hostName))
            lib.attrValues
            (builtins.map (entry: mkMerge [
              {
                allowedIPs = [ "${getIP entry.hostnum}/32" ];
              }
              entry.cfg
            ]))
          ];
        };
      };
    })
    (mkIf cfg.server.enable {
      networking.nat.enable = true;
      networking.nat.externalInterface = cfg.server.externalInterface;
      networking.nat.internalInterfaces = [ cfg.interfaceName ];

      networking.wireguard.interfaces = {
        ${cfg.interfaceName} = {
          # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
          # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
          postSetup = ''
            ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${cidr} -o ${cfg.server.externalInterface} -j MASQUERADE
          '';

          # This undoes the above command
          postShutdown = ''
            ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${cidr} -o ${cfg.server.externalInterface} -j MASQUERADE
          '';

        };
      };
    })
  ]);
}
