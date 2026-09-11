# The `development/dotnet` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the .NET software development kit and runtime, and it sets `DOTNET_ROOT`. On NixOS it
# also turns on `nix-ld`, because a .NET tool loads a dynamic library the normal way.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` and `kdn.env.variables` go.** Each target writes the native option of its
#    own class. Design B:
#    - NixOS: `environment.systemPackages` plus `environment.sessionVariables`;
#    - Darwin: `environment.systemPackages` plus `environment.variables`;
#    - Home Manager: `home.packages` plus `home.sessionVariables`.
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
      dotnet-sdk
      dotnet-runtime
    ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  # See https://nixos.wiki/wiki/DotNET
  variables = pkgs: {
    DOTNET_ROOT = "${pkgs.dotnet-sdk}";
  };
in
{
  kdn.dev-dotnet.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
      environment.sessionVariables = variables pkgs;

      # See https://nixos.wiki/wiki/DotNET
      programs.nix-ld.enable = true;
    };

  kdn.dev-dotnet.darwin =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
      environment.variables = variables pkgs;
    };

  kdn.dev-dotnet.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;
      home.sessionVariables = variables pkgs;
    };
}
