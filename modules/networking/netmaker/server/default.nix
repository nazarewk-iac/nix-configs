{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netmaker.server;

  src = pkgs.fetchFromGitHub {
    owner = "gravitl";
    repo = "netmaker";
    rev = cfg.version;
    sha256 = cfg.sha256;
  };
in
{
  options.kdn.networking.netmaker.server = {
    enable = lib.mkEnableOption "Netmaker server";
    version = lib.mkOption {
      type = with lib.types; str;
      default = "v0.21.2";
    };
    sha256 = lib.mkOption {
      type = with lib.types; str;
      default = "sha256-zC2IWYhHgwVbmN9X0q+/unu7E0sP211UbIIp1kvynoQ=";
    };

    mode = lib.mkOption {
      type = with lib.types; enum [
        "nm-quick"
        #"binary"
      ];
      default = "nm-quick";
    };
    type = lib.mkOption {
      type = with lib.types; enum [
        "ce"
        "pro"
      ];
      default = "ce";
    };
    domain = lib.mkOption {
      type = with lib.types; str;
    };
    publicIp = lib.mkOption {
      type = with lib.types; str;
      default = "";
    };

    stunList = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "stun1.netmaker.io:3478"
        "stun2.netmaker.io:3478"
        "stun1.l.google.com:19302"
        "stun2.l.google.com:19302"
      ];
    };

    ports.turn = {
      type = lib.types.ints.u16;
      default = 3479;
    };
    ports.turnApi = {
      type = lib.types.ints.u16;
      default = 8089;
    };
    ports.networks.start = {
      type = lib.types.ints.u16;
      default = 51821;
    };
    ports.networks.capacity = {
      type = lib.types.ints.u16;
      default = 10;
    };

    environment = lib.mkOption {
      description = "environment variables for Netmaker, see https://docs.netmaker.io/server-installation.html#server-configuration-reference";
      type = with lib.types; attrsOf str;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.mode == "nm-quick") {
      # TODO: move Caddy out of docker-compose?
      # TODO: fix certificates issuance (switch to DNS challenge?)
      # TODO: issue certificates for wildcard domain instead, see https://caddyserver.com/docs/caddyfile/patterns#wildcard-certificates
      environment.systemPackages = [
        pkgs.kdn.netmaker-scripts
      ] ++ pkgs.kdn.netmaker-scripts.passthru.deps;
    })
    {
      kdn.services.caddy.enable = lib.mkForce false;

      networking.firewall = {
        #allowedTCPPorts = [
        #  cfg.ports.turn
        #  cfg.ports.turnApi
        #];
        allowedUDPPortRanges = [{
          #from = with cfg.ports.networks; start;
          #to = with cfg.ports.networks; start + capacity - 1;
          from = 51821;
          to = 51830;
        }];
      };
    }
    {
      # kdn.networking.netmaker.server.environment = {
      #   STUN_LIST = builtins.concatStringsSep "," cfg.stunList;
      #   BROKER_ENDPOINT = "wss://broker.${cfg.domain}";
      #   SERVER_NAME = cfg.domain;
      #   SERVER_API_CONN_STRING = "${cfg.environment.SERVER_HTTP_HOST}:443";
      #   SERVER_HTTP_HOST = "api.${cfg.domain}";
      #   TURN_SERVER_HOST = "turn.${cfg.domain}";
      #   TURN_SERVER_API_HOST = "https://turnapi.${cfg.domain}";
      # };
    }
  ]);
}
