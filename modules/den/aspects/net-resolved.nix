# The systemd-resolved client of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/resolved/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns systemd-resolved on with four opinions: DNSSEC off, DNS-over-TLS opportunistic, LLMNR on,
# and multicast DNS from the consumer. It renders the `DNS` line from the `nameservers` set, and each
# entry may name a port, an interface and a TLS server name.
#
# Every default uses `lib.mkDefault`, so a consumer overrides any one of the four.
#
# ## Class list: `nixos`
#
# systemd-resolved is Linux only, and the old module puts every effect behind a `nixos` guard.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **Two evaluation bugs go.** The old render pipes the address strings through
#    `builtins.concatLists`, and `concatLists` needs a list of lists — so the old code aborts with
#    `value is a string while a list was expected` as soon as one nameserver is present. The old code
#    also interpolates the port with `":${nsCfg.port}"`, and the port is an integer — so it aborts
#    with `cannot coerce an integer to a string`. Both faults hide today, because an empty
#    `nameservers` set never reaches either line. This port drops the `concatLists` step and it wraps
#    the port in `toString`. The empty case renders the same empty list as before.
# 3. **`multicastDNS` keeps the `null` default.** nixpkgs drops a null settings key before it writes
#    `resolved.conf`, so a null writes no line.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The per-nameserver `enable` flag sits inside an
#    `attrsOf submodule`, so the option walk cannot reach it.
# 3. **No custom module argument.** The target module takes `config` and `lib` only.
{ ... }:
{
  kdn.net-resolved.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.networking.resolved;
    in
    {
      options.kdn.networking.resolved.multicastDNS = lib.mkOption {
        type =
          with lib.types;
          nullOr (enum [
            "true"
            "false"
            "resolve"
          ]);
        default = null;
        example = "resolve";
        description = ''
          The `MulticastDNS` value of `resolved.conf`. `null` writes no line, so systemd keeps its
          own default.
        '';
      };

      options.kdn.networking.resolved.nameservers = lib.mkOption {
        default = { };
        example = lib.literalExpression ''
          {
            "192.0.2.53" = { };
            "2001:db8::53".sni = "dns.example.org";
          }
        '';
        description = ''
          The recursive resolvers this machine queries. The attribute name is the address, and a
          disabled entry stays out of the rendered line.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.enable = lib.mkOption {
                type = with lib.types; bool;
                default = true;
                description = "Put this resolver in the rendered `DNS` line.";
              };
              options.addr = lib.mkOption {
                type = with lib.types; str;
                default = name;
                defaultText = lib.literalExpression "the attribute name";
                description = "The address of this resolver.";
              };
              options.port = lib.mkOption {
                type = lib.types.port;
                default = 53;
                description = "The port of this resolver.";
              };
              options.interface = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                example = "lan0";
                description = "The interface this resolver is reachable through. `null` names none.";
              };
              options.sni = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                example = "dns.example.org";
                description = "The TLS server name of this resolver. `null` names none.";
              };
            }
          )
        );
      };

      config = {
        services.resolved.enable = true;
        services.resolved.settings.Resolve.DNSSEC = lib.mkDefault "false";
        services.resolved.settings.Resolve.DNSOverTLS = lib.mkDefault "opportunistic";
        services.resolved.settings.Resolve.LLMNR = lib.mkDefault "true";
        services.resolved.settings.Resolve.MulticastDNS = cfg.multicastDNS;
        services.resolved.settings.Resolve.DNS = lib.pipe cfg.nameservers [
          builtins.attrValues
          (builtins.filter (nsCfg: nsCfg.enable))
          (map (
            nsCfg:
            builtins.concatStringsSep "" [
              nsCfg.addr
              ":${toString nsCfg.port}"
              (lib.strings.optionalString (nsCfg.interface != null) "%${nsCfg.interface}")
              (lib.strings.optionalString (nsCfg.sni != null) "#${nsCfg.sni}")
            ]
          ))
        ];
      };
    };
}
