{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  inherit (kdnConfig) self;
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile."kdn/source-flake".source = self;

        home.sessionPath = ["$HOME/.local/bin"];
        #systemd.user.tmpfiles.settings.kdn-bin.rules."%h/.local/bin".d = {};
        systemd.user.tmpfiles.rules = [
          "d %h/.local/bin - - - -"
        ];
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
    ]
  );
}
