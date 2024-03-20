{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.moss;

  coredns.port = 53;
  coredns.interfaces = [
    "ens3"
  ];
  coredns.upstreams = [
    "tls://1.1.1.1"
    "tls://8.8.8.8"
    "tls://1.0.0.1"
    "tls://8.8.4.4"
    "tls://9.9.9.9"
  ];
in
{
  options.kdn.profile.host.moss = {
    enable = lib.mkEnableOption "enable moss host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.hetzner.enable = true;
      security.sudo.wheelNeedsPassword = false;

      services.coredns.enable = false;
      services.coredns.config = ''
        (defaults) {
          bind ${builtins.concatStringsSep " " coredns.interfaces}
          # https://coredns.io/plugins/cache/
          #     [TTL] [ZONES...]
          cache 60 {
            #         CAPACITY  [TTL]   [MINTTL]
            success   10000     60      10
            #         CAPACITY  [TTL]   [MINTTL]
            denial    1000      5       1
            #         DURATION
            servfail  1s
          }
          log
          errors
        }

        nb.kdn.im:${builtins.toString coredns.port} {
          import defaults
          rewrite name suffix .nb.kdn.im. .netbird.cloud. answer auto
          forward netbird.cloud. /etc/resolv.conf
        }

        nb.nazarewk.pw:${builtins.toString coredns.port} {
          # TODO: DNSSEQ setup
          import defaults
          rewrite name suffix .nb.nazarewk.pw. .netbird.cloud. answer auto
          forward netbird.cloud. /etc/resolv.conf
        }

        .:${builtins.toString coredns.port} {
          import defaults
          forward . ${builtins.concatStringsSep " " coredns.upstreams} {
            tls
            policy random
            health_check 30s
          }
        }
      '';
      networking.firewall = {
        allowedTCPPorts = [ coredns.port ];
        allowedUDPPorts = [ coredns.port ];
      };
    }
  ]);
}
