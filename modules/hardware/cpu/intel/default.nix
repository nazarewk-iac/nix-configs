{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.cpu.intel;
in
{
  options.kdn.hardware.cpu.intel = {
    enable = lib.mkEnableOption "intel CPU setup";
  };

  config = lib.mkIf cfg.enable { };
}
