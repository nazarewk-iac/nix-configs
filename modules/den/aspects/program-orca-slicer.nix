# `kdn.programs.orca-slicer`, as a den aspect.
# It ports `modules/universal/programs/orca-slicer/default.nix`.
#
# ## One workaround the port drops
#
# The old module pins nixpkgs to a 2024 commit and it filters one patch out of `previousAttrs.patches`.
# That is a personal workaround for a build failure of that era, and it holds a hard-coded revision
# hash. The aspect uses plain `pkgs.orca-slicer`. Mark for owner review.
{ kdn, ... }:
{
  kdn.program-orca-slicer.includes = [ kdn.apps ];

  kdn.program-orca-slicer.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps."orca-slicer" = {
          enable = true;
          dirs.cache = [ "orca-slicer" ];
          dirs.config = [ "OrcaSlicer" ];
          dirs.data = [ "orca-slicer" ];
        };
      };
    };
}
