# The `development/git` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It sets up Git, the GitHub CLI, Jujutsu and the `git-utils` scripts for one user. It is a Home
# Manager opinion only: the old module forwards its whole value to Home Manager and writes nothing
# at host level.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** A den target names its class, so this one writes `home.packages`
#    and runs the old `apply` pipeline through ../common/filter-packages.nix. Design B.
# 3. **`git-utils` comes from a plain `callPackage`.** The old module reads the `kdn` package set,
#    so a consumer must add this repository's overlay first. A relative path needs no overlay.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-git.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      git-utils = pkgs.callPackage ../../../packages/git-utils { };
    in
    {
      programs.git.enable = true;

      programs.git.ignores = [
        ''
          # START kdn.git-utils
          /${git-utils.passthru.worktreesDir}/
          # END kdn.git-utils
        ''
      ];
      programs.difftastic.git.enable = true;

      home.packages = filterPackages [
        pkgs.git
        git-utils
        pkgs.gh
        pkgs.jjui
      ];

      programs.jujutsu.enable = true;
      programs.jujutsu.settings = {
        ui.default-command = "log";
        ui.diff-formatter = [
          (lib.getExe config.programs.difftastic.package)
          "--color=always"
          "$left"
          "$right"
        ];
        # turn the pager off by default
        ui.paginate = "auto";
      };
    };
}
