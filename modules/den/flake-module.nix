# The den tree's only wiring into this flake.
#
# This tree is additive. It adds flake outputs and it changes none of the ones that exist today.
# `modules/slots/`, `modules/universal/` and `modules/meta/` stay untouched. README.md in this
# directory holds the plan, the status and the verification commands.
#
# New outputs:
#
#   flake.den                      the raw den evaluation — a debug handle
#   flake.denConfigurations.<host>  a nix-darwin system that den builds
#   flake.denDevenvShells.<host>    a devenv shell that den builds
#   flake.denModules.<aspect>       a plain module for an external adopter
{
  inputs,
  self,
  ...
}:
let
  # den reads `lib` from `inputs.nixpkgs`. This repo's extended `lib` stays out of den's own
  # evaluation, so no den module can depend on a `lib.kdn.*` helper.
  denLib = inputs.nixpkgs.lib;

  # den declares no flake input of its own. Its whole `flake.nix` is `outputs = _: import ./nix;`,
  # so it reads every input from `specialArgs.inputs`.
  #
  # `nix-effects` is explicit on purpose. den's `nix/lib/fx.nix` otherwise fetches it with
  # `builtins.fetchTarball` at evaluation time, keyed off den's own vendored lock file. No consumer
  # lock records that fetch. This is condition 3 of the 004 spike.
  denInputs = inputs // {
    nix-effects.lib = import inputs.nix-effects { lib = denLib; };
  };

  eval = denLib.evalModules {
    specialArgs.inputs = denInputs;
    modules = [
      inputs.den.flakeModule

      # den's flakeModule declares no `flake.<output>` option by itself. Each output needs its own
      # declaration, and den ships one module per output name it knows.
      inputs.den.flakeOutputs.darwinConfigurations
      inputs.den.flakeOutputs.nixosConfigurations

      # One class per target that den does not know about.
      ./classes/devenv.nix

      # One aspect per reimplemented slot. The slot itself stays in place and keeps working.
      ./aspects/rosetta-builder.nix

      # One directory per parallel host. They live under `hosts/den-mvp/` because
      # `flake.hostConfigurations` reads `hosts/` one level deep only, so it never sees them. See
      # ../../hosts/den-mvp/README.md.
      ../../hosts/den-mvp/den-darwin
      ../../hosts/den-mvp/den-nixos

      # devenv needs a root directory, and only the flake knows one.
      { kdn.den.devenv.root = "${self}"; }
    ];
  };

  den = eval.config.den;

  # Condition 1 of the 004 spike.
  #
  # `den.lib.aspects.resolve` returns `{ imports = [ ]; }` for an aspect that reads entity data. It
  # gives no warning and no error, so an empty module reaches an adopter as a silent no-op.
  # Measured on 2026-09-10 — see docs/tasks/2026-09/generalization/004-den-spike/research.md. Every
  # adopter-facing export goes through this guard.
  resolveChecked =
    class: name: aspect:
    let
      module = den.lib.aspects.resolve class aspect;
    in
    if (builtins.length (module.imports or [ ])) > 0 then
      module
    else
      throw ''
        den: the resolved module `denModules.${name}` for class `${class}` has an empty `imports`
        list, so it configures nothing.

        A den aspect that takes an entity argument — for example `{ host, ... }` — resolves to an
        empty module across the export boundary. Keep an adopter-facing aspect free of entity data.
        Give it a plain option instead.
      '';
in
{
  flake.den = den;

  # den writes each entity result to `flake.<intoAttr>` inside its own evaluation. Read the result
  # back with no `or { }` fallback: a wiring mistake must fail loudly here, not pass in silence.
  #
  # Both classes land in one attribute set on purpose. A den host name is unique across the classes,
  # and one flat set keeps the compare commands short. `.config.system.build.toplevel` is the same
  # path in both classes.
  flake.denConfigurations =
    eval.config.flake.darwinConfigurations // eval.config.flake.nixosConfigurations;
  flake.denDevenvShells = eval.config.flake.devenvShells;

  # The adopter-facing surface. An adopter imports a plain module and never adopts den.
  flake.denModules.rosetta-builder =
    resolveChecked "darwin" "rosetta-builder"
      den.aspects.rosetta-builder;
}
