{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.nix;
in {
  options.nazarewk.development.nix = {
    enable = mkEnableOption "nix development/debugging";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nix-tree
      nix-du
      nixfmt
      nixpkgs-fmt
    ];
  };
}