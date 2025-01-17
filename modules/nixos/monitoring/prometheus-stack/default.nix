{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.monitoring.prometheus-stack;
in {
  options.kdn.monitoring.prometheus-stack = {
    enable = lib.mkEnableOption "prometheus + grafana";

    caddy.grafana = lib.mkOption {
      type = lib.types.str;
      default = "";
    };

    pushgateway = {
      enable = lib.mkEnableOption "prometheus + grafana";
    };

    retentionSize = lib.mkOption {
      type = lib.types.str;
      default = "5GB";
    };

    retentionTime = lib.mkOption {
      type = lib.types.str;
      default = "90d";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.grafana = {
        enable = true;
        settings.server = {
          domain = lib.mkDefault "grafana.localhost";
          port = 2342;
          addr = cfg.listenAddress;
        };
        provision.enable = true;
        provision.datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://${cfg.listenAddress}:9090";
          }
        ];
      };

      services.grafana-image-renderer = {
        enable = false; # grafana-image-renderer requires older Node JS
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
    (lib.mkIf cfg.pushgateway.enable {
      services.prometheus.pushgateway = {
        enable = true;
        web.listen-address = "${cfg.listenAddress}:9091";
      };
    })
    (lib.mkIf (cfg.caddy.grafana != "") {
      services.grafana.settings.server.domain = cfg.caddy.grafana;
      services.caddy.virtualHosts."${cfg.caddy.grafana}".extraConfig = ''
        reverse_proxy ${cfg.listenAddress}:2342
      '';
    })
  ];
}
