# Check bundles. A bundle is one `linkFarm` over the checks it names, so one `nix build` runs every
# member and nix builds the members in parallel. A bare `nix flake check` measured 660.6 s before the
# 30 `dev-*` aspects landed. `den-eval-instantiate` then grew by 300 s, so expect about 960 s now.
# Never run it. The four fast bundles together take about 119 s. Two rules hold: a non-VM bundle
# finishes in under 60 s, and every check joins one bundle. A check that breaks 60 s alone belongs in
# `bundle-slow`, and a bundle over 60 s sheds its heaviest member to the same place. Four bundles read
# a name prefix, so a new fast check joins by itself. Times measured 2026-09-11 on `aarch64-darwin`,
# warm store. ./README.md holds the full table.
{
  pkgs,
  lib,
  checks,
}:
let
  byPrefix = p: builtins.filter (lib.hasPrefix p) (builtins.attrNames checks);
  mkBundle =
    name: members:
    pkgs.linkFarm "check-bundle-${name}" (
      map (n: {
        name = n;
        path = checks.${n};
      }) (builtins.filter (n: checks ? ${n}) members)
    );
  # Four members break 60 s alone: 83.3, 358.0, 75.0 and 188.4 s. `den-eval-instantiate` cost 58.0 s
  # until the 30 `dev-*` aspects took the registry from 137 pairs to 201, measured 2026-09-11.
  #
  # Two members do not break 60 s alone. Each one is the heaviest member `bundle-den` holds at the
  # time it moves here, and each move follows the shed rule above.
  #
  #   - `den-eval-hw`, 25.3 s alone. Four batches of aspects took `bundle-den` to 75.4 s, so the
  #     bundle shed it. Two runs then gave 49.3 s and 50.2 s.
  #   - `den-eval-programs`, 19.4 s alone. Five more area checks took `bundle-den` to 98.6 s, so the
  #     bundle shed it too. The shed saves 19.5 s and the bundle then runs 79.1 s, measured
  #     2026-09-11. One shed no longer restores the 60 s ceiling. The owner decides the next step.
  slow = [
    "den-eval-routes"
    "den-eval-instantiate"
    "den-eval-hw"
    "den-eval-programs"
    "den-mvp"
    "jj-experiments-pytest"
  ];
  # Cross-cutting: each reads a bare consumer, not one aspect.
  crossCutting = [
    "den-eval-coverage"
    "den-eval-defaults"
    "den-eval-frozen-paths"
    "den-eval-guards"
    "den-eval-priority"
  ];
in
{
  # The broad tripwires. Run this first after any edit. A new `universal-eval-*` check joins by
  # itself, so a guard test of `modules/universal/` needs no edit here.
  bundle-core = mkBundle "core" (
    [
      "hello"
      "standalone-slots"
      "standalone-aspects"
      "conditional-imports-mechanism"
      "conditional-imports-repository"
    ]
    ++ crossCutting
    ++ byPrefix "universal-eval-"
  );
  # 79.1 s, measured 2026-09-11. One assertion set per den aspect: every `den-eval-*` that is neither
  # cross-cutting nor slow. A new aspect check joins by itself. This bundle is over the 60 s ceiling.
  bundle-den = mkBundle "den" (lib.subtractLists (crossCutting ++ slow) (byPrefix "den-eval-"));
  # 18.0 s. The two package test suites that finish in seconds.
  bundle-pkgs = mkBundle "pkgs" [
    "kdn-slug-pytest"
    "zellij-llm-pytest"
  ];
  # 43.7 s with the system closure already in the store; a cold store builds a system first, and that
  # costs minutes. Empty on `aarch64-linux`, which carries neither prefix.
  bundle-artifact = mkBundle "artifact" (byPrefix "den-artifact-" ++ byPrefix "den-smoke-");
  # 710.6 s. `den-eval-instantiate` alone holds 358.0 s of that.
  bundle-slow = mkBundle "slow" slow;
  # Reserved and empty. No VM test exists — ./den-mvp/tests.nix states why. This is the one bundle the
  # 60 s rule does not cover.
  bundle-vm = mkBundle "vm" [ ];
}
