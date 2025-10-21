{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.toolset.print-3d;
in
{
  options.kdn.toolset.print-3d = {
    enable = lib.mkEnableOption "print-3d tooling";
  };

  config = lib.mkIf cfg.enable {
    kdn.programs.blender.enable = true;
    /*
      TODO: re-enable when build is fixed
       see https://github.com/NixOS/nixpkgs/issues/36957
       see https://nixpk.gs/pr-tracker.html?pr=369729
    */
    # kdn.programs.orca-slicer.enable = true;
  };
}
