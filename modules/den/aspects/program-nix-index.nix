# `kdn.programs.nix-index`, as a den aspect.
# It ports `modules/universal/programs/nix-index/default.nix`.
#
# The aspect file itself takes `inputs`. den sets `specialArgs.inputs`, so an aspect file may take it,
# and `nix.nixPath` needs a real nixpkgs path. A consumer that supplies its own `extraInputs.nixpkgs`
# gets that one instead.
{ inputs, ... }:
let
  filterPackages = import ../common/filter-packages.nix;

  # `nix-index` without `nix-channel`.
  # See https://github.com/bennofs/nix-index/issues/167
  nixPath = {
    nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  };
in
{
  kdn.program-nix-index.nixos =
    { lib, pkgs, ... }:
    {
      imports = [ nixPath ];

      config.environment.systemPackages = (filterPackages { inherit lib; }) [ pkgs.nix-index ];
      config.environment.interactiveShellInit = ''
        source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
      '';
    };

  kdn.program-nix-index.darwin =
    { lib, pkgs, ... }:
    {
      imports = [ nixPath ];

      config.environment.systemPackages = (filterPackages { inherit lib; }) [ pkgs.nix-index ];
    };

  kdn.program-nix-index.homeManager =
    { lib, pkgs, ... }:
    {
      imports = [ nixPath ];

      config.home.packages = (filterPackages { inherit lib; }) [ pkgs.nix-index ];
    };
}
