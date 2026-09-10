# The den tree's only wiring into this flake.
#
# This tree is additive. It adds flake outputs and it changes none of the ones that exist today.
# `modules/slots/`, `modules/universal/` and `modules/meta/` stay untouched. README.md in this
# directory holds the plan, the status and the verification commands.
#
# New outputs:
#
#   flake.den                      the raw den evaluation — a debug handle
#   flake.denConfigurations.<name>  a nix-darwin or a NixOS system that den builds
#   flake.denDevenvShells.<name>    a devenv shell that den builds
#   flake.denHomeConfigurations.<name>  a standalone home-manager configuration that den builds
#   flake.denModules.<aspect>       a plain module for an external adopter
#   flake.denLib                    the adopter-facing library — a thin `imports` wrapper plus the
#                                   raw den machinery
#   flake.denful.kdn                the reusable aspect library, for an adopter who **does** adopt
#                                   den. It is the whole surface in one output, and
#                                   `denModules`/`denLib` stay the route for an adopter who does not
#                                   adopt den.
{
  inputs,
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

  # The adopter-facing library. It uses `den.nixModule`, not `den.flakeModule`, so it loads none of
  # den's batteries. It also owns the aspect registry that the evaluation below reads.
  library = import ./lib.nix {
    inherit inputs;
    lib = denLib;
  };

  eval = denLib.evalModules {
    specialArgs.inputs = denInputs;
    modules = [
      inputs.den.flakeModule

      # den's flakeModule declares no `flake.<output>` option by itself. Each output needs its own
      # declaration, and den ships one module per output name it knows.
      inputs.den.flakeOutputs.darwinConfigurations
      inputs.den.flakeOutputs.nixosConfigurations

      # The two namespaces. Every reusable aspect lives in `kdn`; the creator's own data-carrying
      # aspects live in `personal`, which is never exported. See ./namespaces.nix.
      ./namespaces.nix

      # One class per target that den does not know about.
      ./classes/devenv.nix

      # One aspect per reimplemented slot, each one in the `kdn` namespace. The slot itself stays in
      # place and keeps working. The registry lives in ./lib.nix, so the flake route and the
      # library route cannot drift apart.
    ]
    ++ denLib.attrValues library.aspectModules
    ++ [

      # The parallel entities. They live under `checks/den-mvp/` because they are test artifacts,
      # not real hosts. One directory per den host, plus one `devenv/` directory that holds every
      # standalone shell. See ../../checks/den-mvp/README.md.
      ../../checks/den-mvp/host-darwin
      ../../checks/den-mvp/host-nixos
      ../../checks/den-mvp/users
      ../../checks/den-mvp/devenv
      ../../checks/den-mvp/home
    ];
  };

  den = eval.config.den;

  # The reusable aspect library. The `flake.denful` output below hands the same set to an adopter.
  kdn = den.ful.kdn;

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

  # The namespace output. `namespaces.nix` writes `denful.kdn` inside den's own evaluation, so this
  # line copies it out to this flake. An adopter who adopts den merges it with
  # `(inputs.den.namespace "kdn" [ inputs.nix-configs ])`. See ./namespaces.nix.
  flake.denful = eval.config.flake.denful;

  # den writes each entity result to `flake.<intoAttr>` inside its own evaluation. Read the result
  # back with no `or { }` fallback: a wiring mistake must fail loudly here, not pass in silence.
  #
  # Both classes land in one attribute set on purpose. A den host name is unique across the classes,
  # and one flat set keeps the compare commands short. `.config.system.build.toplevel` is the same
  # path in both classes.
  flake.denConfigurations =
    eval.config.flake.darwinConfigurations // eval.config.flake.nixosConfigurations;
  flake.denDevenvShells = eval.config.flake.devenvShells;
  flake.denHomeConfigurations = eval.config.flake.homeConfigurations;

  # The adopter-facing surface. A caller imports a plain module and never adopts den.
  #
  # `denLib` is the wrapper. `denLib.imports { class = "devenv"; aspects = [ "gh" ]; }` returns a
  # list for `imports = [ … ]`. It also carries the raw machinery (`nixModule`, `eval`, `resolve`,
  # `aspectModules`) for a caller that needs more. See ./lib.nix.
  #
  # `denModules.<aspect>` stays as the zero-argument form: one already-resolved plain module per
  # aspect, for that aspect's common class. Use it when one aspect and one class is the whole need.
  flake.denLib = library;
  flake.denModules.rosetta-builder = resolveChecked "darwin" "rosetta-builder" kdn.rosetta-builder;
  flake.denModules.ca = resolveChecked "nixos" "ca" kdn.ca;
  flake.denModules.gh = resolveChecked "devenv" "gh" kdn.gh;

  # The `jj` family, a coupled pair. `jj-fork` names `jj` in its own `includes`, and `jj` names
  # `mcp`, so both entries below join the same diamond as the `mcp` family. den dedupes it.
  #
  # A repository with one remote takes `jj` alone. A repository with a public remote and a private
  # fork takes `jj-fork`, which brings `jj` with it.
  flake.denModules.jj = resolveChecked "devenv" "jj" kdn.jj;
  flake.denModules.jj-fork = resolveChecked "devenv" "jj-fork" kdn.jj-fork;

  # The `llm` family, three aspects across two classes.
  #
  # `llm` serves local models on a NixOS host, so its one class is `nixos`. `llm-client` adds an
  # opencode provider to a devenv shell, so its one class is `devenv`; it includes `opencode`, and it
  # joins that aspect's diamond.
  #
  # `llm-proxy` has no entry here on purpose. It emits both `nixos` and `devenv`, and the
  # zero-argument `denModules.<aspect>` form names exactly one class. `devenv-cli` is absent for the
  # same reason. An adopter reaches a multi-class aspect through `denLib.imports { class = …; }`,
  # which states the class.
  #
  # DECISION TO REVISE: a `denModules.<aspect>-<class>` naming convention would export every class of
  # every aspect. That is a surface decision for the whole tree, not part of this one port.
  flake.denModules.llm = resolveChecked "nixos" "llm" kdn.llm;
  flake.denModules.llm-client = resolveChecked "devenv" "llm-client" kdn.llm-client;

  # The `mcp` family. Each child resolves on its own, and the parent comes with it through
  # `includes`. den dedupes the diamond, so one shell holds one copy of the gateway.
  flake.denModules.mcp = resolveChecked "devenv" "mcp" kdn.mcp;
  flake.denModules.mcp-basic-memory = resolveChecked "devenv" "mcp-basic-memory" kdn.mcp-basic-memory;
  flake.denModules.mcp-pretty-print = resolveChecked "devenv" "mcp-pretty-print" kdn.mcp-pretty-print;
  flake.denModules.mcp-snoop = resolveChecked "devenv" "mcp-snoop" kdn.mcp-snoop;

  # The `nix` aspect includes `mcp`, because it writes two of that aspect's options. So it joins the
  # same diamond as the three children above.
  flake.denModules.nix = resolveChecked "devenv" "nix" kdn.nix;
  flake.denModules.opencode = resolveChecked "devenv" "opencode" kdn.opencode;
  flake.denModules.ssh-agent = resolveChecked "homeManager" "ssh-agent" kdn.ssh-agent;
  flake.denModules.zellij = resolveChecked "devenv" "zellij" kdn.zellij;
}
