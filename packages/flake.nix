{
  description = "Description for the project";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";
    nix-github-actions.url = "github:nix-community/nix-github-actions";
    poetry2nix.inputs.flake-utils.follows = "flake-utils";
    poetry2nix.inputs.nix-github-actions.follows = "nix-github-actions";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
    poetry2nix.inputs.treefmt-nix.follows = "treefmt-nix";
    poetry2nix.url = "github:nix-community/poetry2nix";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = inputs@{ flake-parts, self, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = import inputs.systems;
    flake.overlays.default = (inputs.nixpkgs.lib.composeManyExtensions [
      inputs.poetry2nix.overlays.default
      (final: prev: { kdn = final.callPackages ./. { }; })
    ]);
    perSystem = { config, self', inputs', system, pkgs, ... }: {
      _module.args.pkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default;
      packages = pkgs.kdn;
    };
  };
}
