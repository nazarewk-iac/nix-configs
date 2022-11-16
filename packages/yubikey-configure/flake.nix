{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, flake-parts, ... }: flake-parts.lib.mkFlake { inherit self; } {
    imports = [
    ];

    systems = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    perSystem = { config, self', inputs', pkgs, system, ... }:
      let
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
    flake = { };
  };
}
