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
      nix-derivation # pretty-derivation
      nix-du
      nix-output-monitor
      nix-tree
      nix-update
      nixfmt
      nixpkgs-fmt
      rnix-lsp

      devenv

      #inputs.nixpkgs-update.defaultPackage.${system}
      (pkgs.writeShellApplication {
        name = "kdn-nix-collect-garbage";
        runtimeInputs = with pkgs; [
          nix
          coreutils
          gnugrep
          glibc # getent
        ];
        text = ''
          if [[ $EUID -ne 0 ]];
          then
            echo "restarting as root..." >&2
            exec sudo ${lib.getExe bash} "$0" "$@"
          fi
          nix-collect-garbage -d
          mapfile -t users < <(getent passwd | cut -d: -f1,6 | grep ':/home/' | cut -d: -f1)
          for user in "''${users[@]}"; do
            sudo -u "$user" -- nix-collect-garbage -d
          done
        '';
      })
      (pkgs.writeShellApplication {
        name = "kdn-nix-list-roots";
        runtimeInputs = with pkgs; [ nix gnugrep ];
        text = ''
          nix-store --gc --print-roots | grep -v -E "^(/nix/var|/run/\w+-system|\{memory|/proc)"
        '';
      })

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
