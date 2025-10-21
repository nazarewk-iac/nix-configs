{
  lib,
  pkgs,
  config,
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
                type = with lib.types; uint;
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.resolved.enable = true;
        # services.resolved.dnssec = "allow-downgrade"; # this complains results are not signed
        services.resolved.dnssec = lib.mkDefault "false";
        services.resolved.dnsovertls = lib.mkDefault "opportunistic";
        services.resolved.llmnr = lib.mkDefault "true";
        services.resolved.extraConfig =
          let
            systemdDNS = lib.pipe cfg.nameservers [
              builtins.attrValues
              (builtins.filter (nsCfg: nsCfg.enable))
              (builtins.map (
                nsCfg:
                builtins.concatStringsSep "" [
                  nsCfg.addr
                  ":${nsCfg.port}"
                  (lib.strings.optionalString (nsCfg.interface != null) "%${nsCfg.interface}")
                  (lib.strings.optionalString (nsCfg.sni != null) "#${nsCfg.sni}")
                ]
              ))
              builtins.concatLists
            ];
          in
          ''
            ${lib.strings.optionalString (cfg.multicastDNS != null) ''
              MulticastDNS=${cfg.multicastDNS}
            ''}
            ${lib.strings.optionalString (systemdDNS != [ ]) ''
              DNS=${systemdDNS}
            ''}
          '';
      }
    ]
  );
}
