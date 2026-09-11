---
type: Reference
title: Checks
description: Run a check bundle, never a bare nix flake check.
authored_by: agent
timestamp: 2026-09-11T20:45:00+02:00
---

# Checks

Full doc, with a command and a measured time per check: [checks/README.md](../../checks/README.md)

**Never run a bare `nix flake check`.** It builds all **63** attributes of `checks.<system>` — 57 real
checks plus 6 bundles, counted 2026-09-11. It measured 660.6 s before 12 more checks landed, so
**960 s is a lower bound**. Never re-measure it. Run a bundle. `bundle-core` 11.1 s covers any edit;
`bundle-den` 108.0 s covers `modules/den/aspects/`; `bundle-pkgs` 18.0 s covers `packages/`;
`bundle-artifact` 43.7 s covers a built artifact; `bundle-slow` 710.6 s runs before a hand-off.
`bundle-vm` is reserved and empty. Every time is a 2026-09-11 snapshot and drifts up as an area grows.

`bundle-slow` holds every check over 60 s, plus `den-eval-hw` and `den-eval-programs`. Each of those
two left `bundle-den` to hold the 60 s ceiling. `den-eval-instantiate` is the heaviest check at 358.0 s.

**`bundle-den` is a third declared exception to the 60 s ceiling**, next to `bundle-slow` and
`bundle-vm`. It sheds no further member: its five newest members cost 1.7 s to 10.6 s each, so no
single shed helps, and a split needs a new bundle name that the repository owner must approve.
`checks/bundles.nix` holds the full reasoning.

```bash
SYS=aarch64-darwin   # or x86_64-linux, or aarch64-linux
nix build --no-eval-cache -L ".#checks.$SYS.bundle-core"   # a whole bundle
nix build --no-eval-cache -L ".#checks.$SYS.den-eval-gh"   # one check, standalone
```

Three flags, three traps: **`--no-eval-cache`**, because Nix caches an evaluation *failure* and replays
it — a sub-second failure is almost always a stale entry. **`-L`**, because the assertion lines live in
the build log. **`--keep-going`**, because a bundle stops at its first failed member.
