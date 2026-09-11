# The `development/nodejs` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs Node.js and Yarn. On Home Manager it also adds the TypeScript language server to
# Helix, and it writes an `.npmrc` that moves the npm cache and the global prefix under `~/.cache`.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The `.npmrc` file moves into the `homeManager` class.** The old NixOS half writes it through
#    `home-manager.sharedModules`, so it reaches a user only from a NixOS host. In den the file is a
#    Home Manager fact, so every consumer of the `homeManager` class gets it, a Darwin user included.
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
      nodejs
      yarn
    ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  systemTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };
in
{
  kdn.dev-nodejs.nixos = systemTarget;
  kdn.dev-nodejs.darwin = systemTarget;

  kdn.dev-nodejs.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;

      programs.helix.extraPackages = with pkgs; [ typescript-language-server ];

      home.file.".npmrc".text = ''
        cache=~/.cache/npm
        prefix=~/.cache/npm-global
      '';
    };
}
