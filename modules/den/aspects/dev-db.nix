# The `development/db` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `duckdb`, so a shell reads many file formats as a database.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
#
# The commented-out `usql` entry stays a comment, with the reason the old module gives.
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
      duckdb # it reads many different files as a database
      # TODO: 2026-03-23: it did not build. Turn it on after nixpkgs pull request 499348.
      #usql # a universal database client
    ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  systemTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };

  homeTarget =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;
    };
in
{
  kdn.dev-db.nixos = systemTarget;
  kdn.dev-db.darwin = systemTarget;
  kdn.dev-db.homeManager = homeTarget;
}
