{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.cue;
in {
  options.nazarewk.development.cue = {
    enable = mkEnableOption "CUE language development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      cue
    ];
  };
}