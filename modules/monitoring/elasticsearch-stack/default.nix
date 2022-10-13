{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.monitoring.elasticsearch-stack;

  esCfg = config.services.elasticsearch;
  kCfg = config.services.kibana;
in
{
  options.kdn.monitoring.elasticsearch-stack = {
    enable = mkEnableOption "elasticsearch + kibana";

    packages.elasticsearch = mkOption {
      type = types.package;
      default = pkgs.elasticsearch7;
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    caddy.kibana = mkOption {
      type = types.str;
      default = "";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.elasticsearch = {
        enable = true;
        listenAddress = cfg.listenAddress;
        package = cfg.packages.elasticsearch;
      };

      services.kibana = {
        enable = true;
        listenAddress = cfg.listenAddress;
        elasticsearch.hosts = [
          "http://${cfg.listenAddress}:${toString esCfg.port}"
        ];
      };
    })
    (mkIf (cfg.caddy.kibana != "") {
      services.caddy.virtualHosts."${cfg.caddy.kibana}".extraConfig = ''
        @denied not remote_ip private_ranges
        abort @denied
        reverse_proxy ${cfg.listenAddress}:${toString kCfg.port}
      '';
    })
  ];
}

