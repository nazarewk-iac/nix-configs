# `kdn.programs.spotify`, as a den aspect.
# It ports `modules/universal/programs/spotify/default.nix`.
#
# The old module carries a long commented-out `spotifywm` build log. That log records a build
# failure of a package the module never uses, so the port drops it.
{ kdn, ... }:
{
  kdn.program-spotify.includes = [ kdn.apps ];

  kdn.program-spotify.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps.spotify = {
          enable = true;
          dirs.cache = [ "spotify" ];
          dirs.config = [ "spotify" ];
        };
      };
    };
}
