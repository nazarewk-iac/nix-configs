# `kdn.programs.chromium`, as a den aspect.
# It ports `modules/universal/programs/chromium/default.nix`.
#
# The old module writes `enable = cfg.enable && !isDarwin`, so the platform test moves to a
# `lib.mkIf` here and the value becomes a plain `true`.
{ kdn, ... }:
{
  kdn.program-chromium.includes = [ kdn.apps ];

  kdn.program-chromium.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
        kdn.apps.chromium = {
          enable = true;
          package.original = pkgs.ungoogled-chromium;
          dirs.config = [ "chromium" ];
        };
      };
    };
}
