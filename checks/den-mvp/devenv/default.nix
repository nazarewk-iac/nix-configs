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
  ];

  mkStandalone =
    name: system:
    config.kdn.den.devenv.mkShell {
      inherit name system;
      modules = map (den.lib.aspects.resolve "devenv") aspects;
    };
in
{
  flake.devenvShells = lib.mapAttrs mkStandalone {
    devenv-darwin = "aarch64-darwin";
    devenv-linux = "x86_64-linux";
  };
}
