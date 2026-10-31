{
  lib,
  pkgs,
}:
let
  mkScript =
    name: args:
    pkgs.writeShellApplication (
      {
        inherit name;
        text = builtins.readFile (./. + "/${name}.sh");
      }
      // args
    );
in
pkgs.symlinkJoin {
  name = "kdn-nix";
  paths = lib.attrsets.attrValues rec {
    kdn-nix-collect-garbage = mkScript "kdn-nix-collect-garbage" {
      runtimeInputs = with pkgs; [
        nix
        coreutils
        gnugrep
        unixtools.getent
        kdn-nix-list-roots
      ];
    };
    kdn-nix-reap-builders = mkScript "kdn-nix-reap-builders" {
      runtimeInputs = with pkgs; [
        procps
        coreutils
        gnugrep
      ];
    };
    kdn-tools = mkScript "kdn-tools" {
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
      ];
    };
    kdn-nix-list-roots = mkScript "kdn-nix-list-roots" {
      runtimeInputs = with pkgs; [
        nix
        gnugrep
      ];
    };
    kdn-nix-which = mkScript "kdn-nix-which" {
      runtimeInputs = with pkgs; [
        nix
        coreutils
      ];
    };
  };
}
