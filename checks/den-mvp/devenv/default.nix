# The standalone devenv shells. They belong to no den host. See ../README.md.
#
# These shells use no den entity. `den.lib.aspects.resolve <class> <aspect>` takes a plain class
# name. It needs no host, no entity kind and no `den.classes` entry. So one directory holds every
# standalone shell, with one entry per system.
#
# Do NOT declare a den host with `class = "devenv"` here. den always includes its
# `insecure-predicate` aspect through `den.default.includes`, and that aspect injects
# `${host.class}.imports` with an OS-shaped module that sets `config.nixpkgs`. A host whose class
# is not an OS class then fails with `The option 'nixpkgs' does not exist`. A bare `resolve` never
# reads `den.default`, so it carries no such limit.
#
# Measured on 2026-09-10: this bare resolve and the same resolve from a `den.nixModule`
# library-only evaluation give one identical shell drvPath. See
# ../../../docs/tasks/2026-09/generalization/004-den-spike/research.md.
{
  config,
  den,
  inputs,
  kdn,
  lib,
  ...
}:
let
  # One aspect list, shared by every standalone shell.
  aspects = [
    kdn.gh

    # The four-target aspect. Its `devenv` half is new — the slot has none. See
    # ../../../modules/den/aspects/devenv-cli.nix.
    kdn.devenv-cli

    # The `zellij` aspect. It is the first aspect that installs a repository file, so it also tests
    # the `kdn.isSourceRepo` switch below.
    kdn.zellij

    # The `opencode` aspect. It declares options and holds no data of its own, so `opencodeData`
    # below supplies every value. It stays out of the two host aspect lists on purpose: `gh` and
    # `zellij` already prove the host-to-devenv route, and one wrapper build per shell is enough.
    kdn.opencode

    # The `mcp` family, four aspects. Only the two leaves appear here: `mcp-snoop` includes `mcp`,
    # and `mcp-basic-memory` includes `mcp-pretty-print`, which includes `mcp` too. So the list
    # itself proves den dedupes the diamond — one shell must hold one gateway, not two.
    #
    # The family stays out of both host aspect lists. `gh` and `zellij` already prove the
    # host-to-devenv route, and this family builds a Python application and a Python virtual
    # environment, so one build per shell is enough.
    kdn.mcp-snoop
    kdn.mcp-basic-memory

    # The `nix` aspect. It includes `mcp` too, because it writes two of that aspect's options — so
    # this list holds four includers of one parent and still must give one gateway. It is also the
    # first aspect that registers a git-hooks pre-commit hook, so it is the reason
    # `den.devenv.inputs.git-hooks` below exists.
    kdn.nix

    # The `jj` family, a coupled pair. Only the leaf appears here: `jj-fork` includes `jj`, and `jj`
    # includes `mcp`. So this list now reaches four direct includers of one parent and still must
    # give one gateway. `jjData` below supplies every value, because neither aspect names a remote.
    #
    # The family stays out of both host aspect lists. `gh` and `zellij` already prove the
    # host-to-devenv route, and this family builds an npm package, so one build per shell is enough.
    kdn.jj-fork
  ];

  # The data for the `nix` aspect. The aspect allow-lists no flake app of its own, because an app
  # name belongs to the consumer. So the entity names one neutral placeholder.
  nixData = {
    kdn.nix.extraBashAllow = [ "nix run .#example-formatter -- *" ];
  };

  # The data for the `mcp` family. The aspects name no knowledge base, no knowledge root and no
  # `mcp-servers-nix` source, so the entity supplies each one.
  mcpData = {
    # The stub source. `mcp-servers-nix` is a `devenv.yaml` input, so no den evaluation reaches the
    # real one. The stub implements the one function the aspect calls, and it turns the aspect's own
    # `programs` declarations into servers — so the translation code gets a real test. See
    # ../mcp-servers-nix-stub/lib/default.nix.
    kdn.mcp.serversNix = ../mcp-servers-nix-stub;

    # Two bases, with neutral names. The creator's own bases and the creator's own knowledge root
    # belong in the real consumer, never in an aspect and never here.
    kdn.mcp.basic-memory.knowledgeRoot = "$HOME/.local/share/den-mvp/knowledge";
    kdn.mcp.basic-memory.bases.general = {
      aliases = [ "bmg" ];
      description = "den MVP general knowledge base";
    };
    kdn.mcp.basic-memory.bases.archive = {
      aliases = [ "bma" ];
      description = "den MVP archive knowledge base";
    };
  };

  # The data for the `jj` family. Every value here is a neutral placeholder. Both aspects name no
  # remote and no denied pattern: a remote name and a denied pattern are the consumer's own private
  # configuration, and a denied pattern reaches a world-readable store path through `runtimeEnv`.
  jjData = {
    kdn.jj.upstream.remote = "public";
    kdn.jj.fork.remote = "private";

    # Three pattern lists, each one a neutral term that names nothing real. The real lists live in
    # this repository's own git-ignored `devenv.slots.local.nix`, never in a test and never in a
    # default.
    kdn.jj.alwaysBlockedMessagePatterns = [ "den-mvp-blocked-message" ];
    kdn.jj.fork.deniedFilePatterns = [ "den-mvp-denied-path" ];
    kdn.jj.fork.deniedMessagePatterns = [ "den-mvp-denied-message" ];
  };

  # The two remote URLs reach `enterShell` only. `devenv-darwin` sets both and `devenv-linux` sets
  # neither, so both branches of the `optionalString` get a test.
  jjUrlData = {
    kdn.jj.upstream.url = "https://example.invalid/den-mvp/public.git";
    kdn.jj.fork.url = "https://example.invalid/den-mvp/private.git";
  };

  # The data for the `opencode` aspect. Every value here is a neutral placeholder — the aspect
  # itself names no provider, no model and no checkout path. See
  # ../../../modules/den/aspects/opencode.nix.
  opencodeData = {
    kdn.opencode.allowedPaths = [
      "/nix/store/**"
      "~/src/**"
    ];
    kdn.opencode.authKeys.EXAMPLE_PROVIDER_API_KEY = "example-provider";
    kdn.opencode.settings.provider.example-provider = { };
    kdn.opencode.wrapper.env.KDN_DEN_MVP = "1";
    kdn.opencode.wrapper.preExec = "true # the den MVP checks this line reaches the wrapper";

    # The entity's own smoke assertions. An aspect tests its own shape; only the entity knows which
    # placeholder values must reach the generated wrapper.
    enterTest = ''
      echo "• opencode (entity): the wrapper exports the entity's credential" >&2
      grep -q 'EXAMPLE_PROVIDER_API_KEY=' "$(command -v opencode)"

      echo "• opencode (entity): the wrapper carries the entity's env and pre-exec line" >&2
      grep -q 'KDN_DEN_MVP=' "$(command -v opencode)"
      grep -q 'the den MVP checks this line' "$(command -v opencode)"
    '';
  };

  # `extra` holds plain consumer modules, next to the resolved aspects. The two shells differ in
  # one value only, so both branches of `kdn.isSourceRepo` get a test — see ../tests.nix.
  mkStandalone =
    name:
    {
      system,
      extra ? [ ],
    }:
    config.den.devenv.mkShell {
      inherit name system;
      modules = (map (den.lib.aspects.resolve "devenv") aspects) ++ extra;
    };
in
{
  # The real `git-hooks` flake input, for every devenv shell this tree builds. The `nix` aspect
  # registers a pre-commit hook, and devenv reads the input from `specialArgs.inputs` — see
  # ../../../modules/den/classes/devenv.nix. A flake reaches its own inputs' inputs, so this needs no
  # new entry in `flake.nix` and no lock file change. `devenv` renamed the input from
  # `pre-commit-hooks` to `git-hooks`; `flake.lock` records the current name.
  den.devenv.inputs.git-hooks = inputs.devenv.inputs.git-hooks;

  flake.devenvShells = lib.mapAttrs mkStandalone {
    # The adopter shape. `kdn.isSourceRepo` keeps its default `false`, so the `zellij` aspect
    # installs its skill file. `kdn.opencode.package` keeps its default, so the wrapper execs the
    # real `pkgs.opencode`, and `defaultModel` names a model.
    devenv-darwin.system = "aarch64-darwin";
    devenv-darwin.extra = [
      opencodeData
      mcpData
      nixData
      jjData
      jjUrlData
      { kdn.opencode.defaultModel = "example-provider/example-model"; }
    ];

    # This repository's own shape. It commits the skill file itself, so no aspect installs one.
    #
    # It also holds the two negative cases of the `opencode` aspect: a `package` override, and
    # `defaultModel` left null so the `model` key stays out of `opencode.jsonc`.
    devenv-linux.system = "x86_64-linux";
    devenv-linux.extra = [
      opencodeData
      mcpData
      nixData
      jjData
      { kdn.isSourceRepo = true; }
      (
        { pkgs, ... }:
        {
          kdn.opencode.package = pkgs.writeShellScriptBin "opencode-under-test" ''
            echo "den-mvp stub" >&2
          '';
        }
      )
    ];
  };
}
