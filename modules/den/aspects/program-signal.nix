# `kdn.programs.signal`, as a den aspect. It ports `modules/universal/programs/signal/default.nix`.
#
# The old module gates its body on `hasParentOfAnyType [ "nixos" ]`, so it fires in a Home Manager
# evaluation under a NixOS parent only. den has no parent chain, so this aspect states the real
# intent: Linux, in a user evaluation.
#
# It includes `apps`, because `kdn.apps` is that aspect's own option.
{ kdn, ... }:
{
  kdn.program-signal.includes = [ kdn.apps ];

  kdn.program-signal.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps."signal-desktop" = {
          enable = true;
          package.original = pkgs."signal-desktop";
          dirs.config = [ "Signal" ];
        };
      };
    };
}
