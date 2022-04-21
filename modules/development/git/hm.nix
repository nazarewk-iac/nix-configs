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

  ghGet = (pkgs.writeShellApplication {
    name = "gh-get";
    runtimeInputs = with pkgs; [ git ghDir ghRemote ];
    text = ''
      for entry in "$@"; do
        dir="$(gh-dir "$entry")"
        remote="$(gh-remote "$entry")"

        if [ -d "$dir/.git" ] ; then
          echo "$dir already exists, updating..."
          git -C "$dir" fetch --all
          git -C "$dir" pull || true
          continue
        fi

        git clone "$remote" "$dir"
      done
    '';
  });

  ghRepos = (pkgs.writeShellApplication {
    name = "gh-repos";
    runtimeInputs = with pkgs; [ gh jq ];
    text = ''
      LIMIT="''${LIMIT:-999}"
      for owner in "$@"; do
        gh repo list "$owner" -L "$LIMIT" --json owner,name | jq -r '.[] | "\(.owner.login)/\(.name)"'
      done
    '';
  });

  ghGetAll = (pkgs.writeShellApplication {
    name = "gh-get-all";
    runtimeInputs = with pkgs; [ ghRepos ];
    text = ''
      readarray -t repos <<<"$(gh-repos "$@")"
      gh-get "''${repos[@]}"
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
      default = "https://github.com/$org/$repo.git";
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
      ghGet
      ghGetAll
      ghRepos

      hub
      gh
    ];
  };
}