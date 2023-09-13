{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.golang;
in
{
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = lib.mkIf cfg.enable {
    environment.extraInit = ''
      export PATH="$PATH:$HOME/.cache/go/bin"
    '';
    environment.systemPackages = with pkgs; [
      (lib.meta.hiPrio go_1_20)
      go_1_19
      #gccgo
      delve
      goreleaser
      golangci-lint # for netbird

      (pkgs.writeShellApplication {
        name = "go-toolchain-install";
        runtimeInputs = with pkgs; [ go jq ];
        text = ''
          set -xeEuo pipefail
          version="$1"
          shift 1
          go install "golang.org/dl/go$version@latest"
          ~/.cache/go/bin/"go$version" download
          "go$version" env --json | jq -S "$@"
        '';
      })
    ];
    home-manager.sharedModules = [{ kdn.development.jetbrains.go.enable = true; }];
  };
}
