{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
    poetry2nix.url = "github:nix-community/poetry2nix";
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs@{ flake-parts, self, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = import inputs.systems;
    flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
      inputs.poetry2nix.overlays.default
      (final: prev: { kdn = final.callPackages ./. { }; })
    ];
    perSystem = { config, self', inputs', system, pkgs, ... }: {
      _module.args.pkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default;
      packages = pkgs.kdn;
    };
  };
}
