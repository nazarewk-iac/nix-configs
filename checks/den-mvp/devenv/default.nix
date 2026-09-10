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
  ];

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
    # installs its skill file.
    devenv-darwin.system = "aarch64-darwin";

    # This repository's own shape. It commits the skill file itself, so no aspect installs one.
    devenv-linux.system = "x86_64-linux";
    devenv-linux.extra = [ { kdn.isSourceRepo = true; } ];
  };
}
