{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.editors.video;
in
{
  options.kdn.programs.editors.video.enable = lib.mkEnableOption "Video editing software";

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [
      {
        kdn.programs.apps.kdenlive = {
          enable = true;
          package.original = pkgs.kdePackages.kdenlive;
          dirs.cache = [ ];
          dirs.config = [ "kdenlive" ];
          dirs.data = [
            "kdenlive"
            "kxmlgui5/kdenlive"
          ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
          files.config = [
            "kdenliverc"
            "kdenlive-layoutsrc"
          ];
          files.data = [
            "knewstuff3"
          ];
        };
        kdn.programs.apps.shotcut = {
          enable = true;
          dirs.cache = [ ];
          dirs.config = [ "Meltytech/Shotcut" ];
          dirs.data = [ "Meltytech/Shotcut" ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
          files.config = [ "Meltytech/Shotcut.conf" ];
        };
        kdn.programs.apps.handbrake = {
          enable = true;
          dirs.cache = [ ];
          dirs.config = [
            "HandBrake"
            "ghb"
          ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ];
  };
}
