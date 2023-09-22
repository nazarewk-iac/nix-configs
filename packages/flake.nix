{
  description = "Description for the project";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixlib.url = "github:nix-community/nixpkgs.lib";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    nixos-generators.inputs.nixlib.follows = "nixlib";
  };
  outputs = inputs@{ flake-parts, self, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      #"x86_64-darwin" # error: 'packages.x86_64-darwin' is not an attribute set
      "aarch64-linux"
      "aarch64-darwin"
    ];

    perSystem = { config, self', inputs', system, pkgs, ... }: {
      packages = (import ./default.nix {
        inherit pkgs;
        inherit (inputs.nixos-generators) nixosGenerate;
      }).kdn;
    };
  };
}
