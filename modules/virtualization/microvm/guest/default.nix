{ lib, pkgs, config, self, system, ... }:
with lib;
let
  cfg = config.kdn.virtualization.microvm.guest;
in
{
  options.kdn.virtualization.microvm.guest = {
    enable = lib.mkEnableOption "microvm guest config";
  };

  config = mkIf cfg.enable { };
}
