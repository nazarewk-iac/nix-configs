{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.programs.obs-studio;

  obs-studio-with-plugins = pkgs.wrapOBS.override { obs-studio = cfg.package; } {
    plugins = cfg.plugins;
  };
in
{
  options.kdn.programs.obs-studio = {
    enable = mkEnableOption "OBS Studio setup";
    package = mkOption {
      type = types.package;
      default = pkgs.obs-studio;
    };
    plugins = mkOption {
      type = types.listOf types.package;
      default = with pkgs.obs-studio-plugins; [
        obs-gstreamer
        obs-pipewire-audio-capture
        obs-vkcapture
        wlrobs
      ];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      obs-studio-with-plugins
    ];
  };
}
