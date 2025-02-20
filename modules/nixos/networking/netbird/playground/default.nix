{
  lib,
  pkgs,
  config,
  ...
}: let
  name = "playground";
  num = 18;

  cfg = config.kdn.networking.netbird."${name}";
  numStr = builtins.toString num;
  serviceName = "netbird-${name}";
  secrets = config.kdn.security.secrets.sops.secrets.default.netbird."${name}";
  secret = secrets."${cfg.type}";
in {
  options.kdn.networking.netbird."${name}" = {
    enable = lib.mkEnableOption "enable Netbird ${name} profile";

    type = lib.mkOption {
      type = with lib.types; enum ["ephemeral" "permanent"];
      default = "permanent";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # TODO: add/switch to `network-online.target` instead of `network.target` to properly initialize

      environment.systemPackages = with pkgs; [
        wireguard-tools
      ];

      services.netbird.clients."${name}" = {
        port = 51800 + num;
        dns-resolver.address = "127.0.0.${numStr}";
      };
      kdn.networking.router.kresd.rewrites."${name}.nb.net.int.kdn.im." = {
        from = "netbird.cloud.";
        upstreams = ["127.0.0.${numStr}"];
      };

      kdn.hw.disks.persist."usr/data".directories = [
        {
          directory = "/var/lib/${serviceName}";
          user = serviceName;
          group = serviceName;
          mode = "0700";
        }
      ];
    }
    (lib.mkIf config.kdn.security.secrets.allowed {
      systemd.services."${serviceName}" = {
        after = ["kdn-secrets.target"];
        requires = ["kdn-secrets.target"];
        serviceConfig.LoadCredential = [
          "setup-key:${secret.setup-key.path}"
        ];
        environment.NB_SETUP_KEY_FILE = "%d/setup-key";
        postStart = ''
          set -x
          nb='${lib.getExe config.services.netbird.clients."${name}".wrapper}'
          keyFile="''${NB_SETUP_KEY_FILE:-"/run/credentials/${serviceName}.service/setup-key"}"
          "$nb" status 2>&1 | ${lib.getExe pkgs.gnused} 's/^/STATUS:INIT: /g'
          while "$nb" status 2>&1 | grep --quiet 'Disconnected' ; do
            sleep 1
          done
          "$nb" status 2>&1 | ${lib.getExe pkgs.gnused} 's/^/STATUS:WAIT: /g'

          if "$nb" status 2>&1 | grep --quiet 'NeedsLogin' ; then
            echo "Using keyfile $(cut -b1-8 <"$keyFile")" >&2
            "$nb" up --setup-key-file="$keyFile"
          fi
        '';
      };
    })
  ]);
}
