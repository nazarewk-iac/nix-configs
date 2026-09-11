---
type: Task
title: Give the den check harness more than one platform
description: The bare consumers are hard-wired to x86_64-linux and set three values at plain priority, so an aarch64-only aspect cannot pass den-eval-instantiate.
status: in-progress
authored_by: agent
timestamp: 2026-09-11T20:30:00+02:00
parent: ../definition.md
---

# 015 — Give the den check harness more than one platform

Parent task: [../definition.md](../definition.md).

## The problem

`den-eval-instantiate` forces every (aspect, class) pair in the registry. It uses the bare consumers
from `checks/den-mvp/harness.nix`. Those consumers name one platform only, and they set three values
at PLAIN priority. So an aspect that needs another platform, or that must set one of those three
values, cannot enter the registry.

Three lines cause this:

| Site | Value | Effect |
|---|---|---|
| `checks/den-mvp/harness.nix:84` | `nixpkgs.hostPlatform = "x86_64-linux"` | every bare NixOS evaluation is x86_64 |
| `checks/den-mvp/harness.nix:85-88` | `fileSystems."/"` at PLAIN priority | a module that also sets it at plain priority stops the evaluation |
| `checks/den-mvp/harness.nix:89` | `boot.loader.grub.enable = false` at PLAIN priority | an aspect's `lib.mkDefault` can never win |

## The blocked work

### Example 1 — `hw-rpi4`

`modules/universal/profile/hardware/rpi4/default.nix` has no den aspect. Batch 18 measured two
independent failures on the current harness:

1. `nixos-hardware.nixosModules.raspberry-pi-4` raises an unsupported-system error.
2. `sd-image.nix` sets `fileSystems."/".fsType = "ext4"` at plain priority. The harness sets
   `"tmpfs"` at plain priority. Two plain definitions of one option stop the evaluation.

All three modules build correctly on `aarch64-linux`.

**A `forceData` row cannot fix failure 2.** A row adds modules to a consumer. It cannot lower the
priority of a definition the consumer already makes.

### Example 2 — an aspect that owns the boot loader

`checks/den-mvp/harness.nix:89` writes `boot.loader.grub.enable = false` at plain priority. An aspect
that writes the same option with `lib.mkDefault` always loses, so its assertion cannot read the
aspect's own value. The batch-19 editor found this and worked around it: that check builds a local
subject from `inputs.nixpkgs.lib.nixosSystem` and omits the one grub line. The work-around proves the
gap and duplicates the harness, so it must not become the pattern.

## The four changes this needs

1. Add an `aarch64-linux` bare NixOS consumer next to the existing one.
2. Add a per-pair platform table, so a pair names the consumer it needs. Default to the current
   consumer, so no landed pair changes.
3. Change the harness `fileSystems."/"` to `lib.mkDefault`. Then a hardware module that sets a real
   root filesystem wins, and every current pair keeps the `tmpfs` value.
4. Change the harness `boot.loader.grub.enable` to `lib.mkDefault`. Then an aspect that owns the boot
   loader wins, and the local work-around subject of batch 19 returns to the shared harness.

Changes 3 and 4 touch every den check, so measure `bundle-core`, `bundle-den` and
`den-eval-instantiate` before and after.

## Cost note

`den-eval-instantiate` costs 358 s warm, measured 2026-09-11. It grew from 58 s when the registry
went from 137 pairs to over 200. A second platform adds a second whole evaluation for each pair that
opts in, not for every pair.

## Exit test

`hw-rpi4` enters the registry, `den-eval-instantiate` passes, and `bundle-core` still passes. No
landed pair changes its resolved module set. No check builds its own local `nixosSystem` subject.

## Evidence

- `checks/den-mvp/harness.nix:77-94` — the bare NixOS consumer and all three hard-wired values
- `checks/den-mvp/harness.nix:30` — where the per-check derivation is built
- Batch 18 plan at `.cache/agent-notes/sub-agent-outputs/layerc-b18-hw-profiles-and-orphans/plan.md`
  — the two measured failures and the `aarch64-linux` control
