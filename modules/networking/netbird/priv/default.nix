{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.networking.netbird.priv;
in
{
  options.kdn.networking.netbird.priv = {
    enable = lib.mkEnableOption "enable Netbird priv profile";

    type = lib.mkOption {
      type = with lib.types; enum [ "ephemeral" "permanent" ];
      default = "permanent";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.netbird.clients.priv.port = 51819;

      services.netbird.clients.priv.dns-resolver.address = "127.0.0.19";
      kdn.networking.router.kresd.rewrites."priv.nb.net.int.kdn.im.".from = "netbird.cloud.";
      kdn.networking.router.kresd.rewrites."priv.nb.net.int.kdn.im.".upstreams = [ "127.0.0.19" ];

      environment.persistence."usr/data".directories = [
        { directory = "/var/lib/netbird-priv"; user = "netbird-priv"; group = "netbird-priv"; mode = "0700"; }
      ];
    }
    (lib.mkIf config.kdn.security.secrets.allowed {
      # Netbird automated login
      sops.templates."netbird-priv.env" = {
        owner = "netbird-priv";
        group = "netbird-priv";
        content = ''
          NB_SETUP_KEY="${config.sops.placeholder."default/netbird-priv/${cfg.type}/setup-key"}"
        '';
      };
      systemd.services.netbird-priv.serviceConfig.EnvironmentFile = config.sops.templates."netbird-priv.env".path;
      systemd.services.netbird-priv.postStart = ''
        nb='${lib.getExe config.services.netbird.clients.priv.wrapper}'
        if "$nb" status 2>&1 | grep --quiet 'NeedsLogin' ; then
          cut -b1-8 <<<"$NB_SETUP_KEY"
          "$nb" up
        fi
      '';
    })
  ]);
}
