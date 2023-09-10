{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #devenv.url = "github:cachix/devenv/latest";
    #devenv.url = "github:cachix/devenv/main";
    # see https://github.com/cachix/devenv/pull/503
    devenv.url = "github:nazarewk/devenv/flake-parts-container-usage";
    #devenv.url = "/home/kdn/dev/github.com/cachix/devenv";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.inputs.flake-utils.follows = "flake-utils";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.devenv.flakeModule
    ];
    systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

    flake = {
      # Nixpkgs overlay providing the application
      overlays.default = nixpkgs.lib.composeManyExtensions [ ];
    };

    perSystem = { config, self', inputs', system, pkgs, ... }:
      let
        conf = import ./config.nix { inherit pkgs; };
      in
      {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
          ];
        };

        packages.default = conf.pkg;
        devenv.shells.default = {
          name = "default";

          languages.python.enable = true;
          languages.python.package = conf.python;
          languages.python.poetry.enable = true;
          languages.python.poetry.install.installRootPackage = true;

          # https://devenv.sh/reference/options/
          packages = with pkgs; [
            black
            conf.klog
          ];
        };
      };
  };
}
