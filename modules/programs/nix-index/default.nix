{ lib, pkgs, config, flakeInputs, ... }:
with lib;
let
  cfg = config.nazarewk.programs.nix-index;
in {
  options.nazarewk.programs.nix-index = {
    enable = mkEnableOption "nix-index setup";
  };

  config = mkIf cfg.enable {
    environment.interactiveShellInit = ''
      source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
    '';

    # use nix-index without `nix-channel`
    # see https://github.com/bennofs/nix-index/issues/167
    nix.nixPath = [ "nixpkgs=${flakeInputs.nixpkgs}" ];
    environment.systemPackages = with pkgs; [ nix-index ];
  };
}