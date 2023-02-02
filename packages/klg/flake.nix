{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    poetry2nix = {
      #url = "github:nazarewk/poetry2nix";
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, poetry2nix, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
    ];

    systems = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    flake = {
      # Nixpkgs overlay providing the application
      overlays.default = nixpkgs.lib.composeManyExtensions [
        poetry2nix.overlay
      ];
    };

    perSystem = { config, self', inputs', system, ... }:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        conf = import ./config.nix { inherit pkgs; };
      in
      {
        packages.default = conf.pkg;
        packages.container = pkgs.dockerTools.buildLayeredImage {
          name = "hello-docker";
          tag = "latest";
          config = {
            Cmd = [ conf.bin ];
          };
        };
        devShells = {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              conf.env
              poetry
              dagger
            ];
          };
        };
        # inspired by https://github.com/NixOS/nix/issues/3803#issuecomment-748612294
        # usage: nix run '.#repl'
        apps.repl = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "repl" ''
            confnix=$(mktemp)
            trap "rm '$confnix' || true" EXIT
            echo "builtins.getFlake (toString "$PWD")" >$confnix
            nix repl "$confnix"
          ''}/bin/repl";
        };
      };
  };
}
