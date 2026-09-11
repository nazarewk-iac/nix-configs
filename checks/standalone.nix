# Enforce the standalone rule, for the slots and for the den aspects.
#
# `.agents/rules/slots-standalone.md` states a hard rule for a slot: it must neither reference nor
# assign an option that `modules/universal/` or `modules/meta/` declares, and it must not take the
# `kdnConfig` argument. Each aspect header states three rules of its own: no entity argument, no
# `enable` option, no custom module argument. Until now nothing enforced either statement.
#
# Two mechanisms run here, because neither one covers the whole rule.
#
# | Mechanism | It catches | It misses |
# |---|---|---|
# | source scan | an assignment **and** a read, in live code and in a dead `mkIf` branch | a computed path such as `kdn.<name>.x` |
# | option-tree walk | a custom module argument, an entity argument, a reachable `enable` | a read that no value forces |
#
# Measured on 2026-09-11 with `lib.evalModules`:
#
#  * An **assignment** to an undeclared option fails, and `lib.mkIf false` does not hide it. So an
#    evaluation catches a dead-branch assignment.
#  * A **read** of an undeclared option throws nothing. The value stays unforced, so the read never
#    happens. An evaluation therefore misses every read, and the source scan is the only guard.
#
# The scan drops a whole-line comment and keeps a trailing comment. A hit in a trailing comment is
# a false positive that fails the build. That is the safe direction: a false positive is loud, and
# a silent skip is not.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  denLib = inputs.self.denLib;

  # Same shape as ./den-mvp/tests.nix tier 1. Every assertion is `{ name; expected; actual; }`, the
  # comparison happens at evaluation time, and the derivation only reports it.
  mkCheck =
    name: assertions:
    let
      failures = lib.filter (a: a.actual != a.expected) assertions;
      total = toString (builtins.length assertions);
      line = a: "  ${a.name}: want ${builtins.toJSON a.expected}, got ${builtins.toJSON a.actual}";
    in
    pkgs.runCommand "standalone-${name}"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      (
        if failures == [ ] then
          ''
            echo "standalone ${name}: ${total} of ${total} assertions pass" >&2
            touch $out
          ''
        else
          ''
            {
              echo "standalone ${name}: ${toString (builtins.length failures)} of ${total} assertions FAIL"
            ${lib.concatMapStringsSep "\n" (a: "  echo ${lib.escapeShellArg (line a)}") failures}
            } >&2
            exit 1
          ''
      );

  # --------------------------------------------------------------- the source scan

  # One hit per (file, line, needle). `dir` is a path literal, so the derivation reads the tree the
  # evaluation already holds and copies nothing extra.
  scan =
    dir: needles:
    let
      files = builtins.filter (p: lib.hasSuffix ".nix" (toString p)) (
        lib.filesystem.listFilesRecursive dir
      );
      codeLines =
        path:
        builtins.filter (l: !(lib.hasPrefix "#" (lib.trim l))) (
          lib.splitString "\n" (builtins.readFile path)
        );
      hitsIn =
        path:
        let
          rel = lib.removePrefix (toString dir + "/") (toString path);
        in
        lib.concatMap (
          entry:
          map (needle: "${rel}:${toString entry.number}: ${needle}") (
            builtins.filter (needle: lib.hasInfix needle entry.line) needles
          )
        ) (lib.imap1 (number: line: { inherit number line; }) (codeLines path));
    in
    lib.concatMap hitsIn files;

  # Every `kdn.*` leaf that `modules/universal/` declares, plus the one `modules/meta/` prefix. A
  # leaf, never the `kdn.nix` prefix: the `nix` slot declares `kdn.nix.extraBashAllow` under the
  # same parent, and a prefix match would flag it.
  universalPaths = [
    "kdn.enable"
    "kdn.args"
    "kdn.hostName"
    "kdn.nixConfig"
    "kdn.nixpkgs."
    "kdn.nix.substituters"
    "kdn.nix.remote-builder"
    "kdn.homebrew."
    "kdn.apps."
    "kdn.desktop."
    "kdn.development."
    "kdn.disks."
    "kdn.emulation."
    "kdn.env."
    "kdn.fs."
    "kdn.headless."
    "kdn.helpers."
    "kdn.hw."
    "kdn.locale."
    "kdn.managed."
    "kdn.monitoring."
    "kdn.networking."
    "kdn.outputs."
    "kdn.packaging."
    "kdn.profile."
    "kdn.programs."
    "kdn.security."
    "kdn.services."
    "kdn.toolset."
    "kdn.virtualisation."
    "k8s.clusters."
  ];

  # The three needles that apply to both trees.
  treePaths = [
    "kdnConfig"
    "modules/universal"
    "modules/meta"
  ];

  slotHits = scan ../modules/slots (universalPaths ++ treePaths);

  # The aspects get `treePaths` only. An aspect legitimately declares `kdn.homebrew.*`,
  # `kdn.ca.*` and `kdn.signing.*`, so `universalPaths` would flag its own options.
  aspectHits = scan ../modules/den/aspects treePaths;

  # --------------------------------------------------------------- the slots tree resolve

  # The whole slots tree resolves with `pkgs` and `inputs` as the only special arguments. A slot
  # that takes `kdnConfig` in its own arguments fails here, because no such argument exists.
  slotsRendered = inputs.self.lib.kdn.mkSlots {
    slotModules = [ (inputs.self + "/modules/slots") ];
    specialArgs = {
      inherit pkgs;
      inputs = inputs // {
        nix-configs = inputs.self;
      };
    };
  };

  # --------------------------------------------------------------- the aspect option trees

  # den adds these keys to every aspect attribute set. The rest name the classes the aspect emits.
  structuralKeys = [
    "_"
    "__functor"
    "__providesForwarded"
    "classes"
    "description"
    "excludes"
    "includes"
    "meta"
    "name"
    "policies"
    "provides"
  ];

  den = denLib.eval { };
  namespace = den.ful.${denLib.namespaceName};
  aspectNames = builtins.attrNames denLib.aspectModules;
  classesOf = name: lib.subtractLists structuralKeys (builtins.attrNames namespace.${name});

  # One option tree per (aspect, class) pair. `pkgs` is the only special argument, so a target
  # module that takes `inputs`, `kdnConfig` or an entity argument fails right here.
  # `_module.check = false` tolerates every definition that names a consumer option, so the tree
  # gathers with no consumer at all.
  optionsOf =
    name: class:
    (lib.evalModules {
      modules = denLib.imports {
        inherit class;
        aspects = [ name ];
      }
      ++ [ { _module.check = false; } ];
      specialArgs = {
        inherit pkgs;
      };
    }).options;

  pairs = lib.concatMap (name: map (class: "${name}/${class}") (classesOf name)) aspectNames;

  # Forcing `options ? _module` forces the whole option gather, so this list names every pair that
  # resolves. An unresolvable pair throws instead.
  resolvedPairs = lib.concatMap (
    name:
    map (
      class: if (optionsOf name class) ? _module then "${name}/${class}" else "${name}/${class}: broken"
    ) (classesOf name)
  ) aspectNames;

  # Walk the option tree and stop at an option. An `enable` inside an `attrsOf submodule` is
  # unreachable this way, so the walk permits the seven per-instance flags and needs no allowlist
  # for them.
  reachableEnables =
    prefix: attrs:
    lib.concatLists (
      lib.mapAttrsToList (
        key: value:
        let
          path = "${prefix}.${key}";
        in
        if key == "_module" then
          [ ]
        else if (value._type or "") == "option" then
          (if key == "enable" then [ path ] else [ ])
        else if builtins.isAttrs value then
          reachableEnables path value
        else
          [ ]
      ) attrs
    );

  # The one documented exception. `modules/den/aspects/llm.nix` states the reason in the option's
  # own description: the Caddy vhost points at the proxy port with no condition, so a separate
  # aspect would have to reach back into `llm`. Remove this entry when that design lands.
  allowedEnables = [ "llm/nixos: kdn.llm.local.compatProxy.enable" ];

  enableHits = lib.subtractLists allowedEnables (
    lib.concatMap (
      name:
      lib.concatMap (
        class:
        map (path: "${name}/${class}: ${path}") (
          reachableEnables "kdn" ((optionsOf name class).kdn or { })
        )
      ) (classesOf name)
    ) aspectNames
  );

  # --------------------------------------------------------------- the assertions

  slotAssertions = [
    {
      name = "no slot names a universal option, a meta option, or kdnConfig";
      expected = [ ];
      actual = slotHits;
    }
    {
      name = "the whole slots tree resolves with pkgs and inputs alone";
      expected = [
        "darwin"
        "devenv"
        "home"
        "kdn"
        "nixos"
        "users"
      ];
      actual = builtins.sort (a: b: a < b) (builtins.attrNames slotsRendered.config);
    }
  ];

  aspectAssertions = [
    {
      name = "no aspect names kdnConfig, modules/universal, or modules/meta";
      expected = [ ];
      actual = aspectHits;
    }
    {
      name = "every aspect and class resolves with pkgs as the only special argument";
      expected = pairs;
      actual = resolvedPairs;
    }
    {
      name = "no aspect declares a reachable enable option";
      expected = [ ];
      actual = enableHits;
    }
  ];
in
{
  checks = {
    standalone-slots = mkCheck "slots" slotAssertions;
    standalone-aspects = mkCheck "aspects" aspectAssertions;
  };
}
