{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.networking.netbird.priv;
in {
  options.kdn.networking.netbird.priv = {
    enable = lib.mkEnableOption "enable Netbird priv profile";

    type = lib.mkOption {
      type = with lib.types; enum ["ephemeral" "permanent"];
      default = "permanent";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # TODO: add/switch to `network-online.target` instead of `network.target` to properly initialize
      services.netbird.clients.priv.port = 51819;

      environment.systemPackages = with pkgs; [
        wireguard-tools
      ];

      services.netbird.clients.priv.dns-resolver.address = "127.0.0.19";
      kdn.networking.router.kresd.rewrites."priv.nb.net.int.kdn.im.".from = "netbird.cloud.";
      kdn.networking.router.kresd.rewrites."priv.nb.net.int.kdn.im.".upstreams = ["127.0.0.19"];

      kdn.hw.disks.persist."usr/data".directories = [
        {
          directory = "/var/lib/netbird-priv";
          user = "netbird-priv";
          group = "netbird-priv";
          mode = "0700";
        }
      ];
    }
    (lib.mkIf config.kdn.security.secrets.allowed {
      systemd.services.netbird-priv.after = ["kdn-secrets.target"];
      systemd.services.netbird-priv.requires = ["kdn-secrets.target"];
      systemd.services.netbird-priv.environment.NB_SETUP_KEY_FILE = config.kdn.security.secrets.sops.secrets.default.netbird-priv."${cfg.type}".setup-key.path;
      systemd.services.netbird-priv.postStart = ''
        set -x
        nb='${lib.getExe config.services.netbird.clients.priv.wrapper}'
        keyFile="''${NB_SETUP_KEY_FILE:-"${config.kdn.security.secrets.sops.secrets.default.netbird-priv."${cfg.type}".setup-key.path}"}"
        if "$nb" status 2>&1 | grep --quiet 'NeedsLogin' ; then
          echo "Using keyfile $(cut -b1-8 <"$keyFile")" >&2
          "$nb" up --setup-key-file="$keyFile"
        fi
      '';
    })
  ]);
}
