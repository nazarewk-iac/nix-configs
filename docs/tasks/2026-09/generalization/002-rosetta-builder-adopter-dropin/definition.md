---
type: Task
description: Make the rosetta-builder slot usable in an external adopter's nix-darwin through a minimal mkSlots call, and add phased enablement of the two builders.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 002 — `rosetta-builder` for an external adopter

Hub: [../generalization-plan.md](../definition.md). Depends on 001. Part of the first
commit chain. Do not push.

Goal: an external adopter enables the dual-arch Rosetta builder in their own nix-darwin
configuration, then builds multi-arch containers in their own repos.

## The adopter API is a minimal `mkSlots` call

An adopter calling `mkSlots` is acceptable and expected. The requirement is narrower:

> The slot must not depend on the other module types at all.

So do **not** extract the slot into a plain nix-darwin module, and do not add a payload/wrapper
split. Verify the independence instead, and document the call.

## What the slot is today

`modules/slots/rosetta-builder/default.nix`, 41 LOC. It imports
`inputs.nix-rosetta-builder.darwinModules.default` and adds three opinions:

```nix
nix-rosetta-builder.enable = true;
nix-rosetta-builder.onDemand = lib.mkDefault true;
nix.settings.builders-use-substitutes = lib.mkDefault true;
```

Favourable facts, already verified:

- It uses **no** `pkgs.kdn.*`, so it needs no overlay.
- It uses **no** `kdnConfig`.
- Its only external need is `inputs.nix-rosetta-builder`, which `mkSlots` supplies through
  `specialArgs`.
- `nix-rosetta-builder` writes its own `nix.buildMachines` entry with
  `systems = [ <hostLinux> "x86_64-linux" ]` (`docs/multi-arch-builder.md:170`), so the slot needs
  no builder wiring from this repo.

It must **not** gain any dependency on `modules/universal/profile/remote-builders/default.nix`
(`docs/multi-arch-builder.md:295`), which holds the creator's own fleet inventory.

## 1. Add phased enablement of the two builders

This is the substantive code change in this checkpoint.

`nix-rosetta-builder` needs an existing Linux builder to build its own Lima guest image the first
time (`docs/multi-arch-builder.md:176`). So a first-time adopter needs stock `nix.linux-builder`
running, then the Rosetta VM, then optionally the stock builder off again. Today the adopter has to
know this and wire it by hand.

Make the slot express the phases. Sketch of the option surface, to be settled during
implementation:

| Phase | Meaning |
|---|---|
| bootstrap | Stock `nix.linux-builder` on, Rosetta builder on. Both advertised. |
| steady | Rosetta builder only. |

Requirements:

- The default must be safe for a first-time adopter, so the bootstrap phase is reachable without
  reading source.
- Both builders on at once must not conflict over `nix.buildMachines` entries or SSH ports.
- The transition must not need a manual edit between two `darwin-rebuild switch` runs if that can
  be avoided; if it cannot, say so in the option description and in the runbook.

## 2. Tell the adopter about the `i686-linux` gap

The builder cannot build `i686-linux`. Rosetta for Linux is x86_64-only, so its binfmt handler
registers only the x86_64 ELF magic. Full analysis:
[rosetta-builder-i686-linux.md](../../../rosetta-builder-i686-linux.md).

An adopter hits this on any 32-bit derivation. State the limitation in the slot's option
description and in the adopter doc. Do not attempt a fix here.

## 3. Verify the container use case is covered

The stated need is "build other repos' multi-arch containers". Confirm what the builder does and
does not cover. `docs/multi-arch-container-builder.md` is a handover doc of approaches with
tradeoffs, and it states it "Requires the dual-arch builder" — so image-index stitching stays the
adopter's own job.

Check whether anything else is needed that the slot does not supply: container tooling, `binfmt`,
registry authentication, or `extra-platforms`. Report the answer in the adopter doc rather than
adding scope here.

## 4. Document the call

Add the worked `mkSlots` snippet to `docs/slots-for-adopters.md` (created in 001) and reference it
from the runbook (003). An adopter needs: one flake input, one `mkSlots` call, one
`kdn.darwin.rosetta-builder.enable = true`, and the `imports` entry for the rendered `darwin`
target.

## Exit criteria

- Pattern V3: a scratch nix-darwin flake under `/tmp`, outside this repo, with only
  `inputs.nix-configs` and a minimal `mkSlots` call, evaluates
  `config.system.build.toplevel.drvPath` successfully.
- Pattern V2: the same evaluation succeeds with no SSH agent.
- The evaluation pulls in no `modules/universal` or `modules/meta` option.
- The bootstrap phase and the steady phase both evaluate.
- A real `x86_64-linux` derivation builds on the Darwin host through the Rosetta builder.

## Out of scope

Extracting the slot into a plain nix-darwin module. Fixing `i686-linux`. Building the container
image-index tooling.
