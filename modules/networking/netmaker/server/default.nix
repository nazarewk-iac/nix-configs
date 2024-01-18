{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netmaker.server;
in
{
  options.kdn.networking.netmaker.server = {
    enable = lib.mkEnableOption "Netmaker server";

    mode = lib.mkOption {
      type = with lib.types; enum [
        "nm-quick"
        #"binary"
      ];
      default = "nm-quick";
    };
    firewall.ports = {
      dns = lib.mkOption {
        type = with lib.types; port;
        default = 53;
      };
      turn = lib.mkOption {
        type = with lib.types; port;
        default = 3479;
      };
      turnApi = lib.mkOption {
        type = with lib.types; port;
        default = 8089;
      };
      networks.start = lib.mkOption {
        type = with lib.types; port;
        default = 51821;
      };
      networks.capacity = lib.mkOption {
        type = with lib.types; port;
        default = 10;
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.mode == "nm-quick") {
      kdn.programs.direnv.enable = true; # to work with it

      kdn.virtualisation.containers.enable = true;
      virtualisation.podman.dockerSocket.enable = true;

      # TODO: move Caddy out of docker-compose?
      # TODO: fix certificates issuance (switch to DNS challenge?)
      # TODO: issue certificates for wildcard domain instead, see https://caddyserver.com/docs/caddyfile/patterns#wildcard-certificates
      environment.systemPackages = [
        pkgs.kdn.netmaker-scripts
        pkgs.sqlite
      ] ++ pkgs.kdn.netmaker-scripts.passthru.deps;
    })
    {
      kdn.services.caddy.enable = lib.mkForce false;

      networking.firewall = with cfg.firewall.ports; {
        allowedTCPPorts = [
          # note: TURN was removed in 0.22.0
          #turn
          #turnApi
          dns
        ];
        allowedUDPPorts = [
          dns
        ];
        allowedUDPPortRanges = [{
          from = networks.start;
          to = networks.start + networks.capacity - 1;
        }];
      };
    }
  ]);
}
