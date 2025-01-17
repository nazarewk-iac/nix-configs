{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.security.secure-boot;
in {
  options.kdn.security.secure-boot = {
    enable = lib.mkEnableOption "Secure Boot setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.toolset.fs.encryption.enable = true;
    }
    {
      # Lanzaboote currently replaces the systemd-boot module.
      # This setting is usually set to true in configuration.nix
      # generated at installation time. So we force it to false
      # for now.
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/etc/secureboot";
      };
    }
  ]);
}
