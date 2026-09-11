{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.print-3d;
in
{
  options.kdn.toolset.print-3d = {
    enable = lib.mkEnableOption "print-3d tooling";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.toolset.print-3d = lib.mkDefault cfg; } ];
      })
      (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) {
        # Keep the plain priority. `programs/blender` forwards its whole `cfg` into Home Manager at
        # `lib.mkDefault`, so a `lib.mkDefault true` here makes a 1000-to-1000 tie and stops the
        # evaluation of every Home Manager user (measured 2026-09-11 on brys).
        kdn.programs.blender.enable = true;
        /*
          TODO: re-enable when build is fixed
           see https://github.com/NixOS/nixpkgs/issues/36957
           see https://nixpk.gs/pr-tracker.html?pr=369729
        */
        # kdn.programs.orca-slicer.enable = true;
      })
    ]
  );
}
