---
type: Task
description: Shrink the system closure of the headless hosts and repair kdn-nix-collect-garbage, so a small cloud server keeps its store near the closure size.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-14T00:03:02+02:00
---

# Shrink the system closure and repair the collector

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

Host `moss` is a headless Hetzner server with a 38 GB disk. Its store held 22 GB while the system
closure was only about 10 GiB. Two separate causes kept the store large:

1. **Stale GC roots.** An old home-manager profile of a deleted user, an old root
   home-manager generation, and a 2022 `channels` root each held a whole closure alive.
2. **A bloated closure.** The closure carried documentation, the full Rust toolchain, the Qt
   stack, and tracing libraries that a server does not use.

## Approach

- Repair `kdn-nix-collect-garbage` so it removes a per-user profile that has no passwd entry, and
  so it treats a `home-manager-N-link` as active only when the home `current-home` gcroots points
  at it.
- Add one `kdn.minimalServer` switch at the top of the options. A headless host turns it on.
- Gate each heavy item on `kdn.minimalServer` or on `kdn.desktop.enable`, so a desktop host keeps
  the package and a server drops it.
- Record the booted-system GC behaviour in `docs/nix-dev.md`, because a collection after a switch
  cannot free the closure of the generation that the machine booted.
