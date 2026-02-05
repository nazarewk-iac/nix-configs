{
  lib,
  baseDir ? "$HOME/dev",
  ide ? "idea-ultimate",
  worktreesDir ? ".worktrees",
  curl,
  gh,
  git,
  jq,
  symlinkJoin,
  writeShellApplication,
  ...
}: let
  writeShellScript = path: {
    runtimeInputs ? [],
    checkPhase ? null,
    ...
  } @ args: let
    name =
      args.name or (lib.trivial.pipe path [
        toString
        builtins.baseNameOf
        (lib.removeSuffix ".sh")
      ]);

    dropFirst = line: lines:
      if (builtins.head lines) == line
      then (builtins.tail lines)
      else lines;

    drv = writeShellApplication {
      inherit name runtimeInputs checkPhase;
      text = lib.trivial.pipe path [
        builtins.readFile
        (lib.strings.splitString "\n")
        (dropFirst "#!/usr/bin/env bash")
        (dropFirst "set -eEuo pipefail")
        (dropFirst "set -xeEuo pipefail")
        (dropFirst "")
        (l: [args.prefix or ""] ++ l ++ [args.suffix or ""])
        (builtins.concatStringsSep "\n")
      ];
    };
  in
    drv // {bin = "${drv}/bin/${name}";};

  utils = with utils; {
    g-dir = writeShellScript ./bin/g-dir.sh {
      prefix = ''
        GIT_UTILS_KDN_BASE_DIR="''${GIT_UTILS_KDN_BASE_DIR:-"${baseDir}"}"
      '';
    };
    g-dir-azure-devops = writeShellScript ./bin/g-dir-dev.azure.com.sh {
      prefix = ''
        GIT_UTILS_KDN_BASE_DIR="''${GIT_UTILS_KDN_BASE_DIR:-"${baseDir}"}"
      '';
    };
    g-dir-codecommit = writeShellScript ./bin/g-dir-codecommit.sh {
      prefix = ''
        GIT_UTILS_KDN_BASE_DIR="''${GIT_UTILS_KDN_BASE_DIR:-"${baseDir}"}"
      '';
    };
    g-wt-dir = writeShellScript ./bin/g-wt-dir.sh {
      prefix = ''
        GIT_UTILS_KDN_WORKTREES_DIR="''${GIT_UTILS_KDN_WORKTREES_DIR:-"${worktreesDir}"}"
      '';
      runtimeInputs = [g-dir];
    };
    g-wt-get = writeShellScript ./bin/g-wt-get.sh {
      runtimeInputs = [
        g-dir
        g-wt-dir
      ];
    };
    g-wt-rm = writeShellScript ./bin/g-wt-rm.sh {
      runtimeInputs = [
        g-dir
        g-wt-dir
      ];
    };
    g-get = writeShellScript ./bin/g-get.sh {
      runtimeInputs = [
        git
        g-dir
        g-remote
      ];
    };
    g-remote = writeShellScript ./bin/g-remote.sh {
      runtimeInputs = [];
    };
    g-open = writeShellScript ./bin/g-open.sh {
      prefix = ''
        GIT_UTILS_KDN_IDE="''${GIT_UTILS_KDN_IDE:-"${ide}"}"
      '';
      runtimeInputs = [
        git
        g-dir
      ];
    };
    gh-repos = writeShellScript ./bin/gh-repos.sh {
      runtimeInputs = [
        gh
        jq
      ];
    };
    gh-get-all = writeShellScript ./bin/gh-get-all.sh {
      runtimeInputs = [gh-repos];
    };

    gl-repos = writeShellScript ./bin/gl-repos.sh {
      runtimeInputs = [
        git
        curl
        jq
      ];
    };
    gl-get-all = writeShellScript ./bin/gl-get-all.sh {
      runtimeInputs = [gl-repos];
    };
  };
in
  symlinkJoin {
    name = "git-utils";
    passthru = {inherit baseDir ide worktreesDir;} // utils;
    paths = lib.attrsets.attrValues utils;
  }
