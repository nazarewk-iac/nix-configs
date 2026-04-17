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

  config = lib.mkIf cfg.enable {
    kdn.env.packages = with pkgs; [
      nickel
    ];
  };
}
