{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.programs.caddy;
in
{
  options.kdn.programs.caddy = {
    enable = mkEnableOption "Caddy web server";
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    systemd.services.caddy.serviceConfig.AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];

    environment.systemPackages = with pkgs; [
      config.services.caddy.package
    ];
  };
}
