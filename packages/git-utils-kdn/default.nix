{ lib
, GIT_UTILS_KDN_BASE_DIR ? "$HOME/dev"
, GIT_UTILS_KDN_IDE ? "idea-ultimate"
, curl
, gh
, git
, jq
, symlinkJoin
, writeShellApplication
, ...
}:
let
  writeShellScript = path: { runtimeInputs ? [ ], checkPhase ? null, ... }@args:
    let
      name = args.name or (lib.trivial.pipe path [
        builtins.toString
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
          (l: [ args.prefix or "" ] ++ l ++ [ args.suffix or "" ])
          (builtins.concatStringsSep "\n")
        ];
      };
    in
    drv // { bin = "${drv}/bin/${name}"; };
in
symlinkJoin {
  name = "git-utils-kdn";
  paths = lib.attrsets.attrValues (rec {
    g-dir = writeShellScript ./bin/g-dir.sh {
      prefix = ''
        GIT_UTILS_KDN_BASE_DIR="''${GIT_UTILS_KDN_BASE_DIR:-"${GIT_UTILS_KDN_BASE_DIR}"}"
      '';
    };
    g-dir-azure-devops = writeShellScript ./bin/g-dir-dev.azure.com.sh {
      prefix = ''
        GIT_UTILS_KDN_BASE_DIR="''${GIT_UTILS_KDN_BASE_DIR:-"${GIT_UTILS_KDN_BASE_DIR}"}"
      '';
    };
    g-dir-codecommit = writeShellScript ./bin/g-dir-codecommit.sh {
      prefix = ''
        GIT_UTILS_KDN_BASE_DIR="''${GIT_UTILS_KDN_BASE_DIR:-"${GIT_UTILS_KDN_BASE_DIR}"}"
      '';
    };
    g-get = writeShellScript ./bin/g-get.sh {
      runtimeInputs = [ git g-dir g-remote ];
    };
    g-open = writeShellScript ./bin/g-open.sh {
      prefix = ''
        GIT_UTILS_KDN_IDE="''${GIT_UTILS_KDN_IDE:-"${GIT_UTILS_KDN_IDE}"}"
      '';
      runtimeInputs = [ git g-dir g-remote ];
    };
    g-remote = writeShellScript ./bin/g-remote.sh { };
    gh-repos = writeShellScript ./bin/gh-repos.sh {
      runtimeInputs = [ gh jq ];
    };
    gh-get-all = writeShellScript ./bin/gh-get-all.sh {
      runtimeInputs = [ gh-repos ];
    };

    gl-repos = writeShellScript ./bin/gl-repos.sh {
      runtimeInputs = [ git curl jq ];
    };
    gl-get-all = writeShellScript ./bin/gl-get-all.sh {
      runtimeInputs = [ gl-repos ];
    };
  });
}
