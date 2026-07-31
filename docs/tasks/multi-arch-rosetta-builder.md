---
type: Task
description: Add a Rosetta-backed dual-arch (aarch64-linux + x86_64-linux) Nix builder darwin slot via nix-rosetta-builder (docs/multi-arch-builder.md Option C), and wire it to an aarch64-darwin host.
status: done
authored_by: agent
timestamp: 2026-07-31T12:00:00+02:00
---

# Multi-arch Rosetta builder slot

Implement [docs/multi-arch-builder.md](../multi-arch-builder.md) **Option C**
(`cpick/nix-rosetta-builder`) so an `aarch64-darwin` host builds **both** `aarch64-linux` and
`x86_64-linux` locally. x86_64 runs under Rosetta 2 (near-native) instead of QEMU-TCG.
Container-image stitching
([docs/multi-arch-container-builder.md](../multi-arch-container-builder.md)) is out of scope for
this task — builder first.

## Approach (host-specific first, slot later)

Start host-specific in a file sibling to a host `default.nix`. Get it working. Then extract a
reusable slot.

- Add flake input `nix-rosetta-builder` (`github:cpick/nix-rosetta-builder`, `nixpkgs` follows
  `nixpkgs`).
- Add `modules/slots/rosetta-builder/default.nix` — the first slot that targets the `darwin`
  slot target. All earlier slots target `devenv` only. It declares
  `options.kdn.darwin.rosetta-builder.enable` and, under `config.darwin`:
  - imports `inputs.nix-rosetta-builder.darwinModules.default`
  - `nix-rosetta-builder.enable = true` (module default; explicit for clarity)
  - `nix-rosetta-builder.onDemand = lib.mkDefault true` (power the VM off when idle)
  - `nix.settings.builders-use-substitutes = lib.mkDefault true`
- Keep the stock `nix.linux-builder` (aarch64-linux) enabled on the host for the **bootstrap
  dance**. nix-rosetta-builder needs an existing Linux builder to build its own Lima guest image
  the first time. Disable it in a follow-up once the Rosetta VM is up.
- Wire the slot into a host through
  `(kdnConfig.self.mkSlots { inherit pkgs; kdn.darwin.rosetta-builder.enable = true; }).config.darwin`.
  This is the first darwin host that consumes `mkSlots`; before this, only `devenv.nix` consumed
  slots.

## Notes

- `nix-rosetta-builder` registers `nix.buildMachines` for both `linuxSystem` (aarch64-linux) and
  `x86_64-linux` on port `31122`, and sets `nix.distributedBuilds = mkForce true`.
- `darwin-rebuild switch` is a host-level action for the owner to run. The agent stages the
  config and builds, then hands back the switch command.
- Follow-up: the `x86_64-linux` filter TODO in
  `modules/universal/profile/remote-builders/default.nix:104` can be revisited once a host builds
  x86_64 locally.
