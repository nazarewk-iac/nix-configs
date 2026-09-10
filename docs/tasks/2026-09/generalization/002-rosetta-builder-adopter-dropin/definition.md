---
type: Task
description: Make the rosetta-builder slot usable in an external adopter's nix-darwin through a minimal mkSlots call, and add phased enablement of the two builders.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 002 — `rosetta-builder` for an external adopter

Hub: [the generalization umbrella task](../definition.md). Depends on 001. Part of the first
commit chain. Do not push.

Goal: an external adopter enables the dual-arch Rosetta builder in their own nix-darwin
configuration. Then the adopter builds multi-arch containers in their own repos.

## The adopter API is a minimal `mkSlots` call

An adopter may call `mkSlots`. That is acceptable and expected. The requirement is narrower:

> The slot must not depend on the other module types at all.

So do **not** extract the slot into a plain nix-darwin module. Do not add a payload/wrapper split.
Verify the independence instead. Document the call.

## What the slot is today

`modules/slots/rosetta-builder/default.nix`. It imports
`inputs.nix-rosetta-builder.darwinModules.default` and adds three opinions:

```nix
nix-rosetta-builder.enable = true;
nix-rosetta-builder.onDemand = lib.mkDefault true;
nix.settings.builders-use-substitutes = lib.mkDefault true;
```

It also declares three guest options of its own — `guest.diskSizeMax`, `guest.minFree` and
`guest.maxFree` — and one assertion that holds the effective `diskSize` at or under the ceiling
`guest.diskSizeMax` (`"150GiB"`). The slot deliberately does **not** set `diskSize`: upstream's
`100GiB` default stands, because any change to `diskSize` destroys and recreates the guest. The
`darwin` target is a module function, not a plain attribute set, because the assertion must read
the consumer's own effective `diskSize`.

Favourable facts, already verified:

- It uses **no** `pkgs.kdn.*`, so it needs no overlay.
- It uses **no** `kdnConfig`.
- Its only external need is `inputs.nix-rosetta-builder`, which `mkSlots` supplies through
  `specialArgs`.
- `nix-rosetta-builder` writes its own `nix.buildMachines` entry with
  `systems = [ <hostLinux> "x86_64-linux" ]` (`docs/multi-arch-builder.md:170`). So the slot needs
  no builder configuration from this repo.

It must **not** gain any dependency on `modules/universal/profile/remote-builders/default.nix`
(`docs/multi-arch-builder.md:295`), which holds the creator's own fleet inventory.

## 1. Add phased enablement of the two builders

This is the substantive code change in this checkpoint.

`nix-rosetta-builder` needs a Linux builder that already exists to build its own Lima guest image
the first time (`docs/multi-arch-builder.md:176`). So a first-time adopter needs stock
`nix.linux-builder` active first, then the Rosetta VM, then optionally the stock builder off again.
Today the adopter must know this and wire it by hand.

Make the slot express the phases. Settle the option surface during implementation. This is a
sketch:

| Phase | Meaning |
|---|---|
| bootstrap | Stock `nix.linux-builder` on, Rosetta builder on. Both advertised. |
| steady | Rosetta builder only. |

Requirements:

- The default must be safe for a first-time adopter. The adopter must reach the bootstrap phase
  without a read of the source.
- Both builders on at once must not conflict over `nix.buildMachines` entries or SSH ports.
- Avoid a manual edit between two `darwin-rebuild switch` runs. When you cannot avoid it, say so in
  the option description and in the runbook.

## 2. Tell the adopter about the `i686-linux` gap

The builder cannot build `i686-linux`. Rosetta for Linux is x86_64-only, so its binfmt handler
registers only the x86_64 ELF magic. Full analysis:
[rosetta-builder-i686-linux.md](../../../2026-08/rosetta-builder-i686-linux/definition.md).

An adopter hits this on any 32-bit derivation. State the limitation in the slot's option
description and in the adopter doc. Do not attempt a fix here.

## 3. Verify the builder covers the container use case

The stated need is "build other repos' multi-arch containers". Confirm what the builder does and
does not cover. `docs/multi-arch-container-builder.md` is a handover doc of approaches with
tradeoffs. It states it "Requires the dual-arch builder". So the image-index assembly stays the
adopter's own job.

Check what else the adopter needs that the slot does not supply: container tooling, `binfmt`,
registry authentication, or `extra-platforms`. Report the answer in the adopter doc. Do not add
scope here.

## 4. Document the call

Add the worked `mkSlots` snippet to `docs/slots-for-adopters.md` (from 001). Reference it from the
runbook (003). An adopter needs: one flake input, one `mkSlots` call, one
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
  **This one criterion runs on bare metal only.** It is unreachable in a macOS guest, and that is
  permanent — see the boundary below.

## The nested-virtualization boundary

Every other criterion above runs in a macOS guest. This last one never can.

`nix-rosetta-builder` drives `limactl`, which starts a **Linux** virtual machine. A Linux guest
inside a macOS guest needs nested virtualization. Apple exposes
`isNestedVirtualizationEnabled` on `VZGenericPlatformConfiguration` only, which is the Linux-guest
platform class. The property does not exist on `VZMacPlatformConfiguration`. So a macOS guest
cannot start any virtual machine of its own, whatever the host chip is.

Tart states the same limit from the other side: its `--nested` flag reads "Enable nested
virtualization if possible" and it rejects a macOS guest.

Consequence for the test plan: the Linux builder sits **beside** the macOS guest on the bare-metal
host, never inside it. A macOS guest verifies the adopter's evaluation, the option surface and the
runbook prose. Bare metal verifies the build itself. Record which side proved which claim.

## Out of scope

Do not extract the slot into a plain nix-darwin module. Do not fix `i686-linux`. Do not build the
container image-index tooling.
