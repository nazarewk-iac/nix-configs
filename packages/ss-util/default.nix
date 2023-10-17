{ pkgs, ... }: (pkgs.callPackage ./config.nix { }).app
