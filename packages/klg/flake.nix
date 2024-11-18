{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #devenv.url = "github:cachix/devenv/latest";
    #devenv.url = "github:cachix/devenv/main";
    devenv.url = "github:nazarewk/devenv/flake-parts-container-usage";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.inputs.flake-utils.follows = "flake-utils";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

      flake = {
        # Nixpkgs overlay providing the application
        overlays.default = nixpkgs.lib.composeManyExtensions [];
      };

      perSystem = {
        config,
        self',
        inputs',
        system,
        pkgs,
        ...
      }: let
        conf = pkgs.callPackage ./config.nix {};
      in {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
            inputs.poetry2nix.overlays.default
            (final: prev: {
              nix2container = inputs'.nix2container.packages.nix2container;
            })
          ];
        };

        packages.default = conf.app;
        packages.dev = conf.dev;
        packages.poetryApp = conf.poetryApp;
        # nix run '.#container.copyToPodman'
        packages.container = conf.container;

        devenv.shells.default = {
          name = "default";

          # https://devenv.sh/reference/options/
          packages = with pkgs; [
            black
            conf.dev
            conf.klog
          ];
        };
      };
    };
}
