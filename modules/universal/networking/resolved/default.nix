{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.networking.resolved;
in
{
  options.kdn.networking.resolved = {
    enable = lib.mkEnableOption "resolved client";
    multicastDNS = lib.mkOption {
      type =
        with lib.types;
        nullOr (enum [
          "true"
          "false"
          "resolve"
        ]);
      default = null;
    };
    domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "~." ];
      description = ''
        The `Domains=` line of `resolved.conf`. A `~` prefix makes it a **routing** domain, so
        resolved sends every matching query to the `DNS=` servers instead of to the per-link
        server it learned from DHCP or a VPN.

        This is the knob for a host that runs its own resolver for the site zones but is also
        handed a resolver by DHCP: without a routing domain the per-link server wins and the host
        cannot resolve the names it manages itself.

        Watch for a loop: the recipient must not forward back to resolved's stub at `127.0.0.53`.
      '';
    };
    nameservers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkOption {
                type = with lib.types; bool;
                default = true;
              };
              addr = lib.mkOption {
                type = with lib.types; str;
                default = name;
              };
              port = lib.mkOption {
                type = with lib.types; port;
                default = 53;
              };
              interface = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
              };
              sni = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
              };
            };
          }
        )
      );
      default = { };
    };
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          services.resolved.enable = true;
          services.resolved.settings.Resolve.DNSSEC = lib.mkDefault "false";
          services.resolved.settings.Resolve.DNSOverTLS = lib.mkDefault "opportunistic";
          services.resolved.settings.Resolve.LLMNR = lib.mkDefault "true";
          services.resolved.settings.Resolve.MulticastDNS = cfg.multicastDNS;
          services.resolved.settings.Resolve.Domains = cfg.domains;
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
        }
      ]
    )
  );
}
