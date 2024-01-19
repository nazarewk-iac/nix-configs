{ pkgs, ... }:
let
  extra = { nmInputs = pkgs.callPackage ./inputs.nix { }; };

  packages.nmctl = pkgs.callPackage ./nmctl extra;
  packages.netmaker = pkgs.callPackage ./netmaker extra;
  packages.netmaker-pro = pkgs.callPackage ./netmaker-pro extra;
  packages.netmaker-ui = pkgs.callPackage ./netmaker-ui extra;
  packages.netclient = pkgs.callPackage ./netclient extra;
  #packages.netclient-gui = pkgs.callPackage ./netclient-gui extra;
in
packages // {
  netmaker-bundle = pkgs.symlinkJoin {
    name = "netmaker-bundle-${packages.netmaker.version}";
    paths = builtins.attrValues packages;
  };
}
