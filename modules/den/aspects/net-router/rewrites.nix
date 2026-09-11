# The CoreDNS suffix-rewrite bridge of the router.
#
# It is one target module of the `net-router` aspect family. ./net-router.nix declares the family
# and ../README.md states the rules.
#
# ## What it holds
#
# | Concern | Old line range |
# |---|---|
# | `coredns.localAddress` option | 637-640 |
# | `kresd.rewrites` option | 662-697 |
# | CoreDNS rewrite servers plus the matching kresd STUB upstreams | 1761-1780 |
#
# Each rewrite makes one CoreDNS server on the local address. It also makes one kresd STUB
# upstream, so kresd sends the rewritten suffix to that CoreDNS server.
#
# It writes `kresd.upstreams`, which ./dns.nix declares. The family `includes` list supplies that
# file.
#
# ## What the port changes
#
# 1. The outer `lib.mkIf (cfg.kresd.rewrites != { })` guard goes. Inclusion of the aspect is now
#    the switch. So a consumer that includes this aspect and sets no rewrite now starts CoreDNS
#    with an empty rewrite set.
# 2. The CoreDNS enable line goes. The family `includes` list names the CoreDNS service aspect,
#    which starts CoreDNS with no gate.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kdn.networking.router;
in
{
  imports = [ ../../common/host-name.nix ];

  options.kdn.networking.router = {
    coredns.localAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.2";
    };

    kresd.rewrites = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@rewriteArgs:
          {
            options = {
              to = lib.mkOption {
                type = with lib.types; str;
                default = name;
                apply =
                  domain:
                  assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
                    `kdn.networking.router.kresd.rewrites.*.to` must end with a '.', invalid entry: ${domain}
                  '';
                  domain;
              };

              from = lib.mkOption {
                type = with lib.types; str;
                apply =
                  domain:
                  assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
                    `kdn.networking.router.kresd.rewrites.*.from` must end with a '.', invalid entry: ${domain}
                  '';
                  domain;
              };

              upstreams = lib.mkOption {
                type = with lib.types; listOf str;
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkMerge [
    {
      # TODO: watch out for kresd 6.0+ version for native support of rewrites
      kdn.services.coredns.rewrites = builtins.mapAttrs (_: rewriteCfg: {
        inherit (rewriteCfg) from to upstreams;
        binds = [ cfg.coredns.localAddress ];
        port = 53;
      }) cfg.kresd.rewrites;
      kdn.networking.router.kresd.upstreams = lib.pipe cfg.kresd.rewrites [
        (lib.attrsets.mapAttrsToList (
          _: rewriteCfg: {
            description = "redirect to ${rewriteCfg.to} from ${rewriteCfg.from}";
            type = "STUB";
            nameservers = [ cfg.coredns.localAddress ];
            domains = [ rewriteCfg.to ];
          }
        ))
        lib.mkBefore
      ];
    }
  ];
}
