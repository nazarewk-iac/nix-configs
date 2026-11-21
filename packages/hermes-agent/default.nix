# Hermes Agent (NousResearch/hermes-agent): a Python CLI plus a messaging gateway, MIT.
#
# Task: docs/tasks/2026-11/ai-workshop/.
#
# ## Why `python3.withPackages` and not the upstream flake
#
# Upstream ships a `flake.nix` built on uv2nix, plus npm builds for its TUI and web
# frontends. Both are a second packaging system to track (uv2nix, pyproject-nix, a
# pnpm store hash) for one host-local container. This repository's convention is a
# `callPackage`-able package with explicit Python dependencies, so the pinned commit
# is packaged that way: `fetchFromGitHub` + `python314.withPackages`.
#
# ## What the upstream Nix wrapper does that this file reproduces
#
# The project's `setup.py` refuses to build a wheel outside a Nix build (it raises
# unless `HERMES_NIX_BUILD=1`), because a wheel alone ships none of the data the
# runtime reads: bundled skills, plugins, locale catalogs, the MCP catalog. Upstream
# resolves those through `HERMES_BUNDLED_*` environment variables set by its wrapper
# (`scripts/build/inputs.py`, `hermes_constants.py::_packaged_dir`). This file sets
# the same variables, pointing at the fetched source tree, which is immutable in the
# Nix store and therefore safe to read in place.
#
# ## What this file deliberately does NOT ship
#
# - `browser-harness` (the engine of the `browser_exec` tool): NOT in nixpkgs. The
#   tool's own `check_fn` hides it when the import fails, so the CLI and the gateway
#   are unaffected. See `docs/tasks/2026-11/ai-workshop/definition.md`.
# - The npm frontends (`--tui`, `hermes web`, `hermes webapp`): they need a pnpm
#   build of `ui-tui/`, `web/` and `webapp/`. The classic REPL and every headless
#   path (`-z`, `gateway run`) are Python-only.
# - `pm` runtime provisioning (`hermes pm ...`): it installs Python packages with uv
#   into a writable tree, which a read-only store cannot provide. The dependency
#   groups a container needs are baked in below instead (see `messagingDeps`).
{
  lib,
  pkgs,
  fetchFromGitHub,
}:
let
  rev = "52b527194b364ba073c85f0b1cd8c63bc9264cac";
  version = "0.0.0-unstable-2026-11-21";

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = "sha256-hlgrJcVQre3uIeDnVrJwRT6tDf5TCi07bT2LdONKDC4=";
  };

  # The project supports 3.11-3.14 and pins every dependency with a
  # `python_version >= '3.14'` marker, so only 3.14 gets any dependency at all from
  # `pip`; nixpkgs' newest interpreter is therefore the only correct choice.
  python = pkgs.python314;

  # Core dependencies, from `[project].dependencies` in pyproject.toml (the
  # linux-only subset: the win32/darwin-only pins are absent on purpose).
  #
  # Two entries of that list are deliberately absent:
  #
  # - `browser-harness`: NOT in nixpkgs at all (checked 2026-11-21). The `browser_exec`
  #   tool's own `check_fn` hides the tool when the import fails, so nothing else
  #   changes.
  # - `nemo-relay`: nixpkgs ships 0.7.3 while the project pins `>=0.11,<0.12` (the
  #   `nemo_relay.observability` / `nemo_relay.plugin` modules it calls do not exist in
  #   0.7.3), and 0.7.3 does not even build on this nixpkgs pin: its `aws-lc-sys`
  #   dependency inherits nixpkgs' `AWS_LC_SYS_USE_SYSTEM=1` crate override without the
  #   `aws-lc` build input the override assumes. The runtime treats a missing module as
  #   a supported platform condition (`hermes_cli/doctor_config.py`: "NeMo Relay is not
  #   available on this platform") and loads it lazily (`agent/relay_runtime.py`), so
  #   only Relay telemetry is lost.
  coreDeps =
    ps: with ps; [
      certifi
      croniter
      cryptography # PyJWT[crypto]
      fastapi
      fire
      firecrawl-anydoc
      httptools
      httpx
      jinja2
      markdown
      openai
      packaging
      pathspec
      pillow
      pillow-heif
      prompt-toolkit
      psutil
      ptyprocess
      pydantic
      pyjwt
      python-dotenv
      python-multipart
      requests
      resvg-py
      rich
      ruamel-yaml
      ruamel-yaml-clib
      snowballstemmer
      socksio # httpx[socks]
      tomli-w
      truststore
      urllib3
      uvicorn
      watchfiles
      websockets
    ];

  # The `[messaging]` extra, baked in because the gateway imports its platform
  # adapters lazily and upstream's own Nix packaging ships a `messaging` variant for
  # exactly this reason: a lazy install would have to write into the read-only store.
  messagingDeps =
    ps: with ps; [
      aiohttp
      brotlicffi
      discordpy
      python-telegram-bot
      qrcode
      slack-bolt
      slack-sdk
    ];

  # The project itself. `setup.py` derives the root single-file modules at build time
  # (`run_agent`, `hermes_state`, `toolsets`, ...) and guards the wheel build, so the
  # two `env` entries below are required, not cosmetic.
  pythonSet = python.override {
    packageOverrides =
      final: _prev:
      {
        hermes-agent = final.buildPythonPackage {
          pname = "hermes-agent";
          inherit version src;
          pyproject = true;

          # The guard in setup.py.
          env.HERMES_NIX_BUILD = "1";

          # `[build-system].requires` pins setuptools and wheel to exact versions as
          # part of the project's PyPI supply-chain policy. The build runs with
          # `--no-isolation` against nixpkgs' own setuptools/wheel, and `build` refuses
          # any version difference, so the pins have to go. Only the build backend is
          # affected; the runtime pins stay declared in `dependencies`.
          postPatch = ''
            substituteInPlace pyproject.toml \
              --replace-fail 'setuptools==84.1.0' 'setuptools' \
              --replace-fail 'wheel==0.48.0' 'wheel'
          '';

          build-system = [
            final.setuptools
            final.wheel
          ];
          dependencies = coreDeps final ++ messagingDeps final;

          # No test suite run: upstream's is thousands of tests against live
          # providers, and it is not what this package has to prove. The container
          # smoke test in hosts/etra/hermes.nix is.
          doCheck = false;
          # nixpkgs ships newer/older versions than the exact `==` pins in
          # pyproject.toml (openai 3.x against a 2.54 pin, for example). The runtime
          # check refuses any difference; the pins are a PyPI supply-chain measure,
          # not an API contract this build can honour.
          dontCheckRuntimeDeps = true;
          # Nothing imports the project at build time; skip the import probe.
          pythonImportsCheck = [ ];

          meta = {
            description = "Self-improving AI agent with a messaging gateway";
            homepage = "https://github.com/NousResearch/hermes-agent";
            license = lib.licenses.mit;
            mainProgram = "hermes";
          };
        };
      };
  };

  # Interpreter plus the project: `/bin/hermes`, `/bin/hermes-agent`, `/bin/hermes-acp`.
  pythonEnv = pythonSet.withPackages (ps: [ ps.hermes-agent ]);

  # Non-Python tools the agent's toolshell expects on PATH. `ripgrep` and `git` are
  # what its search/file tools call; `openssh` covers its remote-workspace mode.
  runtimeDeps = [
    pkgs.git
    pkgs.openssh
    pkgs.ripgrep
  ];

  # Every variable the upstream wrapper sets, plus the ones that make a read-only
  # install usable. Read by `hermes_constants.py::_packaged_dir` and
  # `hermes_cli/plugins.py`; a missing variable silently falls back to
  # `<HERMES_HOME>/<subdir>`, i.e. an empty directory, so each one matters.
  dataEnv = {
    HERMES_BUNDLED_SKILLS = "${src}/skills";
    HERMES_OPTIONAL_SKILLS = "${src}/optional-skills";
    HERMES_BUNDLED_PLUGINS = "${src}/plugins";
    HERMES_BUNDLED_LOCALES = "${src}/locales";
    HERMES_OPTIONAL_MCPS = "${src}/optional-mcps";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "hermes-agent";
  inherit version src;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    # One wrapper per console script. `--set-default` so an operator can still
    # point a variable elsewhere with `nerdctl exec -e`.
    wrap() {
      makeWrapper "${pythonEnv}/bin/$1" "$out/bin/$1" \
        --set-default HERMES_PYTHON "${pythonEnv}/bin/python3" \
        --suffix PATH : "${lib.makeBinPath runtimeDeps}" \
        ${lib.concatStringsSep " \\\n        " (
          lib.mapAttrsToList (name: value: "--set-default ${name} ${lib.escapeShellArg value}") dataEnv
        )}
    }
    wrap hermes
    wrap hermes-agent
    wrap hermes-acp

    runHook postInstall
  '';

  passthru = {
    inherit python pythonEnv src;
    # `pkgs.hermes-agent.pythonEnv` is the interpreter that has every dependency and
    # the project importable; use it to run a script against the same environment.
    interpreter = pythonEnv;
  };

  meta = {
    description = "Self-improving AI agent with a messaging gateway";
    homepage = "https://github.com/NousResearch/hermes-agent";
    license = lib.licenses.mit;
    mainProgram = "hermes";
    platforms = lib.platforms.linux;
  };
}
