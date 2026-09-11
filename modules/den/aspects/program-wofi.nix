# `kdn.programs.wofi`, as a den aspect. It ports `modules/universal/programs/wofi/default.nix`.
{ kdn, ... }:
{
  kdn.program-wofi.includes = [ kdn.apps ];

  kdn.program-wofi.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps.wofi = {
          enable = true;
          files.cache = [ "wofi-run" ];
        };
      };
    };
}
