{
  lib,
  pkgs,
  ...
}:
pkgs.writeShellApplication {
  name = "kdn-cidata-iso";
  runtimeInputs = with pkgs; [
    nix-output-monitor
  ];
  text = ''
    set -xeEuo pipefail

    nom-build --no-out-link --expr "with import <nixpkgs> {}; callPackage ${./.}/build.nix {} { hostname = \"$1\"; }"
  '';
}
