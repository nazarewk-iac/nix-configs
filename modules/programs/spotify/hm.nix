{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.spotify;
in
{
  options.kdn.programs.spotify = {
    enable = lib.mkEnableOption "spotify setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.spotify = {
        enable = true;
        package.original = pkgs.spotifywm;
        dirs.cache = [ "spotify" ];
        dirs.config = [ "spotify" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
  ]);
}
