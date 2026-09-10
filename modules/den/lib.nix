# den as a library — the adopter-facing surface.
#
# It exports two levels:
#
#   1. `imports` — a thin wrapper. It returns a list of plain modules, ready to drop straight into
#      `imports = [ … ];` of a devenv, a nix-darwin or a NixOS module. The caller adopts no den.
#   2. The raw machinery — `nixModule`, `aspectModules`, `eval` and `resolve`. Use it when the thin
#      wrapper is too narrow, for example to declare an aspect of your own.
#
# This uses `den.nixModule`, not `den.flakeModule`. `nixModule` imports four files and exposes
# exactly `{ aspects, lib, policies }`. It has no `den.hosts`, no `den.schema`, no `den.classes` and
# no `den.default`, so none of den's batteries load. `den.flakeModule` imports all of den's
# `modules/` tree, and the batteries live there.
#
# Measured on 2026-09-10: for both ported aspects, this route and the `flakeModule` route give one
# identical `drvPath`. See
# ../../docs/tasks/2026-09/generalization/004-den-spike/definition.md.
{
  inputs,
  lib,
}:
let
  # The aspect registry. `flake-module.nix` reads the same attribute set, so the two routes cannot
  # drift apart. One entry per reimplemented slot.
  aspectModules = {
    gh = ./aspects/gh.nix;
    rosetta-builder = ./aspects/rosetta-builder.nix;
  };

  # `nix-effects` is explicit on purpose. den's `nix/lib/fx.nix` otherwise fetches it with
  # `builtins.fetchTarball` at evaluation time, and no consumer lock records that fetch.
  mkInputs =
    extraInputs:
    inputs
    // {
      nix-effects.lib = import inputs.nix-effects { inherit lib; };
    }
    // extraInputs;

  # One den library evaluation. It loads every aspect this repository ships, plus the caller's own
  # den modules.
  eval =
    {
      extraInputs ? { },
      modules ? [ ],
    }:
    let
      denInputs = mkInputs extraInputs;
    in
    (lib.evalModules {
      # `den.nixModule` closes over inputs for den's own use and forwards none. An aspect file that
      # takes `inputs` fails with `attribute 'inputs' missing` without this line.
      specialArgs.inputs = denInputs;
      modules = [ (inputs.den.nixModule denInputs) ] ++ lib.attrValues aspectModules ++ modules;
    }).config.den;

  # Resolve one aspect into a plain module, and assert that it configures something.
  #
  # `den.lib.aspects.resolve` returns `{ imports = [ ]; }` for a whole-aspect function. It gives no
  # warning and no error, so an empty module reaches a caller as a silent no-op. Condition 1 of the
  # 004 spike. Every export goes through this guard.
  resolve =
    den: class: aspect:
    let
      name = aspect.name or "<unnamed>";
      module = den.lib.aspects.resolve class aspect;
    in
    if (builtins.length (module.imports or [ ])) > 0 then
      module
    else
      throw ''
        den: the resolved module for aspect `${name}` and class `${class}` has an empty `imports`
        list, so it configures nothing.

        A **whole-aspect** function — `{ host, ... }: { name = …; devenv = …; }` — resolves to an
        empty module across this boundary. den binds an entity argument inside its own evaluation
        only.

        A **per-target** function — `devenv = { host, ... }: …` — resolves to a non-empty module,
        so this guard cannot see it. It then fails inside your own evaluation with `attribute
        'host' missing`. So keep an exported aspect free of entity data, and give it a plain option
        instead. Measured on 2026-09-10.
      '';
in
{
  inherit aspectModules eval resolve;

  # den's own library entry point, unwrapped.
  inherit (inputs.den) nixModule;

  # The thin wrapper.
  #
  #   # devenv.nix
  #   { inputs, ... }:
  #   {
  #     imports = inputs.nix-configs.denLib.imports {
  #       class = "devenv";
  #       aspects = [ "gh" ];
  #     };
  #   }
  #
  # `class` names any evaluation domain. den needs no `den.classes` entry for it.
  # `aspects` names entries of `aspectModules` above.
  # `select` takes the den handle and returns a list of aspects, for an aspect of your own.
  # `modules` adds den modules to the library evaluation, for example a file that declares one.
  # `extraInputs` overrides or adds flake inputs. It defaults to this repository's own inputs, so a
  # caller needs no `nix-rosetta-builder` input of their own.
  imports =
    {
      class,
      aspects ? [ ],
      select ? (_den: [ ]),
      modules ? [ ],
      extraInputs ? { },
    }:
    let
      den = eval { inherit modules extraInputs; };

      # A typo must fail when the caller builds the list, not later when the module system happens
      # to force one element. A `throw` inside `map` stays unevaluated through `builtins.length`,
      # so check every name first and let the `if` carry the throw.
      unknown = lib.subtractLists (builtins.attrNames den.aspects) aspects;
      byName =
        if unknown == [ ] then
          map (name: den.aspects.${name}) aspects
        else
          throw ''
            den: no aspect named ${builtins.concatStringsSep ", " (map (n: "`${n}`") unknown)}.
            Known aspects: ${builtins.concatStringsSep ", " (builtins.attrNames den.aspects)}.
          '';
    in
    map (resolve den class) (byName ++ select den);
}
