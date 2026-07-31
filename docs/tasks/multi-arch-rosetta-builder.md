---
type: Task
description: Enable a Rosetta-backed dual-arch (aarch64-linux + x86_64-linux) Nix builder on the PLTP-9KMGDM Apple Silicon host via nix-rosetta-builder (docs/multi-arch-builder.md Option C).
status: in-progress
authored_by: agent
timestamp: 2026-07-31T12:00:00+02:00
---

# Multi-arch Rosetta builder on PLTP-9KMGDM

Implement [docs/multi-arch-builder.md](../multi-arch-builder.md) **Option C**
(`cpick/nix-rosetta-builder`) so this `aarch64-darwin` workstation builds **both**
`aarch64-linux` and `x86_64-linux` locally, x86_64 via Rosetta 2 (near-native) instead of
QEMU-TCG. Container-image stitching ([docs/multi-arch-container-builder.md](../multi-arch-container-builder.md))
is explicitly **out of scope** for this task — builder first.

## Approach (host-specific first, module later)

Per the plan: start host-specific in a file sibling to the host's `default.nix`, get it
working, then consider extracting a reusable module.

- Add flake input `nix-rosetta-builder` (`github:cpick/nix-rosetta-builder`, `nixpkgs`
  follows `nixpkgs`).
- New `hosts/PLTP-9KMGDM/rosetta-builder.nix` imports
  `inputs.nix-rosetta-builder.darwinModules.default` and sets:
  - `nix-rosetta-builder.enable = true` (module default; explicit for clarity)
  - `nix-rosetta-builder.onDemand = true` (power VM off when idle)
  - `nix.settings.builders-use-substitutes = true`
- Keep the stock `nix.linux-builder` (aarch64-linux) enabled in `default.nix` for the
  **bootstrap dance** — nix-rosetta-builder needs an existing Linux builder to build its own
  Lima guest image the first time. Can be disabled in a follow-up once the Rosetta VM is up.

## Notes

- `nix-rosetta-builder` registers `nix.buildMachines` for both `linuxSystem` (aarch64-linux)
  and `x86_64-linux` on port `31122`, and sets `nix.distributedBuilds = mkForce true`.
- `darwin-rebuild switch` is a host-level action for the owner to run — the agent stages the
  config and builds, then hands back the switch command.
- Follow-up: the `x86_64-linux` filter TODO in
  `modules/universal/profile/remote-builders/default.nix:104` can be revisited once this host
  builds x86_64 locally.
