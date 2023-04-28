{ lib, pkgs, config, ... }:
let
cfg = config.kdn.programs.caddy;
in
{
options.kdn.programs.caddy = {
enable = lib.mkEnableOption "Caddy web server";
};

config = lib.mkIf cfg.enable {
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
