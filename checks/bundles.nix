# Check bundles. A bundle is one `linkFarm` over the checks it names, so one `nix build` runs every
# member and nix builds the members in parallel. A bare `nix flake check` takes 660 s; the four fast
# bundles together take about 111 s. Two rules hold: a non-VM bundle finishes in under 60 s, and every
# check joins one bundle. A check that breaks 60 s alone belongs in `bundle-slow`. Four bundles read a
# name prefix, so a new fast check joins by itself. Times measured 2026-09-11 on `aarch64-darwin`,
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
  # Each one breaks 60 s alone: 83.3, 58.0, 75.0 and 188.4 s.
  slow = [
    "den-eval-routes"
    "den-eval-instantiate"
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
  # 32.2 s. One assertion set per den aspect: every `den-eval-*` that is neither cross-cutting nor
  # slow. A new aspect check joins by itself.
  bundle-den = mkBundle "den" (lib.subtractLists (crossCutting ++ slow) (byPrefix "den-eval-"));
  # 18.0 s. The two package test suites that finish in seconds.
  bundle-pkgs = mkBundle "pkgs" [
    "kdn-slug-pytest"
    "zellij-llm-pytest"
  ];
  # 43.7 s with the system closure already in the store; a cold store builds a system first, and that
  # costs minutes. Empty on `aarch64-linux`, which carries neither prefix.
  bundle-artifact = mkBundle "artifact" (byPrefix "den-artifact-" ++ byPrefix "den-smoke-");
  # About 383 s.
  bundle-slow = mkBundle "slow" slow;
  # Reserved and empty. No VM test exists — ./den-mvp/tests.nix states why. This is the one bundle the
  # 60 s rule does not cover.
  bundle-vm = mkBundle "vm" [ ];
}
