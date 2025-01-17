{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = with pkgs; [
        git
        bash
        curl
      ];
    }
    {
      xdg.userDirs.enable = pkgs.stdenv.isLinux;
      xdg.userDirs.createDirectories = false;
    }
    {
      home.packages = with pkgs; [
        nix-derivation # pretty-derivation
        nix-output-monitor
        nix-du
        nix-tree
        kdn.kdn-nix
      ];
    }
  ]);
}
