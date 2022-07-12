{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.monitoring.prometheus-stack;
in
{
  options.nazarewk.monitoring.prometheus-stack = {
    enable = mkEnableOption "prometheus + grafana";
  };

  config = {
    services.grafana = {
      enable = true;
      domain = "grafana.localhost";
      port = 2342;
      addr = "127.0.0.1";
    };

    services.prometheus = {
      enable = true;
      port = 9090;
      listenAddress = "127.0.0.1";
      retentionTime = "30d";
      extraFlags = [
        "--storage.tsdb.retention.size=1GB"
      ];
    };

    environment.systemPackages = with pkgs; [
      prometheus
      opentsdb
    ];
  };
}
