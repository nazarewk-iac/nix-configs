{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.ente-photos;
in
{
  options.kdn.programs.ente-photos = {
    enable = lib.mkEnableOption "ente-photos-desktop setup";
    package = lib.mkPackageOption pkgs [ "kdn" "ente-photos-desktop" ] { };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.ente-photos-desktop = {
        enable = true;
        package.original = cfg.package;
        dirs.cache = [ "ente" ];
        dirs.config = [ "ente" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
  ]);
}
