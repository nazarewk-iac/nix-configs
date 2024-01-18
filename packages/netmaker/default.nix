{ pkgs, ... }:
let
  packages.nmctl = pkgs.callPackage ./nmctl { };
  packages.netmaker = pkgs.callPackage ./netmaker { };
  packages.netmaker-ui = pkgs.callPackage ./netmaker-ui { };
  packages.netclient = pkgs.callPackage ./netclient { };
  #packages.netclient-gui = pkgs.callPackage ./netclient-gui { };
  packages.netmaker-scripts = pkgs.callPackage ./scripts { };
in
packages // {
  netmaker-full = pkgs.symlinkJoin {
    name = "netmaker-full-${packages.netmaker.version}";
    paths = builtins.attrValues packages;
  };
}
