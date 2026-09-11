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

  # Every den MVP entity, as one flat set of buildable derivations. A den host yields a system
  # toplevel; a devenv shell yields its shell derivation. See den-mvp/README.md.
  denEntities =
    let
      configs = lib.mapAttrs' (
        name: cfg: lib.nameValuePair "config-${name}" cfg.config.system.build.toplevel
      ) inputs.self.denConfigurations;
      shells = lib.mapAttrs' (
        name: cfg: lib.nameValuePair "shell-${name}" cfg.shell
      ) inputs.self.denDevenvShells;
    in
    configs // shells;

  # A derivation carries its own platform, so one filter covers both kinds.
  denForThisSystem = lib.filterAttrs (
    _: drv: drv.system == pkgs.stdenv.hostPlatform.system
  ) denEntities;

  mkDenAggregate =
    name: entities:
    pkgs.linkFarm name (
      lib.mapAttrsToList (n: path: {
        name = n;
        inherit path;
      }) entities
    );

  # The den MVP test harness: tier 1 evaluation assertions, tier 2 artifact greps, tier 3 smoke
  # runs, plus the semi-automated runner. See den-mvp/tests.nix.
  denTests = import ./den-mvp/tests.nix { inherit pkgs lib inputs; };

  # The standalone rule gate. It reads the slot sources and the aspect option trees, so it builds
  # no system and it needs no builder for another platform. See standalone.nix.
  standaloneTests = import ./standalone.nix { inherit pkgs lib inputs; };

  # The real fork slot artifacts: the config TOML the tests read through
  # JJ_FORK_CONFIG_TOML, and the pre-push script they read through
  # KDN_JJ_PRE_PUSH_SH. inputs.self is the nix-configs flake.
  jjFork = import ./jj-experiments/render-fork-config.nix {
    inherit pkgs;
    mkSlots = inputs.self.lib.kdn.mkSlots;
    slotsPath = inputs.self + "/modules/slots";
    nixConfigs = inputs.self;
    extraInputs = inputs;
  };
in
denTests.checks
// standaloneTests.checks
// {
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
  #
  # This whole-suite check is the CI gate. It goes through the parameterized
  # builder with no extra pytest args. To run a subset, use the same builder via
  # checks/jj-experiments/subset-runner.nix (or `nix run .#jj-experiments-run`).
  jj-experiments-pytest = import ./jj-experiments/mk-pytest.nix {
    inherit pkgs lib;
    suite = jjExperimentsSuite;
    inherit (jjFork) toml prePush;
    # extraArgs = [ ];  # whole suite
  };

  # den MVP build gate. It proves that the parallel den tree still evaluates and builds. It asserts
  # nothing — the `den-eval-*`, `den-artifact-*` and `den-smoke-*` checks above do that.
  #
  # The default check builds only the entities of the current system, so it needs no remote
  # builder. `den-mvp.all` builds every entity of every system, and a foreign system needs a
  # builder for that platform. `nix flake check` builds the default only, because `.all` sits in
  # `passthru`.
  #
  #   nix build '.#checks.aarch64-darwin.den-mvp'
  #   nix build '.#checks.aarch64-darwin.den-mvp.all'
  #   nix run   '.#checks.aarch64-darwin.den-mvp.smoke'
  den-mvp = (mkDenAggregate "den-mvp" denForThisSystem).overrideAttrs (prev: {
    passthru = (prev.passthru or { }) // {
      all = mkDenAggregate "den-mvp-all" denEntities;
      inherit (denTests) smoke;
    };
  });
}
