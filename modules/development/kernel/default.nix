{ lib, pkgs, config, system, ... }:
let
  cfg = config.kdn.development.kernel;
in
{
  options.kdn.development.kernel = {
    enable = lib.mkEnableOption "kernel development dependencies";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gcc
      gnumake
      binutils
    ];
  };
}
