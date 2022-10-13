{ lib, pkgs, config, inputs, system, ... }:
with lib;
let
  cfg = config.kdn.development.nix;
in
{
  options.kdn.development.nix = {
    enable = mkEnableOption "nix development/debugging";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nix-tree
      # didn't build on 2022-04-25
      # nix-du
      nixfmt
      nixpkgs-fmt

      inputs.nixpkgs-update.defaultPackage.${system}
      inputs.nixos-generators.defaultPackage.${system}

      (pkgs.writeShellApplication {
        name = "nix-which";
        runtimeInputs = with pkgs; [ nix ];
        text = ''
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
            nix-store --query "''${@:2}" "$(command -pv "$1")";;
          esac
        '';
      })
    ];
  };
}
