---
type: Task
description: Decide whether host brys can run a Linux 7.x kernel while it keeps its ZFS root, its LUKS unlock, its TPM-backed sops identity and an unattended boot.
status: open
authored_by: agent
timestamp: 2026-11-19T05:30:00+01:00
---

# A Linux 7.x kernel on brys, with ZFS intact

## Question

Can `brys` move from Linux 6.18.62 to a 7.x kernel and still boot its ZFS root without a
console? The answer depends on three independent limits:

1. which 7.x kernels nixpkgs carries,
2. which kernels OpenZFS supports,
3. how the host's boot path reacts to a kernel change.

The short answer is **no, not today**: the two sides do not overlap in nixpkgs. The only 7.x kernel
there is 7.3, and no released OpenZFS supports 7.3. The rest of this document gives the evidence,
the coupling, the risk list, and a VM-first plan for the day the two sides do agree.

Related tasks: `docs/tasks/2026-11/rocm-on-brys/` (the separate ROCm/`hsa_init` diagnosis — read
it, do not edit it from here), [brys-r9700-model-fit](../brys-r9700-model-fit/definition.md) (what
the GPU serves today), [zfs-arc-cap](../zfs-arc-cap/definition.md) (the ARC cap this host still
needs on any kernel).

## Today's state (measured, not assumed)

| Fact             | Value                                                                    | Source                                                                                                                           |
| ---------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| nixpkgs          | `26.11.20261106.296d5fa`, rev `296d5fa316d8aa9596fa37a0aca699dcf1809377` | `flake.lock`, `nix flake metadata`                                                                                               |
| brys kernel      | **6.18.62**                                                              | `nix eval --raw .#denConfigurations.brys.config.boot.kernelPackages.kernel.version`                                              |
| brys ZFS package | **2.4.4**                                                                | `nix eval --raw .#denConfigurations.brys.config.boot.zfs.package.version`                                                        |
| nixpkgs ROCm     | `rocmPackages.clr` **7.2.4**                                             | `nix eval --raw <nixpkgs>#rocmPackages.clr.version`                                                                              |
| Root             | tmpfs + impermanence, ZFS datasets under `brys-main/`                    | [`hosts-den/brys/default.nix`](../../../../hosts-den/brys/default.nix), [`disks.nix`](../../../../modules/den/aspects/disks.nix) |
| Unlock           | two LUKS volumes (`vp4300-brys`, `px700-brys`) → zpool import in initrd  | `hosts-den/brys/default.nix` lines 687–697, `disks.nix` lines 1199–1205                                                          |
| Secrets          | TPM age identity at `/var/lib/sops-tpm/tpm-identity.txt`, 30 s wait      | `hosts-den/brys/default.nix` lines 721–727                                                                                       |

The boot path is the constraint that makes this task expensive. The brys README records a
motherboard or PSU fault: after any power-off the machine can stay dark until the mains lead is
pulled for 20–60 minutes, and a warm `reboot` can land in the same fault
([`hosts-den/brys/README.md`](../../../../hosts-den/brys/README.md)). A kernel that does not boot
costs a NanoKVM session, a power cycle, and sometimes an hour of downtime.

## 1. Which Linux versions exist

Pinned nixpkgs and current `nixpkgs-unstable` (`f4a03c008967841f2a0b3cb7c436fc6fc31671f6`) give
the same answer:

| Attribute                                   | Version     | Note                                                                |
| ------------------------------------------- | ----------- | ------------------------------------------------------------------- |
| `linux` = `linux_default` = `linuxPackages` | **6.18.62** | what brys runs                                                      |
| `linux_6_12`                                | present     | other supported LTS branch                                          |
| `linux_latest` = `linux_7_3`                | **7.3.3**   | the **only** 7.x in the tree                                        |
| `linux_testing`                             | 7.4-rc1     | release candidate                                                   |
| `linux_7_0`, `linux_7_1`, `linux_7_2`       | **removed** | `throw "… removed because it has reached its end of life upstream"` |

Source: `pkgs/top-level/linux-kernels.nix` in the pinned nixpkgs (`linux_default =
packages.linux_6_18` at line 699, `linux_latest = packages.linux_7_3` at line 701, the `throw`
entries at lines 646–648 of the same file, and the identical file in nixpkgs-unstable).

Consequence: a 7.x attempt on nixpkgs must use **7.3**. There is no 7.0, 7.1 or 7.2 to fall back
to, in either tree.

Commands:

```sh
nix eval --raw nixpkgs#linux.version          # 6.18.62
nix eval --raw nixpkgs#linux_latest.version   # 7.3.3
nix eval --raw 'github:NixOS/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6#zfs.version'  # 2.4.4
```

## 2. OpenZFS support matrix

Each OpenZFS tag declares its range in `META`. The release notes repeat it.

| OpenZFS           | Linux minimum | Linux maximum | State             | Source                 |
| ----------------- | ------------- | ------------- | ----------------- | ---------------------- |
| 2.2.11            | 4.18          | 6.17          | released          | release notes          |
| 2.3.8             | 4.18          | 7.0           | released          | release notes          |
| 2.4.3             | 4.18          | 7.0           | released          | release notes          |
| **2.3.9**         | 4.18          | **7.2**       | released          | `META` + release notes |
| **2.4.4**         | 4.18          | **7.2**       | released (latest) | `META` + release notes |
| master (`2.4.99`) | 4.18          | **7.3**       | **unreleased**    | `master/META`          |

- 2.4.4 `META`:
  `https://raw.githubusercontent.com/openzfs/zfs/zfs-2.4.4/META` → `Linux-Maximum: 7.2`.
- 2.3.9 `META` says the same (`Linux-Maximum: 7.2`).
- master `META`: `https://raw.githubusercontent.com/openzfs/zfs/master/META` →
  `Version: 2.4.99`, `Linux-Maximum: 7.3`. No tag carries this yet.
- The 2.4.3 and 2.3.8 release notes state `compatible with 4.18 - 7.0 kernels`; the 2.2.11
  notes state `4.18 - 6.17`.

So the newest **released** OpenZFS supports **7.2**, and nixpkgs carries only **7.3**.

Which nixpkgs attribute carries what:

| Attribute            | Version | `kernelMinSupportedMajorMinor` | `kernelMaxSupportedMajorMinor`                                 |
| -------------------- | ------- | ------------------------------ | -------------------------------------------------------------- |
| `zfs` = `zfs_2_4`    | 2.4.4   | 4.18                           | 7.2                                                            |
| `zfs_unstable`       | 2.4.4   | 4.18                           | 7.2                                                            |
| `zfs_2_3`            | 2.3.9   | 4.18                           | 7.2                                                            |
| `zfs_2_1`, `zfs_2_2` | —       | —                              | removed (`throw`)                                              |
| `linuxPackages.zfs`  | —       | —                              | removed; use `linuxPackages.${pkgs.zfs.kernelModuleAttribute}` |
| `zfs_canmount`       | —       | —                              | not an attribute in this nixpkgs                               |

Source: `pkgs/os-specific/linux/zfs/{2_3,2_4,unstable}.nix` and `pkgs/top-level/all-packages.nix`
(`zfs = zfs_2_4`, line 7746).

`zfs_unstable` gives nothing here: it is the same 2.4.4 with the same 7.2 maximum. `zfs_2_3` is
older and has the same maximum. **No ZFS package in nixpkgs supports 7.3.**

### The guard refuses at evaluation

`pkgs/os-specific/linux/zfs/generic.nix` computes:

```nix
kernelIsCompatible = kernel:
  (lib.versionAtLeast kernel.version kernelMinSupportedMajorMinor)
  && (lib.versionAtLeast kernelMaxSupportedMajorMinor (lib.versions.majorMinor kernel.version));
...
broken = buildKernel && !((kernelIsCompatible kernel) || enableUnsupportedExperimentalKernel);
```

Measured flags:

```sh
N=/nix/store/lk98r48k05nwda8yh4fzyd9bn6l5z02m-source   # the pinned nixpkgs
nix eval "$N#linuxPackages_6_18.zfs_2_4.meta.broken"   # false
nix eval "$N#linuxPackages_7_3.zfs_2_4.meta.broken"    # true
nix eval "$N#linuxPackages_7_3.zfs_unstable.meta.broken" # true
nix eval "$N#linuxPackages_7_3.zfs_2_3.meta.broken"    # true
```

A build of that pair stops before it compiles anything:

```
error: Refusing to evaluate package 'zfs-kernel-2.4.4-7.3.3' in .../pkgs/os-specific/linux/zfs/generic.nix:361
because it has problems:
- broken: This package is broken.

To allow evaluation regardless, use:
  { problems.handlers = { zfs.broken = "warn"; }; }
```

This is the one cheap failure mode in the whole exercise: the mismatch fails at evaluation, not
at boot. A `problems.handlers.zfs.broken = "warn"` removes that protection and moves the failure
to a compile error or, worse, to a module that loads and panics. Note that brys pins
`nixpkgs.pkgs` and forces `nixpkgs.config = lib.mkForce { }`
([`hosts-den/brys/default.nix`](../../../../hosts-den/brys/default.nix) lines 667–671), so such a
handler cannot be set through `nixpkgs.config` on this host at all; it would go into the pkgs
instance.

### Disabling the guard does not add support

`enableUnsupportedExperimentalKernel` adds one configure flag (`--enable-linux-experimental`) and
silences `meta.broken`. It adds **no** kernel-API compatibility code. Two extra obstacles for a
local override:

- The flag and the version fields are **inner** arguments of `generic.nix`. `zfs_2_4.override`
  reaches only the outer argument set, so the flag cannot be set with a plain `.override`.
- `generic.nix` `postPatch` greps `META` and fails the build when the declared
  `kernelMaxSupportedMajorMinor` does not match the source:

  ```
  echo 'Checking kernelMaxSupportedMajorMinor is correct...'
  grep --quiet '^Linux-Maximum: *<max>$' META
  ```

  A source swap to OpenZFS master therefore fails unless the declared maximum moves to `7.3` in
  the same override. Any experiment must re-instantiate `generic.nix` with **both** the source and
  the maximum, in a throwaway expression under `.cache/agent-notes/`.

## 3. The NixOS coupling

`boot.zfs.package` does not select the kernel modules. It selects the **userspace tools** and
**names the kernel-module attribute**:

```nix
# nixos/modules/tasks/filesystems/zfs.nix, pinned nixpkgs
selectModulePackage = package: config.boot.kernelPackages.${package.kernelModuleAttribute};
...
boot.zfs.package       = mkOption { default = pkgs.zfs; ... };              # userspace
boot.zfs.modulePackage = mkOption { default = selectModulePackage cfgZfs.package; ... };  # kernel module
```

`boot.kernelPackages` defaults to `pkgs.linuxPackages`
(`nixos/modules/system/boot/kernel.nix` lines 69–85). So:

```
boot.kernelPackages              → kernel 6.18.62 + a package set that holds zfs_2_4
boot.zfs.package (2.4.4)         → userspace tools AND the name "zfs_2_4"
boot.zfs.modulePackage           → config.boot.kernelPackages.zfs_2_4   ← built against the kernel
```

Two consequences:

- **Userspace and module cannot skew by version** through these two options. Both come from the
  same nixpkgs attribute, so `zfs` and `zfs_2_4` are one 2.4.4 release. There is no mixed-version
  trap here.
- **The kernel and the module can skew.** That is exactly the 7.3 case, and `meta.broken` catches
  it. Moving the kernel alone gives the error above; moving `boot.zfs.package` alone changes both
  halves together.

### The repository moves the kernel itself

`brys` does not use the NixOS default. The `kdn.fs-zfs` aspect picks the kernel from a two-entry
table and pins it:

```nix
# modules/den/aspects/fs.nix
kernelPackage = lib.pipe [
  { name = "2.3.1+";  check = atLeastZFSVersion "2.3.1";
    pkg = pkgs.linuxKernel.packages.linux_6_18 or null; }
  { name = "default"; check = true;
    pkg = pkgs.linuxKernel.packages.linux_6_6; }
] [ ... ];
...
boot.kernelPackages = lib.mkOverride 1200 kernelPackage;
boot.zfs.package    = cfg.package;                       # default: pkgs.zfs_unstable
```

The table has **no 7.x entry**, and the aspect writes `boot.kernelPackages` at priority 1200, so a
host-level `lib.mkDefault` loses. A 7.x attempt on this repository therefore needs a change to
[`modules/den/aspects/fs.nix`](../../../../modules/den/aspects/fs.nix) (a kernel-table entry) or a
stronger host override. Both are outside this task; this task only decides whether such a change
is worth making.

## What a newer kernel buys

### amdgpu / KFD for gfx1201 and `hsa_init`

The owner's hypothesis: kernel 6.18.62 may be too old for ROCm 7.2.4 on gfx1201, and a 7.x kernel
could unblock ROCm/HIP. The evidence does not support "too old":

- **AMD supports the R9700 (gfx1201), but only on four OS releases, whose kernels stop at 6.17.**
  The ROCm 7.2.3 system requirements list the Radeon AI PRO R9700 as supported, and footnote 7
  limits the Radeon PRO and Radeon cards to Ubuntu 24.04.4 (6.8 GA, 6.17 HWE), Ubuntu 22.04.5
  (5.15 GA, 6.8 HWE), RHEL 10.1 (6.12) and RHEL 9.7 (5.14). The kernels in that supported set are
  5.14, 5.15, 6.8, 6.12 and 6.17. `6.18.62` is **above** the newest of them, not below the oldest.
  <https://rocm.docs.amd.com/projects/install-on-linux/en/docs-7.2.3/reference/system-requirements.html>
- **The card already works at 6.18.62.** The R9700 ran all downloaded models over llama.cpp
  Vulkan on this kernel ([`brys-r9700-model-fit/measurements.md`](../brys-r9700-model-fit/measurements.md)).
  That proves amdgpu binds the device and drives it. A missing DRM enablement is not the problem.
- **gfx1201 is new on the ROCm side, not on the kernel side.** One RDNA4 field report states that
  gfx1201 entered the official ROCm support matrix in 7.2 (January 2026), and that no earlier
  matrix listed it. The ROCm 7.2.3 matrix above confirms it is supported now. The newer half of
  this pair is the ROCm build.
  <https://github.com/LukeLamb/rdna4-ready/blob/main/FIXES.md>
- **`hsa_init` needs `/dev/kfd`, a KFD-capable amdgpu, and a matching userspace.** Reports of
  `hsa_init Failed, possibly no supported GPU devices` trace to a missing `/dev/kfd` or a
  container/runtime path problem, not to a kernel that is too old.
  <https://github.com/unslothai/unsloth/issues/9729>
- **6.18 is a known-regression kernel for RDNA4 under mixed load.** The amdgpu tracker has
  "[Regression] RDNA4 hangs/resets when running 3d workloads while having Ollama run in
  background on linux 6.18" (<https://gitlab.freedesktop.org/drm/amd/-/issues/4765>), and AMD sent
  `amdkfd` fixes for 6.18 (`kfd_queue.c`, `kfd_svm.c`,
  <https://kernelthread.org/t/20251112200930.8788-1-alexander.deucher@amd.com>). This is an argument
  for a **newer stable 6.x**, not for 7.3.
- **The 7.x amdgpu work reported so far is display, power and reset work.** Linux 7.2 merges the
  AMDGPU "power module", a "RDNA 4 fix", and runtime-PM cleanup
  (<https://phoronix.com/news/Linux-7.2-AMDGPU-Power-Mod>,
  <https://phoronix.com/news/Linux-7.2-More-AMDGPU-Fixes>). No listed item names KFD bring-up or
  `hsa_init`.
- **7.x is not risk-free on this card class.** A Fedora report says kernel 7.2 breaks certain AMD
  GPU support (<https://discussion.fedoraproject.org/t/warning-new-kernel-7-2-breaks-certain-amd-gpu-support/195477>).
  Treat it as a user report, not a matrix.

**Is a kernel bump the cheapest test of the ROCm hypothesis? No.** It is the most expensive one,
for three reasons:

1. It cannot be tested on `brys` itself, because the same kernel must carry the ZFS root
   (section 2). Any real test needs a VM or a spare disk with a non-ZFS root.
2. The cheap discriminators come first: `ls -l /dev/kfd`, group membership (`render`, `video`),
   `rocminfo`, `dmesg | grep -iE 'kfd|amdgpu'`, `lspci -k -d 1002:`, and `cat /proc/cmdline` for
   `iommu=pt`. One of these usually explains a failed `hsa_init` in minutes.
3. The kernel is not the part that is new. ROCm 7.2.x on gfx1201 is.

The ROCm track owns that diagnosis. This document only records the ordering: **ROCm checks first,
kernel second, and never on `brys` without the VM evidence below.**

### ZFS

A newer kernel buys brys **nothing** on ZFS. OpenZFS 2.4.4 is the newest release and its maximum
is 7.2. The 6.18 branch that brys runs is inside the supported range and receives the ZFS fixes
that matter (2.4.4 carries explicit `Linux 6.18 compat: vfs_parse_fs_string() takes 3 args`, from
the 2.4.4 release notes). The direction of the dependency is the problem: ZFS limits the kernel,
so a kernel bump is a **ZFS** project first.

### Everything else

| Candidate benefit                                                       | Honest value for brys                                                                                                           | Source                                                 |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Cache-aware scheduling (7.2)                                            | Plausible for the CPU-bound MoE decode path, which is memory-bandwidth bound and thread-sensitive. **Unmeasured** on this host. | <https://phoronix.com/news/Linux-7.2-Best-Features>    |
| Navi 48 / RDNA4 power management (7.2 power module, runtime-PM cleanup) | Power and display behaviour of the R9700. The RX 550 drives the displays, so the R9700 does compute only. Small.                | <https://phoronix.com/news/Linux-7.2-AMDGPU-Power-Mod> |
| io_uring                                                                | No workload on this host is known to depend on it.                                                                              | —                                                      |
| Filesystem and memory-management changes                                | Not useful here: the root is tmpfs, with ZFS datasets on LUKS.                                                                  | —                                                      |

No item in this table justifies a boot-path risk on a host that needs a NanoKVM and sometimes an
AC disconnect to come back.

## Risk inventory for brys

Each item is a way a kernel change can stop the host. "Test" is the step in the plan that covers
it.

| #   | Risk                                                   | Why it matters here                                                                                                                                             | Test                                                   |
| --- | ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| 1   | ZFS module does not build or does not load             | root is ZFS; no module means no `/nix`, no `/persist`                                                                                                           | P1 (eval), P2 (VM boot)                                |
| 2   | Kernel panics in initrd before LUKS unlock             | no console except NanoKVM; the host may need an AC disconnect                                                                                                   | P2, P3 (spare disk)                                    |
| 3   | `zfs-import` races the `cryptsetup` units              | import starts before the mapper exists → pool not found → emergency shell                                                                                       | P2 (mirror the `disks.nix` ordering)                   |
| 4   | LUKS2 header/argon2 or dm-crypt change                 | both volumes fail to open; clevis fallback also fails                                                                                                           | P2                                                     |
| 5   | TPM unseal stops working                               | the sops age identity does not unseal → no host keys, no sshd → mesh and SSH unreachable                                                                        | P2 (software identity), P3 (real TPM, read-only check) |
| 6   | Clevis JWE bound to PCRs that a new kernel re-measures | automatic unlock degrades to a passphrase prompt at a machine with no keyboard in reach                                                                         | P3 (`clevis luks list -d`)                             |
| 7   | TPM contention at boot                                 | two LUKS volumes unseal in the first seconds; the host waits 30 s                                                                                               | P2 (timing), P3                                        |
| 8   | initrd module set misses a NIC driver                  | `r8169`, `igb`, `mt7921e` are the only network paths; no network means no remote unlock                                                                         | P2                                                     |
| 9   | ARC cap lost                                           | `zfs.zfs_arc_max=8589934592` is a kernel parameter in `llm-tuning-shared.nix`; a new kernel config must keep it, or a 126 GiB host gives half of RAM to the ARC | P2 (`cat /proc/cmdline`, `arc_summary`)                |
| 10  | Rollback path unavailable                              | the boot device is a USB stick with `boot.loader.grub.copyKernels = true`; a broken generation must still be selectable                                         | P3 (inspect the menu, do not change it)                |
| 11  | Power fault after a failed boot                        | a power-off can latch the machine dark for 20–60 minutes                                                                                                        | P3 (schedule, have the mains lead reachable)           |
| 12  | `vfio-pci` / `iommu=pt` interaction                    | `softdep amdgpu pre: vfio-pci` and `iommu=pt` are on the cmdline; a kernel change can change probe order and KFD visibility                                     | P2, and the ROCm track                                 |

Items 5 and 6 cannot be fully proven in a VM: a QEMU `swtpm` starts empty, so the host's sealed
blobs cannot be imported into it. Only real hardware proves those. The plan must therefore keep a
fallback: the previous NixOS generation in the boot menu, the LUKS passphrase over the NanoKVM, and
the YubiKey as break-glass sops recipient (`kdn.hw.yubikey.requiredForBoot = false`).

## Experiment plan (VM first, host never)

Nothing in this plan changes `brys`, its bootloader, or any repository module. All scratch
expressions live in `.cache/agent-notes/`, which is git-ignored.

### P0 — Baseline, read-only, on brys

Record what a later comparison needs. Every command is read-only.

```sh
uname -r; cat /proc/cmdline
zpool status; zpool get version brys-main; zpool upgrade          # upgradeable features per pool
zfs --version; modinfo zfs | head -5
clevis luks list -d /dev/disk/by-id/nvme-…-00000001               # PCR set of each binding
tpm2_pcrread sha256:0,2,4,7,9 2>/dev/null | head
ls -l /dev/kfd; id; getent group render video
rocminfo | head -40                                               # feeds the ROCm track
```

The downgrade gate is the pool's feature flags: an older OpenZFS can refuse a pool that a newer
one upgraded. Record `zpool status` and `zpool get all brys-main` now, so the answer is on disk
before any package change.

### P1 — Static proof, no VM, no host

```sh
SYS=x86_64-linux
nix eval --raw ".#denConfigurations.brys.config.boot.kernelPackages.kernel.version"   # 6.18.62
nix eval "$N#linuxPackages_7_3.zfs_2_4.meta.broken"                                  # true
nix build --no-eval-cache -L ".#checks.$SYS.den-eval-hw"                             # 23.6 s
```

`den-eval-hw` evaluates the hardware aspects ([`checks/README.md`](../../../../checks/README.md)). A
kernel-table change that breaks an aspect fails here, before any build. A candidate host
expression with `boot.kernelPackages = pkgs.linuxKernel.packages.linux_7_3` must fail with the
`problems` error from section 2; if it does not, the guard was disabled by mistake.

### P2 — VM harness with the real boot shape

Build a throwaway NixOS VM that mirrors the boot chain but uses no real secret. Put it in
`.cache/agent-notes/zfs-kernel-vm/default.nix` and build it with
`nix build -f .cache/agent-notes/zfs-kernel-vm/default.nix vm -o result-vm` (or
`nixos-rebuild build-vm --flake` against a scratch flake). The VM must have:

- one virtio disk with two LUKS2 containers and a key file (no passphrase prompt in the test),
- a ZFS pool on the mapper, with the datasets `root`, `nix`, `persist`,
- `boot.initrd.supportedFilesystems = [ "zfs" ]`, `boot.zfs.forceImportRoot = false`,
  `boot.zfs.extraPools = [ "brys-main" ]` and the `disks.nix`-style ordering
  (`zfs-import-*` `requires`/`after` the `cryptsetup` units),
- a tmpfs root with one impermanence copy step, so the "root disappears" path is exercised,
- a **software** age identity in place of `/var/lib/sops-tpm/tpm-identity.txt`, and one sops
  secret behind it, so the ordering "unlock → import → decrypt → sshd" is visible,
- `virtualisation.tpm.enable = true` for an _optional_ second boot (a fresh swtpm; enrolment must
  happen inside the VM, so this proves the mechanism, not the host's blobs),
- the same `boot.kernelParams` (`nohibernate`, `zfs.zfs_arc_max=8589934592`, `iommu=pt`).

Run it twice, same expression, one variable:

| Run           | `boot.kernelPackages`                  | ZFS package                                                                                                                     | Expected result                      |
| ------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| A (control)   | `pkgs.linuxKernel.packages.linux_6_18` | `pkgs.zfs_unstable`                                                                                                             | boots, pool imports, secret decrypts |
| B (candidate) | `pkgs.linuxKernel.packages.linux_7_3`  | local `callPackage` of `generic.nix` with `version`/`rev`/`hash` from OpenZFS master and `kernelMaxSupportedMajorMinor = "7.3"` | boots, or fails visibly              |

Acceptance for run B: the VM reaches `multi-user.target`, `zpool status` is `ONLINE`,
`zfs get mounted` is correct, the sops secret file exists before `sshd.service` starts, and
`arc_summary`/`cat /sys/module/zfs/parameters/zfs_arc_max` shows the cap. A panic, a missing pool,
or a module that loads and then oopses is a **no**.

The upstream test is a partial substitute only: `nixosTests.zfs.series_2_4` covers pool create,
import, native encryption and `forcepool`, but it fixes `kernelPackages = pkgs.linuxPackages`
(`nixos/tests/zfs.nix` lines 211–224), so a 7.3 run needs a copied test file. It also has no LUKS
in initrd and no sops.

```sh
nix build --no-eval-cache -L "$N#nixosTests.zfs.series_2_4"   # needs KVM; proof of the 6.18 baseline
```

### P3 — Spare disk, then (and only then) hardware

1. Take one spare NVMe (or a large USB SSD) and repeat run B's closure on it. Do not touch the two
   LUKS volumes and do not touch the USB boot device.
2. Boot it with the NanoKVM attached and the mains lead reachable. Record a screenshot before and
   after.
3. Check, in this order: initrd unlocks both LUKS containers, `zpool import` finishes,
   `zfs-import-*` is `active (exited)`, the system reaches `multi-user.target`, `netbird-priv` and
   `sshd` are up, the sops secrets exist, `arc_summary` shows 8 GiB.
4. Prove the rollback: power off, select the previous generation from the boot menu, boot it. Do
   this **before** declaring the candidate good.

A warm `reboot` can land in the power fault. Prefer a clean `poweroff` and a NanoKVM reset pulse,
per the brys README.

### P4 — Decision gate

Move `brys` only when **all** of these hold:

- a tagged OpenZFS release declares `Linux-Maximum: 7.3` or higher (master already does; a tag
  does not),
- nixpkgs carries that ZFS release **and** the 7.x kernel in the same tree, with
  `meta.broken == false` for the pair,
- run B passes in the VM twice in a row,
- the spare-disk boot passes, including the rollback,
- the ROCm track agrees that the kernel is the remaining variable (section "What a newer kernel
  buys" says it probably is not).

## Recommendation

**Do not move brys to a 7.x kernel now.**

- No released OpenZFS supports 7.3 (2.4.4 and 2.3.9 stop at 7.2), and 7.3.3 is the only 7.x kernel
  in nixpkgs. The two sides do not overlap, in the pinned tree or in current `nixpkgs-unstable`.
- 7.0, 7.1 and 7.2 are gone from nixpkgs, so the supported range (≤ 7.2) is unreachable there. A
  hand-built 7.2 kernel would be an unmaintained kernel with a known end of life.
- The benefit is small and mostly unmeasured: ZFS gains nothing, gfx1201 compute is not a 7.x
  feature, and the plausible wins (cache-aware scheduling, RDNA4 power management) have no number
  on this host.
- The risk is not small: ZFS root, two LUKS volumes, a TPM identity, a 30 s contention window, and
  a machine that can stay dark for an hour after a failed power cycle.

**Do this instead, in order:**

1. Run the ROCm discriminators in P0 with the `rocm-on-brys` track. A missing `/dev/kfd` or a
   userspace mismatch is cheap to find and cheap to fix.
2. Consider a **newer 6.x stable** (`linux_6_18.y` patch bump) rather than 7.x. It stays inside the
   OpenZFS range, keeps the aspect's kernel table valid, and picks up the amdkfd fixes for the 6.18
   branch that 6.18.62 may not carry.
3. Re-open this task when OpenZFS tags a release whose `META` says `Linux-Maximum: 7.3` and nixpkgs
   ships that release next to `linux_7_3`. Then run P1 → P2 → P3 in that order.

## Sources

OpenZFS:

- `zfs-2.4.4` META: <https://raw.githubusercontent.com/openzfs/zfs/zfs-2.4.4/META>
- `zfs-2.4.4` release notes: <https://github.com/openzfs/zfs/releases/tag/zfs-2.4.4>
- `zfs-2.3.9` release notes: <https://github.com/openzfs/zfs/releases/tag/zfs-2.3.9>
- `zfs-2.2.11` release notes: <https://github.com/openzfs/zfs/releases/tag/zfs-2.2.11>
- OpenZFS master META (`2.4.99`, maximum 7.3): <https://raw.githubusercontent.com/openzfs/zfs/master/META>

nixpkgs (pinned `26.11.20261106.296d5fa`, read from
`/nix/store/lk98r48k05nwda8yh4fzyd9bn6l5z02m-source`):

- `pkgs/top-level/linux-kernels.nix` — kernel list, `linux_default`, `linux_latest`, removals
- `pkgs/top-level/all-packages.nix` — `zfs = zfs_2_4` (line 7746)
- `pkgs/os-specific/linux/zfs/2_3.nix`, `2_4.nix`, `unstable.nix`, `generic.nix` — versions,
  supported ranges, `meta.broken`, `postPatch` META check
- `nixos/modules/tasks/filesystems/zfs.nix` — `selectModulePackage`, `boot.zfs.package`,
  `boot.zfs.modulePackage`
- `nixos/modules/system/boot/kernel.nix` — `boot.kernelPackages` default (lines 69–85)
- `nixos/tests/zfs.nix` — `series_2_3`, `series_2_4`, `unstable`, fixed `kernelPackages`

ROCm and amdgpu:

- ROCm 7.2.3 system requirements (R9700 supported; kernel list; PCIe atomics):
  <https://rocm.docs.amd.com/projects/install-on-linux/en/docs-7.2.3/reference/system-requirements.html>
- gfx1201 entered official ROCm support in 7.2:
  <https://github.com/LukeLamb/rdna4-ready/blob/main/FIXES.md>
- `hsa_init` failure with no `/dev/kfd`:
  <https://github.com/unslothai/unsloth/issues/9729>
- RDNA4 hang/reset regression on Linux 6.18:
  <https://gitlab.freedesktop.org/drm/amd/-/issues/4765>
- amdkfd fixes for 6.18:
  <https://kernelthread.org/t/20251112200930.8788-1-alexander.deucher@amd.com>
- Linux 7.2 AMDGPU power module: <https://phoronix.com/news/Linux-7.2-AMDGPU-Power-Mod>
- More Linux 7.2 AMDGPU fixes: <https://phoronix.com/news/Linux-7.2-More-AMDGPU-Fixes>
- Linux 7.2 feature overview: <https://phoronix.com/news/Linux-7.2-Best-Features>
- User report, kernel 7.2 breaks certain AMD GPU support:
  <https://discussion.fedoraproject.org/t/warning-new-kernel-7-2-breaks-certain-amd-gpu-support/195477>

Repository:

- [`hosts-den/brys/default.nix`](../../../../hosts-den/brys/default.nix) — LUKS ids, TPM settings,
  clevis, `vfio`, initrd modules, build path
- [`hosts-den/brys/README.md`](../../../../hosts-den/brys/README.md) — power-off recovery
- [`hosts-den/brys/llm-tuning-shared.nix`](../../../../hosts-den/brys/llm-tuning-shared.nix) — ARC cap
  kernel parameter
- [`modules/den/aspects/fs.nix`](../../../../modules/den/aspects/fs.nix) — kernel table, priority 1200,
  `kdn.fs.zfs.package`
- [`modules/den/aspects/disks.nix`](../../../../modules/den/aspects/disks.nix) — zpool import ordering
- [`modules/den/aspects/hw-gpu.nix`](../../../../modules/den/aspects/hw-gpu.nix) — `vfio-pci`,
  `iommu=pt`, `softdep amdgpu pre: vfio-pci`
- [`checks/README.md`](../../../../checks/README.md) — `den-eval-hw`, `bundle-vm` (empty by design)

## Self-building a 7.2 kernel

The owner's proposal: nixpkgs ships 7.3, OpenZFS 2.4.4 declares 7.2 as its maximum, so build a
7.2 kernel ourselves and pair it with ZFS 2.4.4. This section answers that proposal.

**Headline, measured:** the pair is accepted. A kernel package set built from `7.2.15` reports
`zfs_2_4.meta.broken = false` at evaluation, and ZFS 2.4.4 is the very release that added Linux 7.2
support. The blocker is not the build. It is that **7.2 is an end-of-life series**: self-building
it freezes the host on a kernel that receives no security fixes.

### 1. Is 7.2 still a supported series?

**No. 7.2 is EOL.** `https://www.kernel.org/releases.json` on 2026-11-19 says:

| Moniker  | Version                                        | `iseol`  | Released   |
| -------- | ---------------------------------------------- | -------- | ---------- |
| mainline | 7.4-rc3                                        | false    | 2026-11-15 |
| stable   | **7.3.5**                                      | false    | 2026-11-17 |
| stable   | **7.2.15**                                     | **true** | 2026-11-01 |
| longterm | 6.18.64                                        | false    | 2026-11-17 |
| longterm | 6.12.118, 6.6.162, 6.1.192, 5.15.225, 5.10.274 | false    | Nov 2026   |

- 7.2 was a normal stable series, not a mainline-only tag. It opened on 2026-08-17 and closed on
  2026-11-01 with **7.2.15** as the final release, after 15 point releases. That short life is why
  nixpkgs removed `linux_7_2` with a `throw` entry (section 1 of this document).
- **No security patches after 2026-11-01.** Every CVE fixed in 7.3.y or 6.18.y from that date on
  stays unfixed in a 7.2 kernel. This host starts `sshd` early in the boot order and is reachable
  over the mesh and the LAN, so "no kernel fixes" is not a theoretical cost.
- **The source is still mirrored.** `https://cdn.kernel.org/pub/linux/kernel/v7.x/` lists
  `linux-7.2.15.tar.xz` (153 MB, 01-Nov-2026), `linux-7.2.15.tar.sign` and the rolling
  `sha256sums.asc` (17-Nov-2026). All 7.2.0–7.2.15 tarballs remain. So the tarball is fetchable
  and verifiable; it is simply unmaintained.

### 2. How nixpkgs builds a kernel from an arbitrary version

This nixpkgs has **two** kernel builders, and only one takes a config file:

| Path    | Entry point                                                             | Config source                                                                                                    | Config file argument |
| ------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------- |
| generic | `buildLinux` = `callPackage kernel/generic.nix { }`                     | **generated** from `common-config.nix` + `structuredExtraConfig` + `extraConfig` + `kernelPatches[].extraConfig` | **none**             |
| manual  | `pkgs.linuxKernel.customPackage { … }` → `packagesFor (manualConfig …)` | a `.config` you supply                                                                                           | **`configfile`**     |

So a reused `linux_6_18` config goes through `customPackage`, not through `buildLinux`:

```nix
# pkgs/top-level/linux-kernels.nix
customPackage = { version, src, modDirVersion ? lib.versions.pad 3 version,
                  configfile, allowImportFromDerivation ? false }:
  recurseIntoAttrs (packagesFor (manualConfig {
    inherit version src modDirVersion configfile allowImportFromDerivation;
  }));
manualConfig = callPackage ../os-specific/linux/kernel/build.nix { };
```

`build.nix` details that decide success:

- it links `configfile` as `$buildRoot/.config` and runs **`make oldconfig`**: symbols that 7.2
  removed are dropped, new symbols take their Kconfig default, silently;
- it reads `include/config/kernel.release` and **refuses the build** when the result differs from
  the declared `modDirVersion` (the default `lib.versions.pad 3 version` gives `7.2.15`);
- `meta.broken = withRust && lib.versionOlder version "6.12"` → false for 7.2;
- `requiredSystemFeatures = [ "big-parallel" ]`, `meta.timeout = 14400` (4 h).

**Measured trap: the `modules` output depends on the config being readable at evaluation time.**
`build.nix` sets `config = lib.optionalAttrs (builtins.isPath configfile || allowImportFromDerivation)
(readConfig configfile)`. A derivation as `configfile` is not a path, so `config` stays `{}`,
`MODULES` reads as off, and the kernel is built **without a `modules` output** — unusable for NixOS:

```
withoutFile   = [ "out" "dev" ]              # configfile = a store path, IFD disabled
withPlainPath = [ "out" "dev" "modules" ]    # configfile = a plain path with CONFIG_MODULES=y
```

Fix: pass `allowImportFromDerivation = true` for `pkgs.linux_6_18.configfile`, or copy that file to
a plain path in `.cache/agent-notes/`.

**Expression sketch** (~25 lines, throwaway, never in the flake):

```nix
# .cache/agent-notes/linux-7.2/default.nix
{ pkgs ? import <nixpkgs> { } }:
let
  # The final 7.2.y release. kernel.org marks it EOL; there will be no 7.2.16.
  src = pkgs.fetchurl {
    url = "mirror://kernel/linux/kernel/v7.x/linux-7.2.15.tar.xz";
    hash = "sha256-0Pax1zJMk3zK61xMpwhL/Pcdsu2z4tOjHwrYOmgYCas=";   # prefetched 2026-11-19
  };

  # Start from the 6.18 config. `make oldconfig` reconciles it with 7.2.
  configfile = pkgs.linux_6_18.configfile;      # linux-config-6.18.62

  # A full module package set: it carries zfs_2_4, zfs_2_3, zfs_unstable, ...
  linuxPackages_7_2 = pkgs.linuxKernel.customPackage {
    version = "7.2.15";
    inherit src configfile;
    # Required: `configfile` is a derivation. Without this the set has no `modules` output.
    allowImportFromDerivation = true;
  };
in
{
  inherit linuxPackages_7_2;
  kernel = linuxPackages_7_2.kernel;
  zfs = linuxPackages_7_2.zfs_2_4;
}
```

Commands, and the measured answer:

```sh
# the exact tarball hash used above
nix store prefetch-file --json --hash-type sha256 \
  https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.15.tar.xz
# {"hash":"sha256-0Pax1zJMk3zK61xMpwhL/Pcdsu2z4tOjHwrYOmgYCas=", ...}

# gate 1: the pair is accepted at evaluation time, no build
nix eval --impure --expr '
let pkgs = import <nixpkgs> { };
    k = pkgs.linuxKernel.customPackage {
      version = "7.2.15";
      src = pkgs.emptyFile;                 # brokenness depends on `version` only
      configfile = pkgs.emptyFile;
    };
in { inherit (k.kernel) version modDirVersion;
     zfs = k.zfs_2_4.meta.broken;
     zfsUnstable = k.zfs_unstable.meta.broken;
     zfs23 = k.zfs_2_3.meta.broken; }'
# { version = "7.2.15"; modDirVersion = "7.2.15"; zfs = false;
#   zfsUnstable = false; zfs23 = false; }

# gate 2: the real build (kernel first, then the out-of-tree module)
nix build -f .cache/agent-notes/linux-7.2/default.nix zfs -o result-zfs-7.2
```

Gate 2 is the expensive one: a full kernel compile plus the ZFS module. It needs the 153 MB
tarball, several GB of build space, and CPU time measured in tens of minutes on this class of
machine. A `.config` mismatch shows up as `make oldconfig` prompts, not as an error.

### 3. Would the ZFS build accept it?

**Yes, at the version gate, and the measured flags confirm it** (`zfs = false` above). Three
reasons:

- `META` in zfs-2.4.4 says `Linux-Maximum: 7.2`, and `2_4.nix` declares the same value, so
  `generic.nix`'s `postPatch` grep passes and `kernelIsCompatible` is true (`7.2 >= 4.18`,
  `7.2 >= 7.2`).
- 2.4.4 is exactly the release that added 7.2 support. Its notes list `Linux 7.2 compat: META`
  and `Linux 7.2: zpl_super: convert to sget_fc()`. The compat code exists for this API level.
- `zfs_2_3` and `zfs_unstable` also report `false`, so the choice of branch is open.

Remaining risks, in order of how likely they are to bite:

1. **The inherited `.config`.** `make oldconfig` drops renamed or removed symbols and defaults the
   new ones. ZFS's `configure` checks the kernel symbols it needs (modules, crypto, zlib, zstd,
   lz4). A missing one fails the module build with a configure warning, not at boot. Diff
   `…/dev/lib/modules/7.2.15/build/.config` against `linux_6_18.configfile` after gate 2.
2. **A stable-branch backport.** A 7.2.y point release can backport a VFS or MM fix that changes an
   API ZFS uses. 7.2.15 is the last release, so a mismatch found later would get no 7.2.16 fix;
   it would need a ZFS patch or a kernel revert.
3. **Userspace does not move.** `boot.zfs.package` stays 2.4.4, so the tools, the pool format and
   `zpool` behaviour are unchanged. There is no userspace/module skew to manage.
4. **Nobody has tested it.** `nixosTests.zfs.*` pins `pkgs.linuxPackages` (6.18), and nixpkgs CI
   covers only the kernels nixpkgs ships. The first boot of this pair is the first test of it.
5. **No security updates.** See section 1. This one never improves.

### 4. Maintenance cost and the security argument

|                       | 7.2.15, self-built                                            | 6.18.64, longterm, as today            |
| --------------------- | ------------------------------------------------------------- | -------------------------------------- |
| Series state          | EOL since 2026-11-01                                          | supported longterm, releases regularly |
| Security fixes        | none, ever                                                    | yes, via nixpkgs and kernel.org        |
| OpenZFS 2.4.4 support | 4.18 – 7.2, accepted                                          | 4.18 – 7.2, accepted                   |
| nixpkgs support       | none; a local override                                        | first-class (`linux_6_18`)             |
| Update effort         | manual `version` + `hash` bump; no updater; no reason to bump | `nix flake update`                     |
| Build effort          | own kernel + own ZFS module on every change                   | cache.nixos.org                        |
| Tested by             | this task, once                                               | nixpkgs, NixOS tests, the fleet        |
| Failure cost on brys  | NanoKVM, power cycle, up to 1 h downtime                      | same, but far less likely              |

The asymmetry is the point. The self-built 7.2 kernel is _more_ work than 6.18 _and_ less secure,
for a kernel version that no measured goal on this host requires: ZFS gains nothing (2.4.4 already
supports 6.18), and the ROCm hypothesis is contradicted by AMD's own matrix (section "What a newer
kernel buys").

**Blunt recommendation: do not do it.** Build the expression only if a specific 7.2-only fix must
be tested, keep it in `.cache/agent-notes/`, prove it in the VM (P2), and throw it away. Do not put
an EOL kernel under the ZFS root of the host that also serves the local LLMs.

If the owner overrules this: freeze at 7.2.15 with the hash above, keep 6.18 in the boot menu,
state the EOL date in a comment beside the version, and re-run P3 before trusting a new build.

### 5. What the repository would have to change

The `kdn.fs-zfs` aspect hardcodes the kernel choice in a two-entry table and writes it at priority
1200 (`grep -n 'linux_6_18\|mkOverride 1200' modules/den/aspects/fs.nix`):

```nix
kernelPackage = lib.pipe [
  { name = "2.3.1+";  check = atLeastZFSVersion "2.3.1";
    pkg = pkgs.linuxKernel.packages.linux_6_18 or null; }
  { name = "default"; check = true;
    pkg = pkgs.linuxKernel.packages.linux_6_6; }
] [
  (map (e: lib.optional e.check (lib.trivial.warnIf (e.pkg == null) "kdn.fs.zfs: kernel package not found/removed for: ${e.name}" e.pkg)))
  builtins.concatLists
  (builtins.filter (pkg: pkg != null))
  builtins.head
];
...
boot.kernelPackages = lib.mkOverride 1200 kernelPackage;
```

To offer a 7.2 entry:

1. **A `let` binding for the custom set.** `linux_7_2` is not a nixpkgs attribute, so the aspect
   would hold a `pkgs.linuxKernel.customPackage { … }` value (or a `pkgs.callPackage` of the
   throwaway file). This puts a 153 MB fetch and a kernel build into every evaluation that touches
   the aspect, including `den-eval-hw`.
2. **A predicate for the entry.** Without one, `check = true` hands the EOL kernel to _every_ ZFS
   host in the table of the [zfs-arc-cap](../zfs-arc-cap/definition.md) task (`brys`, `oams`,
   `etra`, `briv`, `pryll`, …). A new option such as `kdn.fs.zfs.kernel = "6_18" | "7_2"`, default
   `"6_18"`, is the minimum.
3. **The fallback chain must survive.** The `or null` + `warnIf` + `filter` + `head` sequence is the
   safety net: a missing or unfetchable kernel entry falls through to 6.18 instead of failing
   evaluation. A new entry must keep `pkg = … or null` and keep its `check` independent of the
   fetch.
4. **The value must survive the NixOS `apply`.** `boot.kernelPackages` is wrapped by
   `kernelPackages.extend` and `kernel.override { randstructSeed; kernelPatches; features; }`
   (`nixos/modules/system/boot/kernel.nix` lines 69–85). A `customPackage` set satisfies this:
   measured `hasExtend = true`, and `build.nix` accepts those three arguments.
5. **`boot.zfs.package` stays as it is.** `cfg.package` = `pkgs.zfs_unstable` (2.4.4) needs no
   change; only the kernel side moves.
6. **A new assertion.** No current check fails when a kernel table entry is wrong; `den-eval-hw`
   only evaluates the hardware aspects. An entry that selects an EOL kernel would pass every
   check and reach the fleet.

That is a design change in a shared aspect, not a one-line addition. It belongs in its own task,
and only after a 7.2 build passes P2 and P3.

### Sources for this section

- kernel.org release list (`iseol` flags, 7.2.15 EOL): <https://www.kernel.org/releases.json>
- kernel.org v7.x tarball directory (7.2.0–7.2.15 mirrored):
  <https://cdn.kernel.org/pub/linux/kernel/v7.x/>
- Prefetch of `linux-7.2.15.tar.xz`, 2026-11-19:
  `sha256-0Pax1zJMk3zK61xMpwhL/Pcdsu2z4tOjHwrYOmgYCas=`
- nixpkgs `pkgs/os-specific/linux/kernel/build.nix` — `configfile`, `oldconfig`,
  `modDirVersion` check, `config`/`allowImportFromDerivation`, `meta.broken`, `meta.timeout`
- nixpkgs `pkgs/os-specific/linux/kernel/generic.nix` — `buildLinux`, generated config
- nixpkgs `pkgs/os-specific/linux/kernel/mainline.nix` — `mirror://kernel` source and
  `modDirVersion = lib.versions.pad 3 version`
- nixpkgs `pkgs/top-level/linux-kernels.nix` — `packagesFor`, `customPackage`, `manualConfig`,
  `buildLinux`
- OpenZFS 2.4.4 release notes (7.2 compat entries):
  <https://github.com/openzfs/zfs/releases/tag/zfs-2.4.4>
