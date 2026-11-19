---
type: Task
description: Move `gaz` from the `hosts/` Crostini VM to `hosts-den/` as a real NixOS workstation with the repository's ZFS impermanence layout, then install it on the hardware.
status: open
authored_by: agent
timestamp: 2026-10-27T19:40:00+01:00
---

# `gaz` from Crostini container to den workstation

Part of [../definition.md](../definition.md).

## Current state

`hosts/gaz/default.nix` builds a Crostini VM: `nixos-crostini`'s `baguette`
module, a 20 GB disk image, the baseline machine profile, desktop off, no disk
layout, no aspects, and no SSH host keys. See
[../research.md](../research.md#1-the-current-gaz).

## Target state

A directory `hosts-den/gaz/default.nix`, modelled on `hosts-den/orr` for the den
shape and on `hosts/brys` for the machine shape:

```nix
{ kdn, ... }:
{
  den.hosts.x86_64-linux.gaz.class = "nixos";

  den.aspects.gaz.includes = [
    kdn."hw-chromebook-c13-yoga"   # new, or an existing laptop aspect
    kdn.disks
    kdn.fs-zfs
    kdn.profile-workstation
    kdn.secrets
    kdn.nix-config
    # ... see the list in hosts/brys/default.nix
  ];

  den.aspects.gaz.nixos = {
    networking.hostName = "gaz";
    networking.hostId = "<8 hex chars>";   # ZFS requires it, and it must be unique
    system.stateVersion = "26.05";
    zramSwap.enable = true;
    zramSwap.memoryPercent = 50;
  };
}
```

The disk block follows `kdn.disks` with a device description, not hand-written
`fileSystems`:

- an ESP on the internal disk,
- a LUKS volume with a detached header for the pool,
- a ZFS pool with a root dataset,
- tmpfs `/`, `preservation` for the kept paths.

Include `disks` **or** `fs-luks-zfs`, never both; `disks` needs `fs-zfs` beside
it.

## Ordered steps

1. **Recon.** Read `modules/den/aspects/disks.nix`, `fs.nix`,
   `profile-workstation.nix`, `hw-dell-e5470.nix`, and `hosts/brys/default.nix`.
   Produce the aspect list for `gaz` and the exact device description. Commit
   it as a plan.
2. **Skeleton.** `hosts-den/gaz/default.nix` that evaluates: tmpfs `/`, GRUB
   off, no devices yet. Gate:
   `nix eval '.#denConfigurations.gaz.config.system.build.toplevel.drvPath'`.
3. **Hardware.** Identify the model. Add a `hw-chromebook-*` aspect (kernel
   modules, `nixos-hardware` entry, keyboard, zram). Capture `dmidecode`,
   `lsblk`, `lspci` from the live machine.
4. **Disk.** Write the real device description. Prove it by evaluating and by
   building the installer.
5. **Boot.** MrChromebox UEFI, USB installer, install, first boot. Every physical
   step follows the hand-off protocol in
   [../design.md](../design.md#6-the-physical-hand-off-protocol).
6. **Parity.** Turn the workstation aspects on until the desktop is usable, then
   delete `hosts/gaz/` in its own commit.

## Hard constraints

- A den host **is** wired into `nixosConfigurations`, so `nixos-rebuild`, `nh` and the build farm
  find it. `flake.hosts` stays old-tree-only: two k8s modules look up `kdn.networking.*` there by
  name and a den host declares none of those options.
- `networking.hostId` must be unique and must be recorded. ZFS will not import
  without it.
- Do not copy `brys`'s device paths or `hostId`.
- Do not keep the Crostini module in the new host. It is a different machine
  model.

## Acceptance

- `denConfigurations.gaz` evaluates.
- The machine boots NixOS from the internal disk with no ChromeOS.
- `/` is tmpfs; the persistent paths survive a reboot.
- `hosts/gaz/` is deleted, and no other host references it.
