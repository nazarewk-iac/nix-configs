# `kdn.programs.rambox`, as a den aspect. It ports `modules/universal/programs/rambox/default.nix`.
{ kdn, ... }:
{
  kdn.program-rambox.includes = [ kdn.apps ];

  kdn.program-rambox.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps."rambox" = {
          enable = true;
          dirs.config = [ "rambox" ];
        };
      };
    };
}
