{ lib, pkgs, config, inputs, system, ... }:
let
  cfg = config.kdn.development.nix;
in
{
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";
  };

  config = lib.mkIf cfg.enable {

    programs.fish.interactiveShellInit = ''
      complete -c nix-which --wraps which
    '';
    environment.systemPackages = with pkgs; [
      nix-tree
      nix-du
      rnix-lsp
      nixfmt
      nixpkgs-fmt

      devenv

      #inputs.nixpkgs-update.defaultPackage.${system}

      (pkgs.writeShellApplication {
        name = "nix-which";
        runtimeInputs = with pkgs; [ nix ];
        text = ''
          set -eEuo pipefail

          help() {
            cat <<EOF >&2
            Usage: "$0" <binary> [options...]
            Find immediate parents/reverse dependencies: nix-which <binary> --referrers
            Find the root using paths: nix-which <binary> --roots
          EOF
          }
          case "$1" in
          -h|--help)
            help;;
          *)
            nix-store --query "''${@:2}" "$(command -v "$1" || command -pv "$1")";;
          esac
        '';
      })
    ];
  };
}
