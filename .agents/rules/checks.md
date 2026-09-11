---
type: Reference
title: Checks
description: Run a check bundle, never a bare nix flake check.
authored_by: agent
timestamp: 2026-09-11T00:00:00Z
---

# Checks

Full doc, with a command and a measured time per check: [checks/README.md](../../checks/README.md)

**Never run a bare `nix flake check`.** It builds all 36 checks and takes over 660 s — 11 minutes,
measured 2026-09-11. Run a bundle. `bundle-core` 16.7 s covers any edit; `bundle-den` about 35 s covers
`modules/den/aspects/`; `bundle-pkgs` 18.0 s covers `packages/`; `bundle-artifact` 43.7 s covers a
built artifact; `bundle-slow` about 383 s runs before a hand-off. `bundle-vm` is reserved and empty.

```bash
SYS=aarch64-darwin   # or x86_64-linux, or aarch64-linux
nix build --no-eval-cache -L ".#checks.$SYS.bundle-core"   # a whole bundle
nix build --no-eval-cache -L ".#checks.$SYS.den-eval-gh"   # one check, standalone
```

Three flags, three traps: **`--no-eval-cache`**, because Nix caches an evaluation *failure* and replays
it — a sub-second failure is almost always a stale entry. **`-L`**, because the assertion lines live in
the build log. **`--keep-going`**, because a bundle stops at its first failed member.
