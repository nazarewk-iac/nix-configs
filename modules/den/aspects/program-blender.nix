# `kdn.programs.blender`, as a den aspect. It ports `modules/universal/programs/blender/default.nix`.
{ kdn, ... }:
{
  kdn.program-blender.includes = [ kdn.apps ];

  kdn.program-blender.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps.blender = {
          enable = true;
          dirs.cache = [ "blender" ];
          dirs.config = [ "blender" ];
        };
      };
    };
}
