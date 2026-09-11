# `kdn.programs.editors.photo`, as a den aspect.
# It ports `modules/universal/programs/editors/photo/default.nix`.
#
# Design B applies. The old module writes `kdn.env.packages`; each class writes its own native option.
{ ... }:
let
  filterPackages = import ../common/filter-packages.nix;

  editors =
    pkgs: with pkgs; [
      gimp
      krita
    ];

  hostTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = (filterPackages { inherit lib; }) (editors pkgs);
    };
in
{
  kdn.program-editors-photo.nixos = hostTarget;
  kdn.program-editors-photo.darwin = hostTarget;

  kdn.program-editors-photo.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = (filterPackages { inherit lib; }) (editors pkgs);
    };
}
