{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.git;
  relDir = "${cfg.baseDir}";
  absDir = "${config.home.homeDirectory}/${relDir}";
  shellDir = "$HOME/${relDir}";

  ghDir = (pkgs.writeShellApplication {
    name = "gh-dir";
    runtimeInputs = with pkgs; [  ];
    text = ''
      for entry in "$@"; do
        echo "${shellDir}/$entry"
      done
    '';
  });

  ghRemote = (pkgs.writeShellApplication {
    name = "gh-remote";
    runtimeInputs = with pkgs; [  ];
    text = ''
      for entry in "$@"; do
        org="''${entry%/*}"
        repo="''${entry#*/}"
        echo "${cfg.remoteShellPattern}"
      done
    '';
  });

  ghClone = (pkgs.writeShellApplication {
    name = "gh-clone";
    runtimeInputs = with pkgs; [ git ghDir ghRemote ];
    text = ''
      for entry in "$@"; do
        dir="$(gh-dir "$entry")"
        remote="$(gh-remote "$entry")"

        if [ -d "$dir/.git" ] ; then
          echo "$dir already exists, skipping..."
          continue
        fi

        git clone "$remote" "$dir"
      done
    '';
  });

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
    programs.bash.initExtra = config.programs.zsh.initExtra;
    programs.zsh.initExtra = ''
      gh-cd() {
        cd "$(${ghDir}/bin/gh-dir $1)"
      }
    '';

    home.packages = with pkgs; [
      ghDir
      ghRemote
      ghClone
    ];
  };
}