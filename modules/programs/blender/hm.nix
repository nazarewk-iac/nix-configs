{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.blender;
in
{
  options.kdn.programs.blender = {
    enable = lib.mkEnableOption "blender setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.blender = {
        enable = true;
        dirs.cache = [ "blender" ];
        dirs.config = [ "blender" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
  ]);
}
