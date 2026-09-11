# `kdn.programs.beeper`, as a den aspect. It ports `modules/universal/programs/beeper/default.nix`.
#
# The old module fires in a Home Manager evaluation under a NixOS parent only. den has no parent
# chain, so this aspect states the real intent: Linux, in a user evaluation.
{ kdn, ... }:
{
  kdn.program-beeper.includes = [ kdn.apps ];

  kdn.program-beeper.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps."beeper" = {
          enable = true;
          dirs.config = [ "Beeper" ];
        };
      };
    };
}
