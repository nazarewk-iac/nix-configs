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
      nix-du
      nix-tree
      nix-update
      nixfmt
      nixpkgs-fmt
      rnix-lsp

      devenv

      #inputs.nixpkgs-update.defaultPackage.${system}

      (pkgs.writeShellApplication {
        name = "nix-which";
        runtimeInputs = with pkgs; [ nix coreutils ];
        text = ''
          set -eEuo pipefail

          help() {
            cat <<EOF >&2
            Usage: "$0" <binary> [options...]
            Find immediate parents/reverse dependencies: nix-which <binary> --referrers
            Find the root using paths: nix-which <binary> --roots
          EOF
          }
          type_immediate() {
            command -v "$1" || command -pv "$1"
          }
          type_resolved() {
            realpath "$(type_immediate "$1")"
          }
          type="resolved"
          args=()

          while test "$#" -gt 0 ; do
            case "$1" in
            -h|--help) help && exit 0 ;;
            -i|--immediate) type="immediate" ;;
            -r|--resolved) type="resolved" ;;
            *) args+=("$1") ;;
            esac
            shift
          done

          name="''${args[0]}"
          args=("''${args[@]:1}")
          nix-store --query "''${args[@]}" "$(type_"$type" "$name")"
        '';
      })
    ];
  };
}
