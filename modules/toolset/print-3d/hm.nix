{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.toolset.print-3d;
in
{
  options.kdn.toolset.print-3d = {
    enable = lib.mkEnableOption "print-3d tooling";
  };

  config = lib.mkIf cfg.enable {
    kdn.programs.blender.enable = true;
    kdn.programs.orca-slicer.enable = true;
  };
}
