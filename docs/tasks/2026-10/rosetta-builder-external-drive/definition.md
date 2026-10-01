---
type: Task
description: Move the Rosetta builder guest disk from the internal disk of host `anji` to an external drive by patching the upstream module in a fork.
status: open
authored_by: agent
timestamp: 2026-10-01T17:38:07+02:00
---

# Move the Rosetta builder guest disk to an external drive on `anji`

## Context

- Host `anji` is an Apple Silicon Mac mini M2. It has a 256 GB internal disk. It runs
  nix-darwin and Lix 2.95.x.
- The Rosetta builder comes from the flake input `nix-rosetta-builder`. The input URL is
  `github:cpick/nix-rosetta-builder`.
- The option `kdn.darwin.rosetta-builder` enables the builder. The slot is
  `modules/slots/rosetta-builder/default.nix`.
- Upstream hardcodes the guest working directory to `/var/lib/rosetta-builder` (upstream
  `module.nix:190`, `workingDirPath = "/var/lib/${name}"`). No option moves it.
- The guest disk is a sparse file. Upstream defaults to `100GiB`. This repo caps it with
  `kdn.darwin.rosetta-builder.guest.diskSizeMax` = `150GiB`.
- The working directory is on the internal disk. So the sparse guest competes with the OS
  for the 256 GB internal disk.
- Two external encrypted APFS volumes exist: `anji-ext-01` (2 TB, mounted `/anji-ext-01`)
  and `anji-ext-02` (2 TB, mounted `/anji-ext-02`). Both unlock at boot. A `preActivation`
  block and a launchd daemon do the unlock (see `hosts/anji/default.nix` and
  `hosts/anji/disks.md`).
- The stock `nix.linux-builder` already uses `/anji-ext-01/linux-builder` on the external
  volume. That path needs Full Disk Access (TCC) for the bash binary of the daemon (see
  `docs/darwin-quirks.md`).
- The Rosetta builder does not need this grant today. It lives on the internal disk. An
  external location reintroduces the TCC/FDA requirement.

## Problem

Upstream gives no option to change the guest working directory. The guest sparse file
therefore grows on the internal disk. The internal disk is small (256 GB). The guest can
fill it and starve the OS.

## Proposed approach

- The user forked `cpick/nix-rosetta-builder` to `nazarewk/nix-rosetta-builder`. The fork
  is a GitHub web fork with the `main` branch only.
- The local checkout is at `~/dev/github.com/cpick/nix-rosetta-builder`. It is colocated
  jj+git. The remotes are `origin` = `cpick/nix-rosetta-builder` (upstream) and `nazarewk`
  = `nazarewk/nix-rosetta-builder` (the fork). The primary branch is `main`.
- Add an option to the fork module, for example `nix-rosetta-builder.workingDir`. Its
  default is `/var/lib/${name}` for backward compatibility.
- Set the option on `anji` to a path on `/anji-ext-01`, for example
  `/anji-ext-01/rosetta-builder`.
- Update `modules/slots/rosetta-builder/default.nix` (or the host) to pass the option.
- Change the flake input in `flake.nix` (line ~64) from `github:cpick/nix-rosetta-builder`
  to `github:nazarewk/nix-rosetta-builder`. Update `flake.lock`.
- The fork `main` branch carries the patch. The `nix-configs` flake consumes the fork.
- Rebase the fork on new upstream commits to stay in sync.

## Risks and open questions

- TCC/Full Disk Access: the Rosetta guest runs through `limactl`/`qemu`. Which binary
  needs the grant? Does it change on each nixpkgs bump? See `docs/darwin-quirks.md`.
- Boot ordering: the external volume must be mounted before the Rosetta daemon starts. The
  `preActivation` unlock already runs first. The launchd daemon order needs a check.
- Lima regenerates `lima.yaml` on a working-dir change. The upstream module deletes and
  recreates the guest on a `lima.yaml` change (upstream `module.nix:336-360`). So the move
  destroys the current guest and its cached store. This is acceptable once, on purpose.
- Fork maintenance: how to track upstream `cpick/nix-rosetta-builder` changes.
- Should the fork be a full fork or a thin patch?

## Related docs

- [docs/multi-arch-builder.md](../../../multi-arch-builder.md) — the bootstrap procedure
  and the single-authoritative-store invariant.
- [docs/darwin-quirks.md](../../../darwin-quirks.md) — TCC/FDA on external volumes.
- [hosts/anji/disks.md](../../../../hosts/anji/disks.md) — the external volumes and the
  unlock.
- [docs/guides/git-forking.md](../../../guides/git-forking.md) — how the fork was created.
- The fork checkout: `~/dev/github.com/cpick/nix-rosetta-builder`.
