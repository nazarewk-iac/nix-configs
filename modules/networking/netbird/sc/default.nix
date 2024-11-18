{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.networking.netbird.sc;
in {
  options.kdn.networking.netbird.sc = {
    enable = lib.mkEnableOption "enable Netbird sc profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.netbird.clients.sc.autoStart = false;
      services.netbird.clients.sc.port = 51818;
      services.netbird.clients.sc.dns-resolver.address = "127.0.0.18";
      kdn.networking.router.kresd.rewrites."sc.nb.net.int.kdn.im.".from = "netbird.cloud.";
      kdn.networking.router.kresd.rewrites."sc.nb.net.int.kdn.im.".upstreams = ["127.0.0.18"];

      environment.persistence."usr/data".directories = [
        {
          directory = "/var/lib/netbird-sc";
          user = "netbird-sc";
          group = "netbird-sc";
          mode = "0700";
        }
      ];
    }
  ]);
}
