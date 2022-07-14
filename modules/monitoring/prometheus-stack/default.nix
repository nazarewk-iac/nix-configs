{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.monitoring.prometheus-stack;
in
{
  options.nazarewk.monitoring.prometheus-stack = {
    enable = mkEnableOption "prometheus + grafana";

    pushgateway = {
      enable = mkEnableOption "prometheus + grafana";
    };

    retentionSize = mkOption {
      type = types.str;
      default = "5GB";
    };

    retentionTime = mkOption {
      type = types.str;
      default = "90d";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };
  };

  config = mkMerge [
    ({
      services.grafana = {
        enable = true;
        domain = "grafana.localhost";
        port = 2342;
        addr = cfg.listenAddress;

        provision.enable = true;
        provision.datasources = [
          {
            url = "http://${cfg.listenAddress}:9090";
            type = "prometheus";
            name = "Prometheus";
          }
        ];
      };

      services.grafana-image-renderer = {
        enable = true;
        provisionGrafana = true;
        settings.rendering.height = 1000;
        settings.rendering.width = 1900;
      };

      services.prometheus = {
        enable = true;
        port = 9090;
        listenAddress = cfg.listenAddress;
        retentionTime = cfg.retentionTime;
        extraFlags = [
          "--storage.tsdb.retention.size=${cfg.retentionSize}"
        ];
      };

      environment.systemPackages = with pkgs; [
        prometheus
        opentsdb
      ];
    })
    (mkIf cfg.pushgateway.enable {
      services.prometheus.pushgateway = {
        enable = true;
        web.listen-address = "${cfg.listenAddress}:9091";
      };
    })
  ];
}
