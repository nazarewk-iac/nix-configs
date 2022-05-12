{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.networking.wireguard.server;
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
  options.nazarewk.networking.wireguard.server = {
    enable = mkEnableOption "wireguard setup setup";

    externalInterface = mkOption {
      type = types.str;
      default = "eth0";
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

    hostnum = mkOption {
      type = types.ints.unsigned;
      default = 1;
    };

    port = mkOption {
      type = types.ints.unsigned;
      default = 51820;
    };
  };

  config = mkIf cfg.enable {
    networking.nat.enable = true;
    networking.nat.externalInterface = cfg.externalInterface;
    networking.nat.internalInterfaces = [ cfg.interfaceName ];
    networking.firewall = {
      allowedUDPPorts = [ cfg.port ];
    };

    networking.wireguard.interfaces = {
      # "wg0" is the network interface name. You can name the interface arbitrarily.
      ${cfg.interfaceName} = {
        # Determines the IP address and subnet of the server's end of the tunnel interface.
        ips = [ "${ip}/${toString cfg.netmask}" ];

        # The port that WireGuard listens to. Must be accessible by the client.
        listenPort = cfg.port;

        # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
        # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
        postSetup = ''
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${cidr} -o ${cfg.externalInterface} -j MASQUERADE
        '';

        # This undoes the above command
        postShutdown = ''
          ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${cidr} -o ${cfg.externalInterface} -j MASQUERADE
        '';

        privateKeyFile = "/root/wireguard-keys/main/private";
        generatePrivateKeyFile = true;

        peers = [
        ];
      };
    };
  };
}
