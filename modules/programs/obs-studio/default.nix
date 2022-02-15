{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.obs-studio;
in {
  options.nazarewk.programs.obs-studio = {
    enable = mkEnableOption "OBS Studio setup";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      obs-studio
      obs-studio-plugins.wlrobs
      obs-studio-plugins.obs-gstreamer
    ];
  };
}