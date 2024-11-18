{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.obs-studio;

  obs-studio-with-plugins = pkgs.wrapOBS.override {obs-studio = cfg.package;} {
    plugins = cfg.plugins;
  };
in {
  options.kdn.programs.obs-studio = {
    enable = lib.mkEnableOption "OBS Studio setup";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.obs-studio;
    };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs.obs-studio-plugins; [
        obs-gstreamer
        obs-pipewire-audio-capture
        obs-vkcapture
        wlrobs
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      obs-studio-with-plugins
    ];

    boot.kernelModules = [
      "v4l2loopback" # for getting OBS virtual camera to work
    ];
    home-manager.sharedModules = [
      {
        home.persistence."usr/config".directories = [
          ".config/obs-studio"
        ];
      }
    ];
  };
}
