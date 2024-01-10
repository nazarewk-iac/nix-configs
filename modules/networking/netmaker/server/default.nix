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

    ports.turn = lib.mkOption {
      type = lib.types.ints.u16;
      default = 3479;
    };
    ports.turnApi = lib.mkOption {
      type = lib.types.ints.u16;
      default = 8089;
    };
    ports.networks.start = lib.mkOption {
      type = lib.types.ints.u16;
      default = 51821;
    };
    ports.networks.capacity = lib.mkOption {
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
      kdn.programs.direnv.enable = true; # to work with it

      kdn.virtualisation.containers.enable = true;
      virtualisation.podman.dockerSocket.enable = true;

      /* TODO: fix errors
          + netclient install
          {"time":"2024-01-09T21:29:29.859945417+01:00","level":"ERROR","source":"common_linux.go 178}","msg":"error checking /sbin/init","error":"exit status 2"}
          {"time":"2024-01-09T21:29:31.881457607+01:00","level":"ERROR","source":"common_linux.go 29}","msg":"open /sbin/netclient: no such file or directory"}
          {"time":"2024-01-09T21:29:31.881985779+01:00","level":"ERROR","source":"install.go 33}","msg":"daemon install error","error":"open /sbin/netclient: no such file or directory"}

          see https://github.com/gravitl/netclient/blob/79ffc7d2ea343a19f2a8157ae265dd1cffd9950f/daemon/common_linux.go#L177-L180
          Why is it even installed on system level if it could be a Docker service? https://docs.netmaker.org/netclient.html#docker
      */

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
        allowedTCPPorts = [
          cfg.ports.turn
          cfg.ports.turnApi
        ];
        allowedUDPPortRanges = [{
          from = with cfg.ports.networks; start;
          to = with cfg.ports.networks; start + capacity - 1;
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
