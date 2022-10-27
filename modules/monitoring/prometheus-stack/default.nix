{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.monitoring.prometheus-stack;
in
{
  options.kdn.monitoring.prometheus-stack = {
    enable = lib.mkEnableOption "prometheus + grafana";

    caddy.grafana = mkOption {
      type = types.str;
      default = "";
    };

    pushgateway = {
      enable = lib.mkEnableOption "prometheus + grafana";
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
    (mkIf cfg.enable {
      services.grafana = {
        enable = true;
        settings.server = {
          domain = mkDefault "grafana.localhost";
          port = 2342;
          addr = cfg.listenAddress;
        };
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
    (mkIf cfg.pushgateway.enable {
      services.prometheus.pushgateway = {
        enable = true;
        web.listen-address = "${cfg.listenAddress}:9091";
      };
    })
    (mkIf (cfg.caddy.grafana != "") {
      services.grafana.settings.server.domain = cfg.caddy.grafana;
      services.caddy.virtualHosts."${cfg.caddy.grafana}".extraConfig = ''
        reverse_proxy ${cfg.listenAddress}:2342
      '';
    })
  ];
}

