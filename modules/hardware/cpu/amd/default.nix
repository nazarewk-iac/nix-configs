{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.cpu.amd;
in
{
  options.kdn.hardware.cpu.amd = {
    enable = lib.mkEnableOption "AMD CPU setup";
  };

  config = lib.mkIf cfg.enable { };
}
