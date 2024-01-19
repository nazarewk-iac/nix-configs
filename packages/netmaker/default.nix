{ pkgs, ... }:
let
  packages.nmctl = pkgs.callPackage ./nmctl { };
  packages.netmaker = pkgs.callPackage ./netmaker { };
  packages.netmaker-pro = pkgs.callPackage ./netmaker-pro { };
  packages.netmaker-ui = pkgs.callPackage ./netmaker-ui { };
  packages.netclient = pkgs.callPackage ./netclient { };
  #packages.netclient-gui = pkgs.callPackage ./netclient-gui { };
in
packages // {
  netmaker-full = pkgs.symlinkJoin {
    name = "netmaker-full-${packages.netmaker.version}";
    paths = builtins.attrValues packages;
  };
}
