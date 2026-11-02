---
type: Task
description: Give every ZFS host a declarative, memory-relative ZFS ARC cap (default 8 GiB or 25% of RAM, whichever is lower), replacing the ad-hoc per-host kernelParam that only brys and now oams carry.
status: open
authored_by: agent
timestamp: 2026-11-02T19:40:29+01:00
---

# Cap the ZFS ARC on every ZFS host

## Context

The ZFS ARC grows to about half of RAM by default. On a box with a lot of RAM that is
fine; on a box that also runs interactive work it is not. Measured on `oams` (62 GiB, no
swap) on 2026-11-02: the ARC held **25.2 GiB**, `free` reported 41 GiB used while the RSS of
all processes was only ~12 GiB. The same failure had already been fixed on `brys` by a hard
`zfs.zfs_arc_max=8589934592` kernelParam in `hosts/brys/llm-tuning-shared.nix`, and on
`oams` by the same line added on 2026-11-02 (`hosts/oams/default.nix`).

Two hosts with a hand-written kernelParam is a drift hazard: every new ZFS host must
remember the line, and a low-RAM host needs a different number than a 126 GiB box.

## The hosts that run ZFS (from the configs, 2026-11-02)

A host runs ZFS when it enables `kdn.disks.enable` (the disko layout writes a ZFS pool) or
`kdn.fs.disko.luks-zfs.enable` (ZFS on LUKS). Verified by reading each `hosts/<h>/default.nix`:

| host  | enables                         | RAM (MemTotal)                          | has arc cap today |
| ----- | ------------------------------- | --------------------------------------- | ----------------- |
| brys  | `kdn.disks.enable` (ZFS pool)   | 131 806 148 kB ≈ 126 GiB                | yes, 8 GiB (hard) |
| oams  | `kdn.fs.disko.luks-zfs.enable`  | 65 229 184 kB ≈ 62 GiB                  | yes, 8 GiB (hard) |
| etra  | `kdn.disks.enable`              | 32 611 624 kB ≈ 31 GiB                  | no                |
| briv  | `kdn.disks.enable`              | 7 957 152 kB ≈ 7.6 GiB                  | no                |
| pryll | `kdn.disks.enable`              | 8 017 664 kB ≈ 7.6 GiB                  | no                |
| pwet  | `kdn.disks.zpools` + `luks-zfs` | not reachable now; Intel, low-RAM class | no                |
| turo  | `kdn.disks.zpools` + `luks-zfs` | not reachable now; Intel, low-RAM class | no                |
| yost  | `kdn.disks.zpools` + `luks-zfs` | not reachable now; Intel, low-RAM class | no                |
| obler | `kdn.fs.disko.luks-zfs.enable`  | not reachable now                       | no                |

Hosts that do **not** run ZFS and need no change: `anji` (darwin), `gaz`, `moss`, `orr`,
`kdn-rpi4-bootstrap` (no `kdn.disks`/luks-zfs), and `install-iso`.

**The unreachable hosts (`pwet`, `turo`, `yost`, `obler`) must be measured** before their
value is final. They are Intel mini-PC class; if 25% of RAM is below 8 GiB the cap is 25%.

## Goal

One declarative option expresses the cap for every host, so no host repeats the line and a
low-RAM host automatically gets a smaller cap than a large one:

```nix
kdn.fs.zfs.arcMaxPercent = 25;   # default: min(25% of RAM, 8 GiB)
# or a fixed override when a host needs an exact number:
kdn.fs.zfs.arcMaxBytes = 8 * 1024 * 1024 * 1024;
```

The option computes `zfs.zfs_arc_max` as `min(percent * MemTotal, maxBytesDefault)` in
bytes and writes it into `boot.kernelParams` (or `boot.extraModprobeConfig`, which applies
without a reboot only on module load). The value must be visible in the evaluated config,
so a later reader sees the exact number, not a computation.

Nix cannot read live `MemTotal` at build time without impurity. The honest inputs are:
the host's declared RAM (a small `kdn.hw.memory` option, or a per-host literal), or a
fixed bytes value. The task must pick one and say why — do not guess from a shell command
in a build.

## Scope

- A shared option + default in `modules/den/aspects/fs.nix` (or the `zfs` aspect), consumed
  by every ZFS host.
- Remove the two ad-hoc kernelParams (`hosts/brys/llm-tuning-shared.nix`,
  `hosts/oams/default.nix`) and set the option there (8 GiB on both, since both are > 32 GiB).
- Set `25%` (or the computed value) on `etra`, `briv`, `pryll`, `pwet`, `turo`, `yost`,
  `obler`.
- `briv` and `pryll` are ~8 GiB: 25% is ~2 GiB. Confirm 2 GiB is enough for a usable ARC, or
  set a floor (e.g. never below 1 GiB) in the option.

## Acceptance

- Every ZFS host renders a `zfs.zfs_arc_max` in its evaluated `boot.kernelParams`
  (or modprobe config), and the value is `min(25% RAM, 8 GiB)` unless overridden.
- The two ad-hoc kernelParams are gone; `rg 'zfs_arc_max'` shows only the option and its
  per-host values.
- `nix eval` on each ZFS host shows the exact computed number next to the host in this
  task's table.
- No low-RAM host is given a cap that starves ordinary file I/O (a floor is justified).

## Open questions

- Measured `MemTotal` for `pwet`, `turo`, `yost`, `obler`.
- Is 25% right for a 126 GiB host? `brys` uses a flat 8 GiB by measurement; 25% would be
  31 GiB. The task should keep 8 GiB as the ceiling so a big box does not hand the ARC more
  than measured-safe.
