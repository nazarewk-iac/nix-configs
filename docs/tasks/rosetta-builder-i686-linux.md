---
type: Task
description: Let the Rosetta darwin builder build i686-linux derivations (e.g. the brgenml1lpr Brother printer driver) so a cross-arch NixOS sanity check from the aarch64-darwin host is complete.
status: todo
authored_by: agent
timestamp: 2026-08-07T00:00:00+02:00
---

# Rosetta builder — build i686-linux derivations

The Rosetta darwin builder ([multi-arch-rosetta-builder.done.md](multi-arch-rosetta-builder.done.md),
`modules/slots/rosetta-builder/default.nix`) builds `aarch64-linux` and `x86_64-linux`. It cannot
build `i686-linux`. So a `nom build` of a NixOS `toplevel` from the aarch64-darwin host fails on
any 32-bit derivation.

## Trigger

A build of `brys`/`oams` `toplevel` from the darwin host fails on one derivation:

```
error: a 'i686-linux' with features {} is required to build
'…-brgenml1lpr-3.1.0-1.drv', but I am a 'aarch64-darwin' …
```

`brgenml1lpr` is a 32-bit Brother printer driver from `services.printing.drivers`
(`modules/universal/services/printing/default.nix`). Both hosts set
`kdn.services.printing.enable = true`. This is NOT a flake-update regression. Native
`x86_64-linux` hosts advertise `i686-linux` automatically, so the driver builds on the real
brys/oams. The darwin/Rosetta check cannot cover it.

## Why the simple fix does not work

Rosetta for Linux is **x86_64-only**. Its binfmt handler registers only for the x86_64/amd64 ELF
magic. The aarch64 guest kernel cannot run 32-bit x86 natively. So adding `i686-linux` to
`nix.buildMachines[].systems` only moves the failure from schedule time to build time — the VM
cannot execute i686 build tools.

## Directions to investigate

1. **qemu-user (TCG) binfmt inside the VM image.** Add `boot.binfmt.emulatedSystems = [
   "i686-linux" ]` (or the i686 handler) to the rosetta VM's NixOS image, through
   `nix-rosetta-builder`'s `potentiallyInsecureExtraNixosModule` or an upstream option. Then
   advertise `i686-linux` in `buildMachines.systems`. Slow (TCG emulation), but correct.
2. **Accept the gap.** Keep the darwin sanity check as "eval + all buildable derivations", and
   build the i686 driver only on the real x86_64-linux hosts. Document the known gap.
3. **Split the sanity check.** Filter i686 derivations out of the darwin build set, so the check
   reports a clean pass with a noted exclusion.

## Notes

- Upstream module hardcodes `buildMachines[].systems = [ linuxSystem "x86_64-linux" ]` as a list
  literal, so you cannot override just that field. Append a second `buildMachines` entry for the
  same host (`rosetta-builder`, user `builder`, ssh-ng) to add systems.
- Full context: `.macos-build-report.md` (non-committable) in the repo root at the time of this
  task.
