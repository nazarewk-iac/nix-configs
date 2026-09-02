{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # The suite source: only the Python files (conftest.py, topologies.py,
  # test_*.py). This uses a directory filter, so new test files are picked up
  # without editing this list.
  jjExperimentsSuite = lib.fileset.toSource {
    root = ./jj-experiments;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./jj-experiments;
  };

  # The real fork slot config, rendered to a TOML the tests read through
  # JJ_FORK_CONFIG_TOML. inputs.self is the nix-configs flake.
  jjForkConfigToml = import ./jj-experiments/render-fork-config.nix {
    inherit pkgs;
    mkSlots = inputs.self.lib.kdn.mkSlots;
    slotsPath = inputs.self + "/modules/slots";
    nixConfigs = inputs.self;
    extraInputs = inputs;
  };
in
{
  # Minimal "hello world" check: proves the `checks.<system>` plumbing evaluates and
  # builds end-to-end (flake.nix mkSubmodule wiring + checks/default.nix), independent
  # of the heavier pytest checks whose sandbox behaviour still needs verifying.
  hello = pkgs.runCommand "check-hello" { } ''
    echo "hello world"
    touch $out
  '';

  kdn-slug-pytest = pkgs.kdn.kdn-slug.passthru.tests.pytest;
  zellij-llm-pytest = pkgs.kdn.zellij-llm.passthru.tests.pytest;

  # jj-experiments harness: runs the isolated 3-repo pytest suite headless. The
  # rendered fork slot config is passed in through JJ_FORK_CONFIG_TOML so the
  # tests resolve the real revset aliases without a devenv shell.
  jj-experiments-pytest =
    pkgs.runCommand "jj-experiments-pytest-check"
      {
        nativeBuildInputs = [
          (pkgs.python3.withPackages (ps: [ ps.pytest ]))
          pkgs.jujutsu
          pkgs.git
        ];
        JJ_FORK_CONFIG_TOML = jjForkConfigToml;
      }
      ''
        export HOME="$(mktemp -d)"
        cp -r ${jjExperimentsSuite}/. ./suite
        chmod -R u+w ./suite
        cd ./suite
        python3 -m pytest -v
        touch "$out"
      '';
}
