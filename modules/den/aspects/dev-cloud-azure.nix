# The `development/cloud/azure` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the Azure command-line set and PowerShell, and it pulls in the .NET aspect.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The `enable` write becomes an `includes` entry.** The old module writes
#    `kdn.development.dotnet.enable`, as `lib.mkDefault true`. den collapses a diamond, so several
#    aspects may name the same one.
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
  packages =
    pkgs: with pkgs; [
      powershell
      azure-cli
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
  kdn.dev-cloud-azure.includes = [ kdn.dev-dotnet ];

  kdn.dev-cloud-azure.nixos = systemTarget;
  kdn.dev-cloud-azure.darwin = systemTarget;
  kdn.dev-cloud-azure.homeManager = homeTarget;
}
