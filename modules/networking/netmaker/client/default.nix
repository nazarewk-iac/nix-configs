{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netmaker.client;
  srvCfg = config.kdn.networking.netmaker.server;
in
{
  options.kdn.networking.netmaker.client = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = srvCfg.enable;
    };

    firewall.trusted = lib.mkEnableOption "trust all traffic coming from Netmaker interfaces";

    firewall.ports = {
      tcp = lib.mkOption {
        type = with lib.types; listOf port;
        default = [ ];
      };
      tcpRanges = lib.mkOption {
        type = with lib.types; listOf (attrsOf port);
        default = [ ];
      };
      udp = lib.mkOption {
        type = with lib.types; listOf port;
        default = [ ];
      };
      udpRanges = lib.mkOption {
        type = with lib.types; listOf (attrsOf port);
        default = [ ];
      };
      networks.start = lib.mkOption {
        type = with lib.types; port;
        default = srvCfg.firewall.ports.networks.start;
      };
      networks.capacity = lib.mkOption {
        type = with lib.types; port;
        default = srvCfg.firewall.ports.networks.capacity;
      };
    };

  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.netclient.enable = true;
      services.netclient.package = pkgs.kdn.netclient;

      # required for detection by https://github.com/gravitl/netclient/blob/51f4458db0a5560d102d337a342567cb347399a6/config/config.go#L430-L443
      systemd.services."netclient".path = let fw = config.networking.firewall; in lib.optionals fw.enable [ fw.package ];
      systemd.services.netclient.environment.NETCLIENT_INIT_TYPE = "systemd";
      networking.networkmanager.unmanaged = [ "interface-name:netmaker*" ];

      networking.firewall = with cfg.firewall.ports; {
        allowedUDPPortRanges = [{
          from = networks.start;
          to = networks.start + networks.capacity - 1;
        }];
      };
    }
    {
      networking.firewall = with cfg.firewall; {
        trustedInterfaces = lib.mkIf trusted [ "netmaker+" ];
        interfaces."netmaker+" = lib.mkIf (!trusted) {
          allowedTCPPorts = ports.tcp;
          allowedTCPPortRanges = ports.tcpRanges;
          allowedUDPPorts = ports.udp;
          allowedUDPPortRanges = ports.udpRanges;
        };
      };
    }
  ]);
}
