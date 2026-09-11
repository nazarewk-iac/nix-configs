# `kdn.programs.direnv`, as a den aspect. It ports `modules/universal/programs/direnv/default.nix`.
{ kdn, ... }:
{
  kdn.program-direnv.includes = [ kdn.apps ];

  # `keep-outputs` and `keep-derivations` stop the garbage collector from removing a build input a
  # direnv shell still needs.
  kdn.program-direnv.nixos.nix.extraOptions = ''
    keep-outputs = true
    keep-derivations = true
  '';

  kdn.program-direnv.homeManager =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      config = {
        home.packages = filterPackages (
          with pkgs;
          [
            direnv
            nix-direnv
          ]
        );

        programs.direnv.enable = true;
        programs.direnv.nix-direnv.enable = true;

        # The old module reads a four-line `.gitignore` file next to itself. The text is short, so the
        # aspect holds it inline and needs no second file.
        programs.git.ignores = [
          "# START direnv"
          ".direnv/"
          ".envrc"
          "# END direnv"
        ];

        kdn.apps.direnv = {
          enable = true;
          # `programs.direnv` already installs the package.
          package.install = false;
          dirs.data = [ "direnv" ];
          dirs.config = [ "direnv" ];
        };
      };
    };
}
