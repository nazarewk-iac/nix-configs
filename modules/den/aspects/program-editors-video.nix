# `kdn.programs.editors.video`, as a den aspect.
# It ports `modules/universal/programs/editors/video/default.nix`.
{ kdn, ... }:
{
  kdn.program-editors-video.includes = [ kdn.apps ];

  kdn.program-editors-video.homeManager =
    { pkgs, ... }:
    {
      config.kdn.apps = {
        kdenlive = {
          enable = true;
          package.original = pkgs.kdePackages.kdenlive;
          dirs.config = [ "kdenlive" ];
          dirs.data = [
            "kdenlive"
            "kxmlgui5/kdenlive"
          ];
          files.config = [
            "kdenliverc"
            "kdenlive-layoutsrc"
          ];
          files.data = [ "knewstuff3" ];
        };

        shotcut = {
          enable = true;
          dirs.config = [ "Meltytech/Shotcut" ];
          dirs.data = [ "Meltytech/Shotcut" ];
          files.config = [ "Meltytech/Shotcut.conf" ];
        };

        handbrake = {
          enable = true;
          dirs.config = [
            "HandBrake"
            "ghb"
          ];
        };
      };
    };
}
