---
type: Solution
description: The fork option `nix-rosetta-builder.workingDir` plus the slot pass-through put the guest on /anji-ext-01 before the first boot, so no guest was destroyed. TCC asked for no new grant.
timestamp: 2026-10-11T16:45:00+02:00
authored_by: agent
---

# Solution

## What shipped

- The fork `nazarewk/nix-rosetta-builder` adds `nix-rosetta-builder.workingDir`
  (default `/var/lib/${name}`); `flake.nix` consumes the fork.
- `modules/slots/rosetta-builder/default.nix` exposes `guest.workingDir` and passes it through.
- `hosts/anji/default.nix` sets `kdn.darwin.rosetta-builder.guest.workingDir =
  "/anji-ext-01/rosetta-builder"`.

The host had no Rosetta guest yet (the bootstrap was at phase 1), so the move was free: the guest
was **created** on the external volume during the phase-2 switch of
[rosetta-builder-bootstrap](../rosetta-builder-bootstrap/done.md) on 2026-10-11, and the
"regenerate `lima.yaml` destroys the guest" risk never applied.

## The open questions, answered by the run

- **TCC/Full Disk Access:** no new grant was needed. `org.nixos.rosetta-builderd` runs from
  `/anji-ext-01` with the grants the `linux-builder` daemon already carried on the same volume —
  the responsible-process grant covers the shared nix bash path.
- **Boot ordering:** the unlock `preActivation` + launchd re-run covers this volume; the
  `linux-builder` daemon already lived there for a month without an ordering failure. A dedicated
  reboot test of `rosetta-builderd` specifically is still not measured.
- **Fork shape:** the thin fork (one commit, `feat: add workingDir option`) tracked upstream `main`
  with a merge of the recent upstream PRs. Upstreaming is still possible later; the fork is cheap.
