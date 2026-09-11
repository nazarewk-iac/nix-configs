# CoreDNS as a suffix-rewrite forwarder, as a den aspect. It ports
# `modules/universal/services/coredns/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs CoreDNS with one server block per rewrite. A rewrite maps a local suffix onto a real
# suffix, then forwards the query to the upstream resolvers of that real suffix. Two snippets carry
# the shared opinion: `defaults-before` logs and reports an error, and `defaults-after` caches.
#
# ## The data stays with the consumer
#
# The aspect names no domain, no resolver and no interface. `rewrites` is an empty attribute set
# until a consumer fills it, because `types.attrsOf` supplies an empty value of its own.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. Nothing else. The generated CoreDNS text is byte-identical to the old module.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The per-instance options below sit inside an
#    `attrsOf submodule`, so the option walk cannot reach them.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.service-coredns.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.services.coredns;
    in
    {
      options.kdn.services.coredns.rewrites = lib.mkOption {
        example = lib.literalExpression ''
          {
            "internal.example." = {
              from = "svc.cluster.local.";
              upstreams = [ "127.0.0.1:5353" ];
            };
          }
        '';
        description = ''
          One CoreDNS server block per entry. The attribute name is the local suffix, unless the
          entry overrides `to`.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.to = lib.mkOption {
                type = lib.types.str;
                default = name;
                defaultText = lib.literalExpression "the attribute name";
                apply =
                  domain:
                  assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
                    `kdn.services.coredns.rewrites.*.to` must end with a '.': ${domain}
                  '';
                  domain;
                description = "The local suffix this server answers, with a trailing dot.";
              };

              options.from = lib.mkOption {
                type = lib.types.str;
                apply =
                  domain:
                  assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
                    `kdn.services.coredns.rewrites.*.from` must end with a '.': ${domain}
                  '';
                  domain;
                description = "The real suffix the upstreams answer, with a trailing dot.";
              };

              options.upstreams = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "The resolvers that answer `from`.";
              };

              options.binds = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "lo" ];
                description = "The interfaces this server block binds.";
              };

              options.port = lib.mkOption {
                type = lib.types.port;
                default = 53;
                description = "The port this server block binds. 53 is the DNS default.";
              };
            }
          )
        );
      };

      config.services.coredns.enable = true;

      config.services.coredns.config =
        lib.pipe
          [
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
            (lib.attrsets.mapAttrsToList (_: rewriteCfg: ''
              ${rewriteCfg.to}:${toString rewriteCfg.port} {
                bind ${builtins.concatStringsSep " " rewriteCfg.binds}
                import defaults-before
                rewrite name suffix .${rewriteCfg.to} .${rewriteCfg.from} answer auto
                forward ${rewriteCfg.from} ${builtins.concatStringsSep " " rewriteCfg.upstreams}
                import defaults-after
              }
            '') cfg.rewrites)
          ]
          [
            lib.flatten
            lib.mkMerge
          ];
    };
}
