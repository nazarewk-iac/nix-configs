{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.git;
  relDir = "${cfg.baseDir}";
  absDir = "${config.home.homeDirectory}/${relDir}";
  shellDir = "$HOME/${relDir}";
in {
  options.nazarewk.development.git = {
    enable = mkEnableOption "Git development utilities";

    baseDir = mkOption {
      default = "dev/github.com";
      description = "Base git checkout directory";
    };

    remoteShellPattern = mkOption {
      default = "git@github.com:$org/$repo.git";
    };
  };
  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "gh-clone";
        runtimeInputs = with pkgs; [ git ];
        text = ''
          for entry in "$@"; do
            org="''${entry%/*}"
            repo="''${entry#*/}"
            git clone "${cfg.remoteShellPattern}" "${shellDir}/$entry"
          done
        '';
      })
    ];
  };
}