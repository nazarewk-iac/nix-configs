# The `development/cloud` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `redis` and it pulls in the Node.js and the Lua aspects.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The two `enable` writes become `includes` entries.** The old module writes
#    `kdn.development.nodejs.enable` and `kdn.development.lua.enable`, each as `lib.mkDefault true`.
#    den collapses a diamond, so several aspects may name the same one.
# 3. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `lib` and `pkgs` only.
{ kdn, ... }:
let
  packages = pkgs: with pkgs; [ redis ];

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
  kdn.dev-cloud.includes = [
    kdn.dev-lua
    kdn.dev-nodejs
  ];

  kdn.dev-cloud.nixos = systemTarget;
  kdn.dev-cloud.darwin = systemTarget;
  kdn.dev-cloud.homeManager = homeTarget;
}
