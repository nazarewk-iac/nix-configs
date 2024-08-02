{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.security.secure-boot.tools;
in
{
  options.kdn.security.secure-boot.tools = {
    enable = lib.mkEnableOption "Secure Boot tooling setup";
  };

  config = lib.mkIf cfg.enable {
    kdn.security.disk-encryption.tools.enable = true;

    environment.systemPackages = with pkgs; [
      sbctl
    ];
  };
}
