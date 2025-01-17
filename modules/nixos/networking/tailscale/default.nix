{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.networking.tailscale;
  authKeys = config.kdn.security.secrets.sops.secrets.default.tailscale.default.auth_keys;
in {
  options.kdn.networking.tailscale = {
    enable = lib.mkEnableOption "Tailscale client";
    auth_key = lib.mkOption {
      type = lib.types.enum (
        [null]
        ++ builtins.attrNames authKeys
      );
      default = "nixos";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.tailscale.enable = true;
      services.tailscale.openFirewall = true;
      kdn.hardware.disks.persist."usr/data".directories = [
        "/var/lib/tailscale"
      ];
    }
    (lib.mkIf (cfg.auth_key != null) {
      services.tailscale.authKeyFile = lib.mkDefault authKeys."${cfg.auth_key}".path;
    })
  ]);
}
