{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.obs-studio;
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
        input-overlay # display keystrokes
        obs-backgroundremoval
        # obs-gstreamer # never used it?
        obs-pipewire-audio-capture
        wlrobs # "Wayland output(dmabuf) / (scpy)
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    programs.obs-studio.enable = true;
    programs.obs-studio.package = cfg.package;
    programs.obs-studio.plugins = cfg.plugins;
    programs.obs-studio.enableVirtualCamera = true;

    home-manager.sharedModules = [
      {
        kdn.disks.persist."usr/config".directories = [
          ".config/obs-studio"
        ];
      }
    ];
  };
}
