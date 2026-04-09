{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.nickel;
in
{
  options.kdn.development.nickel = {
    enable = lib.mkEnableOption "nickel development/debugging";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        nickel
      ];
    }
  );
}
