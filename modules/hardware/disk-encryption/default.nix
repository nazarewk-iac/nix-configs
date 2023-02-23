{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.disk-encryption;
in
{
  options.kdn.hardware.disk-encryption = {
    enable = lib.mkEnableOption "disk encryption wrapper setup";
  };

  config = lib.mkIf cfg.enable { };
}
