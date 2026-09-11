# `kdn.programs.browsers-launcher`, as a den aspect.
# It ports `modules/universal/programs/browsers-launcher/default.nix`.
#
# The old module writes `homebrew.casks` only when `config.kdn.homebrew.enable` is true. An aspect
# reads no other aspect's `enable`, and the `homebrew` aspect holds none. The darwin target writes the
# casks directly; nix-darwin ignores `homebrew.casks` when `homebrew.enable` is false.
{ kdn, ... }:
{
  kdn.program-browsers-launcher.includes = [ kdn.apps ];

  kdn.program-browsers-launcher.darwin =
    { config, lib, ... }:
    {
      options.kdn.programs.browsers-launcher.casks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "browsers" ];
        description = ''
          Homebrew casks that supply the launcher on macOS.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };

      config.homebrew.casks = config.kdn.programs.browsers-launcher.casks;
    };

  kdn.program-browsers-launcher.homeManager =
    { pkgs, ... }:
    {
      config.kdn.apps.browsers = {
        enable = true;
        # On macOS the cask above installs the launcher.
        package.install = !pkgs.stdenv.hostPlatform.isDarwin;
        dirs.config = [ "software.Browsers" ];
      };
    };
}
