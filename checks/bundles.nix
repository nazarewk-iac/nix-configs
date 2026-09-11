# Check bundles. A bundle is one `linkFarm` over the checks it names, so one `nix build` runs every
# member and nix builds the members in parallel. A bare `nix flake check` builds every attribute of
# `checks.<system>`. It measured 660.6 s before the 30 `dev-*` aspects landed. `den-eval-instantiate`
# then grew by 300 s, and 12 more checks landed after that run. So **960 s is a lower bound, not a
# measurement**. Never run it, and never re-measure it — the measurement costs the same 15 minutes
# the rule exists to save. Two rules hold: a non-VM bundle finishes in under 60 s, and every check
# joins one bundle. A check that breaks 60 s alone belongs in `bundle-slow`. Four bundles read a name
# prefix, so a new fast check joins by itself.
#
# **`bundle-den` is a third declared exception to the 60 s rule**, next to `bundle-slow` and
# `bundle-vm`. It runs 108.0 s. The old shed rule — a bundle over 60 s moves its heaviest member to
# `bundle-slow` — no longer applies to it. The reasoning, recorded 2026-09-11:
#
#   - A shed moves cost into `bundle-slow`, and nobody runs that bundle per edit. So a shed **hides**
#     the cost. It does not remove it.
#   - `bundle-core`, at 11.1 s, is the real per-edit tripwire. `bundle-den` is the area bundle you
#     run when you touch an aspect, and about 100 s is acceptable for that job.
#   - 205 aspects cannot fit one 60 s bundle. A split needs a new bundle name, and a bundle name is an
#     infrastructure decision that belongs to the repository owner.
#
# The owner should revise this decision. The alternative is a split of `bundle-den` into two area
# bundles. Times measured 2026-09-11 on `aarch64-darwin`, warm store. ./README.md holds the full
# table.
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
  #     2026-09-11. One shed no longer restores the 60 s ceiling.
  #
  # **This list takes no further member from `bundle-den`.** Five more `den-eval-*` checks landed
  # after the second shed: `router` 5.8 s, `user` 10.6 s, `batch2` 9.3 s, `graphical` 1.7 s and
  # `harness-split` 1.8 s. Each one is far under the 60 s ceiling, so none of them qualifies. The
  # header comment states why `bundle-den` keeps its 108.0 s instead.
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
  # 108.0 s, measured 2026-09-11. One assertion set per den aspect: every `den-eval-*` that is neither
  # cross-cutting nor slow. A new aspect check joins by itself. This bundle is a declared exception to
  # the 60 s ceiling; the header comment holds the decision and its reasoning.
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
  # Empty, and it stays empty. A VM test can NEVER join a bundle, so this is not a reserved slot
  # that somebody fills later.
  #
  # The reason is structural. `mkBundle` above is a `linkFarm` over entries of `checks`, so every
  # member is a derivation. A macOS guest needs three things the Nix sandbox refuses: the Hypervisor
  # entitlement, network access, and a writable disk image outside the store. It also needs `sudo`
  # inside the guest and it mutates a 120 GB disk image. None of that belongs in a derivation.
  # ./den-mvp/tests.nix:21 states the same conclusion from the other side.
  #
  # The Darwin guest activation gate therefore lands as a flake app, `apps.darwin-vm-test`. It runs
  # 5 to 15 minutes per run and it never enters a per-edit loop.
  # docs/tasks/2026-09/darwin-vm-testing/design.md § 7 holds the full argument.
  #
  # The owner may delete this name instead. A bundle name is an infrastructure decision, so this
  # file keeps the name and only corrects the reason.
  bundle-vm = mkBundle "vm" [ ];
}
