{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.service.coredns;
in
{
  options.kdn.service.coredns = {
    enable = lib.mkEnableOption "CoreDNS";

    rewrites = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@rewriteArgs: {
        options = {
          to = lib.mkOption {
            type = with lib.types; str;
            default = name;
          };

          from = lib.mkOption {
            type = with lib.types; str;
          };

          upstreams = lib.mkOption {
            type = with lib.types; listOf str;
          };

          binds = lib.mkOption {
            type = with lib.types; listOf str;
            default = [ "lo" ];
          };

          port = lib.mkOption {
            type = with lib.types; port;
            default = 53;
          };
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.coredns.enable = true;
      services.coredns.config = lib.pipe [
        (lib.mkBefore ''
          (defaults-before) {
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
        '')
        (lib.attrsets.mapAttrsToList
          (_: rewriteCfg: ''
            ${rewriteCfg.to}:${builtins.toString rewriteCfg.port} {
              bind ${builtins.concatStringsSep " " rewriteCfg.binds}
              import defaults-before
              rewrite name suffix .${rewriteCfg.to}. .${rewriteCfg.from}. answer auto
              forward ${rewriteCfg.from}. ${builtins.concatStringsSep " " rewriteCfg.upstreams}
              import defaults-after
            }
          '')
          cfg.rewrites)
      ] [
        lib.flatten
        lib.mkMerge
      ];
    }
  ]);
}
