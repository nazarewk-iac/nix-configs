{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.monitoring.elasticsearch-stack;

  esCfg = config.services.elasticsearch;
  kCfg = config.services.kibana;
in
{
  options.kdn.monitoring.elasticsearch-stack = {
    enable = lib.mkEnableOption "elasticsearch + kibana";

    onDemand = lib.mkEnableOption "starting services on demand";

    packages.elasticsearch = lib.mkOption {
      type = lib.types.package;
      default = pkgs.elasticsearch7;
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    caddy.kibana = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.elasticsearch = {
        enable = true;
        listenAddress = cfg.listenAddress;
        package = cfg.packages.elasticsearch;
      };

      services.kibana = {
        enable = true;
        listenAddress = cfg.listenAddress;
        elasticsearch.ca = null;
        # TODO: report undefined variable https://github.com/NixOS/nixpkgs/blob/12303c652b881435065a98729eb7278313041e49/nixos/modules/services/search/kibana.nix#L124-L138
        elasticsearch.certificateAuthorities = [ ];
        elasticsearch.hosts = [
          "http://${cfg.listenAddress}:${toString esCfg.port}"
        ];
      };
    }
    (lib.mkIf cfg.onDemand {
      systemd.services.elasticsearch.wantedBy = lib.mkForce [ "kibana.service" ];
      systemd.services.kibana.wantedBy = lib.mkForce [ ];
    })
    (lib.mkIf (cfg.caddy.kibana != "") {
      services.caddy.virtualHosts."${cfg.caddy.kibana}".extraConfig = ''
        @denied not remote_ip private_ranges
        abort @denied
        reverse_proxy ${cfg.listenAddress}:${toString kCfg.port}
      '';
    })
  ]);
}

