{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    flake-utils.url = "github:numtide/flake-utils";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    nix2container.inputs.flake-utils.follows = "flake-utils";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.url = "github:nlewo/nix2container";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
    poetry2nix.url = "github:nix-community/poetry2nix";
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;
      imports = [
        inputs.devenv.flakeModule
      ];
      flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
        inputs.poetry2nix.overlays.default
        (final: prev: {git-credential-keyring = final.callPackage ./. {};})
      ];
      perSystem = {
        config,
        self',
        inputs',
        system,
        pkgs,
        ...
      }: {
        _module.args.pkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default;
        packages.git-credential-keyring = pkgs.git-credential-keyring;

        devenv.shells.default = {
          packages = with pkgs; [
            git-credential-keyring
          ];
        };
      };
    };
}
