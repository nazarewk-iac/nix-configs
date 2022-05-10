{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.networking.wireguard.server;
in {
  options.nazarewk.networking.wireguard.server = {
    enable = mkEnableOption "wireguard setup setup";
  };

  config = mkIf cfg.enable {
    networking.nat.enable = true;
    networking.nat.externalInterface = "eth0";
    networking.nat.internalInterfaces = [ "wg0" ];
    networking.firewall = {
      allowedUDPPorts = [ 51820 ];
    };
  };
}
