{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  inherit (kdn) self;
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      xdg.configFile."kdn/source-flake".source = self;
    }
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
        pkgs.kdn.kdn-nix
      ];
    }
  ]);
}
