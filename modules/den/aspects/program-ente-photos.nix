# `kdn.programs.ente-photos`, as a den aspect.
# It ports `modules/universal/programs/ente-photos/default.nix`.
#
# The old `package` option is gone. `kdn.apps.<name>.package.original` already serves that purpose,
# so a consumer repoints the package there and this aspect declares no second option for it.
{ kdn, ... }:
{
  kdn.program-ente-photos.includes = [ kdn.apps ];

  kdn.program-ente-photos.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps.ente-photos-desktop = {
          enable = true;
          package.original = pkgs.ente-desktop;
          dirs.cache = [ "ente" ];
          dirs.config = [ "ente" ];
        };
      };
    };
}
