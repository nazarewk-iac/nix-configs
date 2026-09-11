# The `development/rust` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `rustup` and `pkg-config`. On Home Manager it also adds `rust-analyzer` and `lldb` to
# Helix.
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
      #cargo
      #rustc
      rustup
      #rust-analyzer # rustup already ships it
      pkg-config
    ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  systemTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };
in
{
  kdn.dev-rust.nixos = systemTarget;
  kdn.dev-rust.darwin = systemTarget;

  kdn.dev-rust.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;

      programs.helix.extraPackages = with pkgs; [
        rust-analyzer
        lldb
      ];
    };
}
