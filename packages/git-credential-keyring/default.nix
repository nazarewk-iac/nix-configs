{ pkgs, ... }:
pkgs.poetry2nix.mkPoetryApplication {
  projectDir = ./.;
}
