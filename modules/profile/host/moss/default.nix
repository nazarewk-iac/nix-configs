{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.moss;

  netbird.interface = "nb-priv";
  netbird.trusted = false;

  coredns.openToInternet = false;
  coredns.onNetbird = true;
  coredns.port = 53;
  coredns.interfaces = [
    "lo"
  ]
  ++ lib.optional coredns.openToInternet "ens3"
  ++ lib.optional coredns.onNetbird netbird.interface;
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
      kdn.profile.machine.hetzner.ipv6Address = "2a01:4f8:1c0c:56e4::1/64";
      security.sudo.wheelNeedsPassword = false;

      services.coredns.enable = true;
      services.coredns.config = ''
        (defaults-before) {
          bind ${builtins.concatStringsSep " " coredns.interfaces}
          log
          errors
        }

        (defaults-after) {
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
        }

        nb.kdn.im:${builtins.toString coredns.port} {
          import defaults-before
          rewrite name suffix .nb.kdn.im. .netbird.cloud. answer auto
          forward netbird.cloud. /etc/resolv.conf
          import defaults-after
        }

        nb.nazarewk.pw:${builtins.toString coredns.port} {
          # TODO: DNSSEQ setup
          import defaults-before
          rewrite name suffix .nb.nazarewk.pw. .netbird.cloud. answer auto
          forward netbird.cloud. /etc/resolv.conf
          import defaults-after
        }

        .:${builtins.toString coredns.port} {
          import defaults-before
          forward . ${builtins.concatStringsSep " " coredns.upstreams} {
            tls
            policy random
            health_check 30s
          }
          import defaults-after
        }
      '';
    }
    (lib.mkIf coredns.openToInternet {
      networking.firewall.allowedTCPPorts = [ coredns.port ];
      networking.firewall.allowedUDPPorts = [ coredns.port ];
    })
    (lib.mkIf netbird.trusted { networking.firewall.trustedInterfaces = [ netbird.interface ]; })
    (lib.mkIf (!netbird.trusted && coredns.onNetbird) {
      networking.firewall.interfaces."${netbird.interface}" = {
        allowedTCPPorts = [ coredns.port ];
        allowedUDPPorts = [ coredns.port ];
      };
    })
  ]);
}
