{
  lib,
  pkgs,
  config,
  inputs,
  system,
  ...
}: let
  cfg = config.kdn.development.nickel;
in {
  options.kdn.development.nickel = {
    enable = lib.mkEnableOption "nickel development/debugging";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nickel
    ];
  };
}
