{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.networking.tailscale;
  # `or { }` keeps this module evaluable when the sops tree holds no tailscale keys.
  authKeys = config.kdn.security.secrets.sops.secrets.default.tailscale.default.auth_keys or { };
in
{
  options.kdn.networking.tailscale = {
    enable = lib.mkEnableOption "Tailscale client";
    auth_key = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "nixos";
      description = ''
        Name of a sops key under `default/tailscale/default/auth_keys/`.
        `null` means the client joins with no auth key file.
        An assertion checks the name against the discovered keys, but only when that set is not
        empty. A type cannot do the check: a type built from the sops tree stops an adopter who
        has no sops file.
      '';
    };
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          services.tailscale.enable = true;
          services.tailscale.openFirewall = true;
          kdn.disks.persist."usr/data".directories = [
            "/var/lib/tailscale"
          ];
        }
        {
          assertions = [
            {
              assertion = cfg.auth_key == null || authKeys == { } || authKeys ? "${cfg.auth_key}";
              message = "kdn.networking.tailscale.auth_key `${toString cfg.auth_key}` is not a discovered sops key. Known keys: ${builtins.concatStringsSep ", " (builtins.attrNames authKeys)}.";
            }
          ];
        }
        (lib.mkIf (cfg.auth_key != null && authKeys ? "${cfg.auth_key}") {
          services.tailscale.authKeyFile = lib.mkDefault authKeys."${cfg.auth_key}".path;
        })
      ]
    )
  );
}
