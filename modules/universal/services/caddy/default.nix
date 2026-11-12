{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.services.caddy;
in
{
  options.kdn.services.caddy = {
    enable = lib.mkEnableOption "Caddy web server";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifTypes [ "nixos" ] {
        kdn.env.packages = with pkgs; [
          config.services.caddy.package
        ];
        services.caddy.enable = true;
        # No public ACME: the hosts trust only the KDN CA. Caddy's automatic HTTPS starts an
        # ACME order for every site address that carries no `tls` directive, so turn it off for
        # the whole process. A consumer's vhost must load its leaf with `tls <cert> <key>`.
        services.caddy.globalConfig = "auto_https off";

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        systemd.services.caddy.serviceConfig.AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      })
    ]
  );
}
