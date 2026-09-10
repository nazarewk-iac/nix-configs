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
  lib,
  ...
}:
let
  # One aspect list, shared by every standalone shell.
  aspects = [
    den.aspects.gh

    # The four-target aspect. Its `devenv` half is new — the slot has none. See
    # ../../../modules/den/aspects/devenv-cli.nix.
    den.aspects.devenv-cli

    # The `zellij` aspect. It is the first aspect that installs a repository file, so it also tests
    # the `kdn.isSourceRepo` switch below.
    den.aspects.zellij

    # The `opencode` aspect. It declares options and holds no data of its own, so `opencodeData`
    # below supplies every value. It stays out of the two host aspect lists on purpose: `gh` and
    # `zellij` already prove the host-to-devenv route, and one wrapper build per shell is enough.
    den.aspects.opencode
  ];

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
    config.kdn.den.devenv.mkShell {
      inherit name system;
      modules = (map (den.lib.aspects.resolve "devenv") aspects) ++ extra;
    };
in
{
  flake.devenvShells = lib.mapAttrs mkStandalone {
    # The adopter shape. `kdn.isSourceRepo` keeps its default `false`, so the `zellij` aspect
    # installs its skill file. `kdn.opencode.package` keeps its default, so the wrapper execs the
    # real `pkgs.opencode`, and `defaultModel` names a model.
    devenv-darwin.system = "aarch64-darwin";
    devenv-darwin.extra = [
      opencodeData
      { kdn.opencode.defaultModel = "example-provider/example-model"; }
    ];

    # This repository's own shape. It commits the skill file itself, so no aspect installs one.
    #
    # It also holds the two negative cases of the `opencode` aspect: a `package` override, and
    # `defaultModel` left null so the `model` key stays out of `opencode.jsonc`.
    devenv-linux.system = "x86_64-linux";
    devenv-linux.extra = [
      opencodeData
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
