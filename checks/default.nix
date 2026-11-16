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

  # The conditional-imports conformance test. It states, as a runnable test, the one requirement
  # `modules/meta/` exists to solve. See conditional-imports.nix and
  # docs/tasks/2026-09/generalization/005-conditional-imports-requirement/.
  conditionalImportsTests = import ./conditional-imports.nix { inherit pkgs lib inputs; };

  # The two guard defects of `modules/universal/`, as a runnable test. Each check evaluates one
  # module file in both contexts and forces the attribute path that laziness hides. See
  # universal-guards.nix and docs/tasks/2026-09/latent-guard-defects/.
  universalGuardTests = import ./universal-guards.nix { inherit pkgs lib inputs; };

  # Pi harness smoke checks. They need no brys, no GPU and no network after the first fetch.
  # Linux only: a check binds a loopback port and runs an in-sandbox server, which the darwin
  # sandbox does not allow.
  #
  # Measured RSS per check (2026-11-01):
  #   pi-harness-plumbing / prompt-stable / timestamps / subagent-registered
  #       23 MiB llama-server (stories260K @ ctx 4096) + ~120-200 MiB pi  =  ~150-250 MiB
  #   pi-harness-subagent-spawn      fake SSE server + one child pi      =  ~150-250 MiB
  #   pi-harness-delegates           587 MiB llama-server (qwen2.5-0.5b @ 2048) + pi  =  ~800 MiB
  # So bundle-core stays under 1.5 GiB at max-jobs 2; the delegation check alone needs ~800 MiB.
  piHarnessTests =
    if pkgs.stdenv.hostPlatform.isLinux then import ./pi-harness { inherit pkgs lib; } else { };

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
// conditionalImportsTests.checks
// universalGuardTests.checks
// piHarnessTests
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

  # The `kdn-certs` Go suite. Every case mocks the `nix eval` and the `step` call behind an
  # interface, so the check needs no flake, no CA and no network. See
  # ../packages/kdn-certs/default.nix.
  kdn-certs-test = pkgs.kdn.kdn-certs.passthru.tests.go-test;

  # The `kdn-certs` test-CA integration suite. It runs the same Go suite with `step`, `sops`, `age`
  # and `openssl` on PATH, so `internal/generate` drives the real generation loop against a
  # temporary unattended CA. The test CA lives outside `data/` and its key is encrypted to a test
  # age identity, so the suite signs with no YubiKey. See design § 8.1.
  kdn-certs-test-ca = pkgs.kdn.kdn-certs.passthru.tests.go-test-ca;

  # The `kdn-journal` Go suite. Every case uses temp fixtures; the real-repository integration
  # test skips when docs/tasks is absent, which is the case in the sandbox.
  kdn-journal-test = pkgs.kdn.kdn-journal.passthru.tests.go-test;

  # The `jj-meta` Go suite: the trailer parser, the session table, the profile builder and the jj
  # runner behind a fake. The two real-jj cases skip in the sandbox.
  jj-meta-test = pkgs.kdn.jj-meta.passthru.tests.go-test;

  # The `jj-meta` binary against a temporary jj repository. It proves what the Go suite fakes: the
  # `json(self)` read, the `mutable()` gate, `describe --stdin` and idempotency. No network, no
  # user configuration, no remote.
  jj-meta-attribute =
    pkgs.runCommand "check-jj-meta-attribute"
      {
        nativeBuildInputs = [
          pkgs.kdn.jj-meta
          pkgs.jujutsu
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export JJ_CONFIG="$TMPDIR/jj.toml"
        mkdir -p "$HOME"
        cat > "$JJ_CONFIG" <<'EOF'
        user.name = "jj-meta check"
        user.email = "check@example.com"
        EOF

        cd "$TMPDIR"
        jj git init >/dev/null
        printf 'subject\n' | jj describe --no-pager -r @ --stdin >/dev/null 2>&1

        jj-meta attribute @ --harness opencode --model test-model --session ses_check
        jj log --no-pager --no-graph -r @ -T 'description' > after-first.txt
        grep -q '^subject$' after-first.txt
        grep -q 'Assisted-by: opencode:test-model' after-first.txt
        grep -q 'Generated-by: opencode:test-model' after-first.txt
        grep -q 'Session-Id: ses_check' after-first.txt
        grep -q 'Harness: opencode' after-first.txt
        grep -q 'Model: test-model' after-first.txt

        # A second run must not rewrite the description.
        cp after-first.txt before-second.txt
        jj-meta attribute @ --harness opencode --model test-model --session ses_check
        jj log --no-pager --no-graph -r @ -T 'description' > after-second.txt
        diff before-second.txt after-second.txt

        # The github profile adds the agent, never the human author.
        jj-meta attribute @ --profile github --coauthor-email bot@example.com \
          --harness opencode --model test-model --session ses_check
        jj log --no-pager --no-graph -r @ -T 'description' > after-github.txt
        grep -q 'Co-authored-by: opencode <bot@example.com>' after-github.txt

        # The gate passes on the attributed change and fails on a bare one.
        jj-meta check @
        jj new -m 'unattributed' >/dev/null 2>&1
        if jj-meta check @; then
          echo "check passed on an unattributed change" >&2
          exit 1
        fi

        # The agent profile writes only the local session key, not a disclosure.
        jj-meta attribute @ --profile agent --harness opencode --model test-model --session ses_check
        jj log --no-pager --no-graph -r @ -T 'description' > after-agent.txt
        grep -q 'Session-Id: ses_check' after-agent.txt
        if grep -q 'Assisted-by' after-agent.txt; then
          echo "the agent profile wrote Assisted-by" >&2
          exit 1
        fi

        # The root change is immutable and must be refused.
        if jj-meta attribute 'root()' --harness opencode --model test-model; then
          echo "attribute accepted the immutable root change" >&2
          exit 1
        fi

        touch "$out"
      '';

  # The parser gate over the real task tree. It copies docs/tasks into a temporary root and runs
  # `kdn-journal doctor --parse-only`, so a broken definition or board fails a check even though
  # .cache/agents is not in the flake source.
  kdn-journal-parse =
    let
      src = pkgs.lib.fileset.toSource {
        root = ../.;
        fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "md") ../docs/tasks;
      };
    in
    pkgs.runCommand "check-kdn-journal-parse"
      {
        nativeBuildInputs = [ pkgs.kdn.kdn-journal ];
      }
      ''
        mkdir -p "$TMPDIR/repo/docs"
        cp -r ${src}/docs/tasks "$TMPDIR/repo/docs/tasks"
        kdn-journal --root "$TMPDIR/repo" doctor --parse-only
        touch "$out"
      '';

  # The committed certificate-expiry summary must match the certificates. The script decodes them
  # in the sandbox and compares the result with `data/certs/expiry.json`; a certificate renewed
  # without re-running `hack/certs-expiry.py` fails here instead of drifting silently until the
  # shell reminder is wrong. The fileset keeps the copy small: the summary, the script, the CA and
  # the SSH host certificates, nothing else.
  kdn-certs-expiry =
    let
      src = pkgs.lib.fileset.toSource {
        root = ../.;
        fileset = pkgs.lib.fileset.unions [
          ../hack/certs-expiry.py
          ../data/certs/expiry.json
          (pkgs.lib.fileset.fileFilter (file: file.hasExt "crt") ../data/ca)
          (pkgs.lib.fileset.fileFilter (file: pkgs.lib.hasSuffix "-cert.pub" file.name) ../hosts)
        ];
      };
    in
    pkgs.runCommand "check-kdn-certs-expiry"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.openssh
          pkgs.openssl
        ];
      }
      ''
        cp -r ${src} src
        chmod -R u+w src
        cd src
        python3 hack/certs-expiry.py --check
        touch $out
      '';

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
