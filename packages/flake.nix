{
  description = "Description for the project";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixlib.url = "github:nix-community/nixpkgs.lib";
  };
  outputs = inputs@{ flake-parts, self, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    perSystem = { config, self', inputs', system, pkgs, ... }: {
      packages = (import ./default.nix {
        inherit pkgs;
      }).kdn;
    };
  };
}
