{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # TODO: package, mirror & install KDE Connect through Nix https://kdeconnect.kde.org/download.html
      home.packages = with pkgs.nixcasks; [
      ];
    }
    {
      kdn.programs.firefox.enable = true;
      home.packages = with pkgs; [
        realvnc-vnc-viewer
      ];
    }
  ]);
}
