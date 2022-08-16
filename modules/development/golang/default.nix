{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.golang;
in
{
  options.nazarewk.development.golang = {
    enable = mkEnableOption "golang development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      go_1_19
      gccgo
      delve
    ];
  };
}
