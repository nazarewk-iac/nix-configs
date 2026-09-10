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
# ## The namespace, and the two modules it needs here
#
# Every reusable aspect lives in the `kdn` namespace — see ./namespaces.nix. `nixModule` declares
# neither `den.ful` nor `den.classes`, so a namespace needs two extra modules on this route.
# Measured on 2026-09-10: with both of them, the library route carries a namespace, and den still
# collapses a diamond `includes` to one import.
#
# This route creates the `kdn` namespace **unexported**, and it creates no `personal` namespace at
# all. A consumer's own `modules` may declare aspects in `kdn`; a reference to `personal` fails
# here by design.
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
    ca = ./aspects/ca.nix;
    devenv-cli = ./aspects/devenv-cli.nix;
    gh = ./aspects/gh.nix;
    jj = ./aspects/jj.nix;
    jj-fork = ./aspects/jj-fork.nix;
    mcp = ./aspects/mcp.nix;
    mcp-basic-memory = ./aspects/mcp-basic-memory.nix;
    mcp-pretty-print = ./aspects/mcp-pretty-print.nix;
    mcp-snoop = ./aspects/mcp-snoop.nix;
    nix = ./aspects/nix.nix;
    opencode = ./aspects/opencode.nix;
    rosetta-builder = ./aspects/rosetta-builder.nix;
    ssh-agent = ./aspects/ssh-agent.nix;
    zellij = ./aspects/zellij.nix;
  };

  # The namespace name. `namespaces.nix` uses the same one on the `flakeModule` route.
  namespaceName = "kdn";

  # den's namespace machinery is not in `den.nixModule`. Two modules make it reachable:
  #
  #   1. den's own `modules/aspects.nix` declares `den.ful` and `flake.denful`. It needs the `den`
  #      module argument, and `nixModule` supplies that (`_module.args.den = config.den`).
  #   2. `den.classes` needs a declaration, because `namespace.nix` merges each source's classes
  #      into it. Nothing on this route reads the value, so a plain `raw` shim is enough. den's own
  #      declaration lives in `modules/options.nix`, which also declares `den.hosts` and
  #      `den.schema` — importing that file would pull in the entity machinery this route avoids.
  namespaceSupport = [
    (import (inputs.den + "/modules/aspects.nix"))
    {
      options.den.classes = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        internal = true;
        visible = false;
        description = "A shim for `den.namespace`. See ./lib.nix.";
      };
    }
  ];

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
      modules = [
        (inputs.den.nixModule denInputs)
      ]
      ++ namespaceSupport
      ++ [ (inputs.den.namespace namespaceName false) ]
      ++ lib.attrValues aspectModules
      ++ modules;
    }).config.den;

  # Resolve one aspect into a plain module, and assert that it configures something.
  #
  # `den.lib.aspects.resolve` returns `{ imports = [ ]; }` for a whole-aspect function. It gives no
  # warning and no error, so an empty module reaches a caller as a silent no-op. Condition 1 of the
  # 004 spike. Every export goes through this guard.
  resolve =
    den: class: aspect:
    let
      # A whole-aspect function has no `name` attribute, and `or` does not catch the type error
      # that `<function>.name` raises. Test the shape first, so the message below stays reachable.
      name = if lib.isFunction aspect then "<function>" else aspect.name or "<unnamed>";
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
  inherit
    aspectModules
    eval
    resolve
    namespaceName
    ;

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
  # `aspects` names entries of `aspectModules` above. Each one resolves through `den.ful.kdn`.
  # `select` takes the den handle and returns a list of aspects, for an aspect of your own. Reach a
  #   namespaced aspect with `d: [ d.ful.kdn.<name> ]`.
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
      # The registry is the name list, not `den.ful.kdn`. A namespace attribute set also holds the
      # structural keys `_`, `schema`, `classes` and `stages`, and none of those is an aspect.
      unknown = lib.subtractLists (builtins.attrNames aspectModules) aspects;
      byName =
        if unknown == [ ] then
          map (name: den.ful.${namespaceName}.${name}) aspects
        else
          throw ''
            den: no aspect named ${builtins.concatStringsSep ", " (map (n: "`${n}`") unknown)}.
            Known aspects: ${builtins.concatStringsSep ", " (builtins.attrNames aspectModules)}.
          '';
    in
    map (resolve den class) (byName ++ select den);
}
