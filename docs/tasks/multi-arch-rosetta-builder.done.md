---
type: Task
description: Solution — a rosetta-builder darwin slot lets an aarch64-darwin host build both aarch64-linux and x86_64-linux locally through nix-rosetta-builder (Option C); x86_64 runs under Rosetta 2, not QEMU-TCG.
status: done
authored_by: agent
timestamp: 2026-08-04T12:00:00+02:00
---

# Solution — multi-arch Rosetta builder slot

## Root cause analysis

An `aarch64-darwin` host can build `aarch64-linux` through the stock `nix.linux-builder`, but not
`x86_64-linux` at usable speed. QEMU-TCG emulation of x86_64 is very slow.
`docs/multi-arch-builder.md` Option C (`cpick/nix-rosetta-builder`) runs a single Linux VM that
registers both arches, with x86_64 under Rosetta 2 (near-native) instead of QEMU-TCG.

## Solution

- Added flake input `nix-rosetta-builder` (`github:cpick/nix-rosetta-builder`) with
  `inputs.nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs"` in `flake.nix`.
- Added `modules/slots/rosetta-builder/default.nix` — the first slot that targets the `darwin`
  slot target. All earlier slots target `devenv` only. It declares
  `options.kdn.darwin.rosetta-builder.enable` and, under `config.darwin`:
  - imports `inputs.nix-rosetta-builder.darwinModules.default`
  - `nix-rosetta-builder.enable = true;`
  - `nix-rosetta-builder.onDemand = lib.mkDefault true;` (power the VM off when idle)
  - `nix.settings.builders-use-substitutes = lib.mkDefault true;` (the VM pulls from public
    caches instead of the host uploading everything over the slow VM link)
- A host keeps the stock `nix.linux-builder` (aarch64-linux) enabled for the bootstrap dance.
  nix-rosetta-builder needs an existing Linux builder to build its own Lima guest image the first
  time.
- Wire the slot into a host through
  `(kdnConfig.self.mkSlots { inherit pkgs; kdn.darwin.rosetta-builder.enable = true; }).config.darwin`.
  This is the first darwin host that consumes `mkSlots`; before this, only `devenv.nix` consumed
  slots.

## Verification steps

- A first `nix run '.#darwin-rebuild' -- build <host>` (inside zellij-llm) reached the top
  `✔ darwin-system-26.11.57a3171`, 151 builds, ~21m. The Rosetta VM's Lima guest image built on
  the stock `linux-builder` (bootstrap dance confirmed).
- After the slot extraction, the same build re-ran green (EXIT:0). `nix eval` of
  `config.nix.buildMachines` returns systems `[["aarch64-linux" "x86_64-linux"] ["aarch64-linux"]]`
  — the Rosetta dual-arch VM plus the stock linux-builder — so the slot produces the same
  `nix.buildMachines` as the earlier host-specific file.
- The slot builds for the `anji` host too:
  `nix run '.#darwin-rebuild' -- build anji` reaches `darwin-system` without activation.
- After activation on a host:
  - `/etc/nix/machines` lists `ssh-ng://rosetta-builder aarch64-linux,x86_64-linux` on the
    Rosetta VM, plus the stock `ssh-ng://builder@linux-builder aarch64-linux`.
  - launchd service `org.nixos.rosetta-builderd` is loaded.
  - Trivial builds return the right arch: `x86_64-linux` → `x86_64`, `aarch64-linux` → `aarch64`,
    both copied from `ssh-ng://rosetta-builder`.
  - Real flake packages built for x86_64-linux: `.#packages.x86_64-linux.kdn-slug` and
    `.#packages.x86_64-linux.data-converters`. The Python interpreter in the `kdn-slug` closure is
    a genuine x86_64 ELF (`e_machine = 0x3e`, EM_X86_64), so the builder compiles real x86_64
    binaries, not aarch64 or cache-fetched Darwin.

## Follow-up notes

- A `git+file://` fetch blocker can surface first: `error: unexpected end-of-file` from a dangling
  `refs/remotes/<remote>/HEAD` symref (points at a removed branch). Nix's libgit2 fetcher is
  stricter than the git CLI. Fix with `git remote set-head <remote> <branch>`. See the agent
  memory note on this failure mode.
- The stock `nix.linux-builder` stays enabled for now. The Rosetta VM already registers
  aarch64-linux, so disabling the stock builder is a possible later cleanup — not done here to
  keep a known-good fallback.
- The config started host-specific in a `rosetta-builder.nix` sibling file, then moved into the
  `modules/slots/rosetta-builder/` slot once it was known-good. The old host file is removed.
- The `x86_64-linux` filter TODO in `modules/universal/profile/remote-builders/default.nix:104`
  can be revisited now that a host builds x86_64 locally.
