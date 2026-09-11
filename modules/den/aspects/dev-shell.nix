# The `development/shell` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the shell development set: `bash`, `zsh`, `shellcheck`, `shfmt`, `bats`, `docopts`,
# `gnumake` and `expect`. On Home Manager it also adds four language servers to Helix.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The forward to Home Manager goes.** den needs no forward: a consumer names the class it
#    wants.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `lib` and `pkgs` only.
{ ... }:
let
  packages =
    pkgs: with pkgs; [
      bash
      shellcheck
      shfmt
      zsh

      docopts # https://github.com/docopt/docopts
      bats # https://github.com/bats-core/bats-core

      gnumake

      expect
    ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  systemTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };
in
{
  kdn.dev-shell.nixos = systemTarget;
  kdn.dev-shell.darwin = systemTarget;

  kdn.dev-shell.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;

      programs.helix.extraPackages = with pkgs; [
        bash-language-server
        shellcheck
        shfmt
        cmake-language-server
      ];
    };
}
