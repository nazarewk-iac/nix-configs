{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.toolset.print-3d;
in
{
  options.kdn.toolset.print-3d = {
    enable = lib.mkEnableOption "print-3d tooling";
  };

  config = lib.mkIf cfg.enable {
    # TODO: enable it back after https://github.com/NixOS/nixpkgs/issues/353961
    kdn.programs.blender.enable = false;
    # TODO: enable it back after https://github.com/NixOS/nixpkgs/issues/353863
    kdn.programs.orca-slicer.enable = false;
  };
}
