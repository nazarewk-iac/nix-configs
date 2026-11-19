---
type: Task
description: Decide whether the R9700 can be passed through to a VM on brys so the LLM stack gets its own kernel, report the measured IOMMU groups, and rank the tests that prove or kill the idea.
status: open
authored_by: agent
timestamp: 2026-11-19T12:00:00+01:00
---

# The LLM stack in a VM with the R9700 passed through

## Result in one paragraph

**VFIO is possible on this board with these two cards, and the suspected fatal blocker is not
real.** The read-only probes on brys show the R9700 GPU function `0000:0d:00.0` **alone** in IOMMU
group 30, its HDMI-audio function `0000:0d:00.1` alone in group 31, and the Lexa in group 32. The
two bridges that the topology shares (`0b:00.0`, `0c:00.0`) are **part of the R9700 card**, not the
motherboard, and they sit in their own groups 28 and 29. The Lexa shares no group with the R9700.
The card also reports `reset_method=[flr bus]`, so it has a function-level reset. `iommu=pt` is
already on the kernel command line and AMD-Vi is active. **microvm.nix supports VFIO passthrough**
on both its `cloud-hypervisor` and `qemu` runners through the `microvm.devices` option.

**The VM does not beat the host for the workload served today.** llama.cpp on Vulkan needs no ROCm,
so the `gfx803` defect that the VM would hide is already worked around by one `LD_PRELOAD` shim. A
guest with a fixed RAM allocation **lowers** the model ceiling from 125 GiB to whatever is left
after the host keeps its share. And no public report shows an R9700 working in a KVM guest for
compute, while one public report shows it failing in a Xen guest. The strongest reason to build it
is not the kernel: it is that a wedged engine becomes a VM restart instead of a brys power cycle,
and that a HIP-only tool then needs no patch. Rank the tests so the cheap ones run first.

## The proposal under test

Run the LLM inference stack in a VM, pass the R9700 through with VFIO, and let the guest run its
own kernel. Keep the host on its ZFS-bound 6.18 LTS. Share the model files into the guest. The
claimed gains are: the host's upgrade cadence stops governing the LLM stack, the guest kernel can
be newer or tuned, and the `llms` boot specialisation becomes unnecessary.

Four claims to test: (1) the right tool exists, (2) the guest solves a brys-specific problem,
(3) the hardware allows the passthrough, (4) the model files can be shared fast enough.

## 1. Is this even the right tool?

### microvm.nix does support VFIO

The option exists and it is not decorative:

```nix
microvm.devices = [ { bus = "pci"; path = "0000:0d:00.0"; } ];
```

- `nixos-modules/microvm/options.nix` declares `microvm.devices` as a list of `{ bus, path }` with
  `bus = "pci" | "usb"` and the example `{ bus = "pci"; path = "0000:01:00.0"; }`.
- `nixos-modules/microvm/pci-devices.nix` turns that list into a `pci-setup` script: it runs
  `modprobe vfio-pci`, unbinds whatever driver holds the device, writes `vfio-pci` to
  `driver_override`, triggers `/sys/bus/pci/drivers_probe`, and hands `/dev/vfio/<group>` to
  `microvm:kvm`.
- The host module runs that script as a unit (`ConditionPathExists` on
  `${stateDir}/%i/current/bin/pci-setup`, `ExecStart` on the same path) before the VM starts.
- The `cloud-hypervisor` runner emits `--device path=/sys/bus/pci/devices/<path>`.
- The `qemu` runner emits `-device vfio-pci,host=<path>,multifunction=on`, creates the
  `pcie-root-port`s first, and turns `pcie=on` on for the `microvm` machine type when a PCI device
  is present.

I checked the pinned revision (`b7bd556`, 2026-10-29) as well as `main` (`194a254`, 2026-11-13);
the file is the same in both.

### What each hypervisor can and cannot do

| Hypervisor                        | PCI VFIO   | Shares              | Verdict for this job                       |
| --------------------------------- | ---------- | ------------------- | ------------------------------------------ |
| `qemu`                            | yes        | 9p + virtiofs       | **the mature VFIO path**; can use `-M q35` |
| `cloud-hypervisor`                | yes        | virtiofs, **no 9p** | works, but the weakest GPU field evidence  |
| `firecracker`                     | **no**     | no 9p, no virtiofs  | **not usable**: virtio-MMIO, no PCI        |
| `crosvm`                          | yes        | 9p broken           | no                                         |
| `kvmtool`, `stratovirt`, `alioth` | yes        | limited             | no                                         |
| `vfkit`                           | macOS only | virtiofs            | no                                         |

So the honest answer to "can microvm.nix do VFIO" is **yes**, and the choice inside microvm.nix is
`qemu` or `cloud-hypervisor`.

### The real limits of a passthrough guest

These are not microvm.nix limits; they are VFIO limits and they apply to libvirt too:

| Limit                                                                                                                                                                                                     | Consequence on brys                                                                                                                |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **No live migration.** A device behind a virtual IOMMU "is not supported and is refused at migration start". The generic `vfio_pci` driver has no migration v2 support.                                   | The guest cannot be moved or snapshotted. A restart is the only recovery.                                                          |
| **No memory balloon.** With a device that DMAs into guest RAM, guest memory must be a fixed reservation. microvm.nix defaults `balloon = false`, `hotplugMem = 0`, and `mem` is a fixed positive integer. | The guest RAM is a hard budget taken from the host. See section 4.                                                                 |
| **No useful virtual IOMMU.** cloud-hypervisor states a vIOMMU blocks migration and adds no benefit for a passthrough GPU.                                                                                 | Guest needs no `amd_iommu=on`. Simpler than feared.                                                                                |
| **Every device in a group must be passed together.** The cloud-hypervisor VFIO document is explicit about this.                                                                                           | On brys the two R9700 functions are in _different_ groups, so passing `0d:00.0` alone is legal.                                    |
| **Large BARs stress the guest PCI allocator.** A passthrough GPU with a 64 GB BAR failed to enumerate in cloud-hypervisor issue #4375; Nvidia BAR re-allocation failed in issue #6147.                    | The R9700 has a **32 GiB BAR0** (measured). The guest needs a large 64-bit MMIO window. QEMU `q35` is the path with known answers. |

### microvm.nix versus plain libvirtd

| Criterion                         | microvm.nix (`qemu` runner)                                          | microvm.nix (`cloud-hypervisor`) | plain `virtualisation.libvirtd`               |
| --------------------------------- | -------------------------------------------------------------------- | -------------------------------- | --------------------------------------------- |
| Guest defined in this flake       | **yes**, one NixOS config                                            | yes                              | no; XML plus a separate image                 |
| Host-side VFIO setup              | generated `pci-setup` unit                                           | same                             | libvirt `managed='yes'`, or a hook script     |
| Field reports for GPU passthrough | **many** (QEMU is the VFIO reference)                                | few, and one large-BAR failure   | **most**: AMD's own guide, Proxmox, Arch Wiki |
| Share protocols                   | 9p + virtiofs                                                        | virtiofs only                    | 9p, virtiofs, NFS, block                      |
| Deploy story                      | `microvm.deploy.installOnHost`, `microvm@<name>.service`             | same                             | `virsh define` + `start`                      |
| Debugging                         | QEMU monitor, journal                                                | `ch-remote`, thinner tooling     | `virsh`, the most documented                  |
| Already in this repository        | **yes**: `inputs.microvm`, `virt-microvm-host`, `virt-microvm-guest` | same                             | `virt-libvirtd` aspect                        |

**Verdict:** microvm.nix with the **`qemu` runner** is the right packaging. It keeps QEMU's mature
VFIO and gains the declarative guest plus the `microvm@` unit. cloud-hypervisor is the smaller
attack surface but has no GPU field evidence and a large-BAR failure on record. Plain libvirtd is
the best _debugging_ tool and the worst _packaging_ tool, so use it only as a one-off smoke test if
QEMU on the command line proves awkward.

## 2. What the VM buys on brys (the `gfx803` synergy)

This is the strongest argument for the VM, and it is real, but it is narrower than it looks.

**The defect.** `docs/tasks/2026-11/rocm-on-brys/` proves the cause: ROCm 7.2.4 aborts `hsa_init()`
when any KFD node reports a legacy 32-bit doorbell. The Lexa (Polaris 12, `gfx803`) is such a node.
The check is `node_props.Capability.ui32.DoorbellType != 2` in `amd_gpu_agent.cpp`, and
`DiscoverGpu` only tolerates `HSA_STATUS_ERROR_INVALID_ISA`. One old card kills HIP for the whole
machine.

**Why a guest fixes it.** KFD topology is built by the kernel from the devices that kernel sees. A
guest with only the R9700 passed through has one GPU node, with doorbell type 2. The `if` never
fires. Stock ROCm works with no patch and no `LD_PRELOAD`.

**Why that is not enough on its own.**

- llama.cpp, the only engine measured on brys, serves this host over **Vulkan**, not HIP. Vulkan
  never touches HSA. At 21.9 t/s decode and 255-289 t/s prefill it is already the faster path
  (the same task records R9700 Vulkan 138.8 vs ROCm 98.0 t/s on a 7B).
- The shim already unblocks the one HIP consumer that exists: the signed Strata bundle loads a
  62 GB pack and reports `GPU 0: AMD Radeon AI PRO R9700 (gfx1201)`.
- So the VM buys a _cleaner_ fix for a problem that already has a working fix, plus a route to
  HIP-only stacks (vLLM, PyTorch, Triton) without carrying a `rocm-runtime` patch.

**The stronger argument is availability, not ROCm.** A crashed engine or a wedged `amdgpu` inside a
guest stops the guest. The host, its desktop and its SSH stay alive. brys has a documented
power-off fault: a shutdown or a warm `reboot` can leave the machine dark for 20-60 minutes and
sometimes needs the mains lead pulled (`hosts-den/brys/README.md`). Anything that turns "reboot the
host" into "restart a unit" is worth more on this machine than on a normal one.

**The kernel argument is weak.** `docs/tasks/2026-11/brys-kernel-7-zfs/` already shows a newer
kernel buys nothing here: OpenZFS 2.4.4 stops at Linux 7.2, the only 7.x in nixpkgs is 7.3, and
`gfx1201` compute is not a 7.x feature. The guest does remove the ZFS constraint, and that freedom
has value, but no measured goal on this host needs it today.

## 3. IOMMU reality on brys (measured 2026-11-19)

Read-only probes only. No configuration change, no VM, no VFIO binding, no reboot.

### The groups

`/sys/kernel/iommu_groups/*`, kernel `6.18.62`:

|  Group | Devices                        | What it is                                                                           |
| -----: | ------------------------------ | ------------------------------------------------------------------------------------ |
|      5 | `0000:00:03.1`                 | CPU root port, feeds `[0b-0d]`                                                       |
| **28** | `0000:0b:00.0`                 | **card-internal** PCIe switch upstream port (`1002:1478` "Navi 10 XL Upstream Port") |
| **29** | `0000:0c:00.0`                 | **card-internal** switch downstream port (`1002:1479`)                               |
| **30** | `0000:0d:00.0`                 | **R9700 GPU** (`1002:7551`)                                                          |
| **31** | `0000:0d:00.1`                 | **R9700 HDMI audio** (`1002:ab40`)                                                   |
|      6 | `0000:00:03.2`                 | CPU root port, feeds `[0e]`                                                          |
| **32** | `0000:0e:00.0`, `0000:0e:00.1` | **Lexa GPU + its audio** (`1002:699f`, `1002:aae0`)                                  |

```
$ for g in /sys/kernel/iommu_groups/*; do echo "group $(basename $g): \
    $(ls $g/devices | tr '\n' ' ')"; done
…  (excerpt: only the GPU groups are shown; all 38 groups are in research.md)
group 30: 0000:0d:00.0
group 31: 0000:0d:00.1
group 32: 0000:0e:00.0 0000:0e:00.1
```

**Reading.** The R9700 is alone. The suspected fatal blocker — "it shares bridges with the Lexa" —
is false. The bridges are the card's own PCIe switch, not a shared motherboard slot, and the kernel
already split every function into its own group. `lspci -tv` confirms it:

```
+-03.1-[0b-0d]----00.0-[0c-0d]----00.0-[0d]--+-00.0  Navi 48 [Radeon AI PRO R9700]
|                                            \-00.1  Navi 48 HDMI/DP Audio Controller
+-03.2-[0e]--+-00.0  Lexa PRO
             \-00.1  Baffin HDMI/DP Audio
```

The two cards hang off **different CPU root ports** (`00:03.1` and `00:03.2`). Nothing is shared.

### The IOMMU is already on

- `/proc/cmdline` contains `iommu=pt`. It does **not** contain `amd_iommu=on`, and it does not need
  to: an AMD part turns `amd_iommu` on by default, and the repository's `hw-gpu` aspect comments
  say so. `iommu=pt` is the standard VFIO host setting.
- `journalctl -k` shows `AMD-Vi: Using global IVHD EFR:0x0, EFR2:0x0`,
  `pci 0000:00:00.2: AMD-Vi: IOMMU performance counters supported`,
  `iommu: Default domain type: Passthrough (set via kernel command line)`, and one
  `Adding to iommu group N` line per device.
- `/sys/class/iommu/ivhd0` exists.
- `vfio`, `vfio_pci` and `vfio_iommu_type1` are already loaded, because brys sets
  `kdn.hw.gpu.vfio.use = true`. No `vfio-pci.ids=` is set, so nothing is bound to VFIO today.

### Reset, power state and the barrier

| Probe                            | Value                                            | Meaning                                                       |
| -------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- |
| `0d:00.0/reset_method`           | `flr bus`                                        | **FLR exists**; QEMU/libvirt can reset the card between boots |
| `0d:00.1/reset_method`           | absent                                           | audio function has no FLR; leave it on the host               |
| `0d:00.0/d3cold_allowed`         | `1`                                              | the card may drop to D3cold when `amdgpu` unbinds             |
| `0d:00.0/power/control`          | `auto`                                           | runtime PM is active; the D3 hazard is live                   |
| `0d:00.0/power_state`            | `D0`                                             | idle now, not suspended                                       |
| BAR0 / BAR2 / BAR4 / BAR5 / BAR6 | **32 GiB** / 256 MiB / 256 B / 512 KiB / 128 KiB | ReBAR is on; the guest needs a >32 GiB 64-bit MMIO window     |
| Link `00:03.1`                   | `LnkCap 16 GT/s x8`, `LnkSta 2.5 GT/s x8`        | Gen4 x8 slot, idle-downclocked                                |
| Link `0c:00.0 → 0d:00.0`         | `32 GT/s x16`                                    | the card's internal link is Gen5 x16                          |
| Atomics `00:03.1`                | `Routing+ 32bit+ 64bit+ 128bitCAS-`              | the root port routes atomics                                  |
| Atomics `0d:00.0`                | `32bit+ 64bit+ 128bitCAS-`, `ReqEn+`             | the GPU issues atomics                                        |

The atomics check matters: ROCm needs atomic routing on AMD platforms. Both ends report it, so this
is **not** a blocker. `128bitCAS-` is expected on a consumer root complex and ROCm does not need it.

**The D3 hazard is the real trap.** A field-tested RDNA4 guide (RX 9070 XT, same Navi 48 family)
records it: when `amdgpu` unbinds, runtime PM plus ACPI can drop the card to D3cold within about a
second, and `vfio-pci` then reads `0xFFFF` everywhere ("stuck in D3"). The fix is to lock the card
in D0 before the unbind:

```sh
echo 0 > /sys/bus/pci/devices/0000:0d:00.0/d3cold_allowed
echo on > /sys/bus/pci/devices/0000:0d:00.0/power/control
```

microvm.nix's generated `pci-setup` does **not** do this. A guest on brys needs it, so
`microvm.preStart` must run it before `pci-setup`. That is a small, known gap, not a design
problem.

Two more findings from the same guide, both relevant to brys: **do not pre-bind the card to
`vfio-pci` at boot** (let `amdgpu` initialise it first), and **Navi 48 has no reset bug** unlike
RDNA 1-3. The second claim is contradicted by Proxmox reports of an "RX 9070 reset bug", so treat
"no reset bug" as _probable, unproven on this card_, and prove it in P2 below.

## 4. Model sharing: the numbers that decide the design

The models are 62 GB (`Qwen3.8-Flash-Next UD-IQ1_S`) and 102 GB (`GLM-5.3-Flash UD-IQ2_XXS`).
Both engines mmap the weights, so the guest page cache holds the model and a miss becomes a read
from the share.

| Mechanism                                           | Sequential read                                                                                                          | Copies of a 62 GB model in RAM  | Est. load of 62 GB  | Verdict                                       |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------- | ------------------- | --------------------------------------------- |
| **virtio-blk on a ZFS zvol**, `cache=none`/O_DIRECT | ~2.0 GB/s cold, ~5.4-10 GB/s warm (measured on brys)                                                                     | **1** (guest only)              | **~31 s**           | **use this for the weights**                  |
| virtiofs (virtiofsd, no DAX)                        | 0.65 GB/s single-queue, ~2.5 GB/s multi-queue (measured, qemu-devel 2020); 134-154 MB/s real-world 4k/1M on Proxmox 2025 | **2** (guest + host page cache) | 25-95 s theoretical | works, but doubles RAM. Only for small files. |
| virtio-9p                                           | ~0.4 GB/s (same source)                                                                                                  | 2                               | ~155 s              | no                                            |
| NFS over virtio-net                                 | bounded by TCP, typically 1-5 GB/s on loopback                                                                           | 2                               | 12-60 s             | no benefit over block                         |
| host today (mmap over ZFS)                          | **~430-450 MB/s effective** (45 GB in 105 s, 58.5 GB in 129 s)                                                           | 1                               | **~135 s**          | the baseline to match                         |

**Why virtio-blk wins.** `virtiofsd` cannot do DAX, and microvm.nix says so: `microvm.shares.*.dax`
is "ignored unless `proto = virtiofs`" and works only on `alioth` and `crosvm`. Without DAX there is
no page-cache sharing, so the guest caches a copy and the host caches another. On a 125 GiB host
that is fatal for a 100 GB model and wasteful for a 62 GB one. A block device has one cache, and it
maps exactly onto llama.cpp's mmap.

**Why not virtiofs for the big files even when RAM allows it.** `virtiofsd` on ZFS has a known
open-file-handle problem, which is why microvm.nix exposes
`microvm.virtiofsd.inodeFileHandles = "prefer"` with a link to virtiofsd issue #121. And a FUSE
page fault costs more than a block page fault, which is why the qemu-devel thread and virtiofsd
issue #66 both show virtio-blk finishing the same job in about half the time.

**The RAM ceiling is the real cost.** A guest RAM figure is a fixed reservation; ballooning is off
and must stay off. With 125 GiB usable:

| Model                              | Guest needs | Host left | Fits?                                                    |
| ---------------------------------- | ----------: | --------: | -------------------------------------------------------- |
| flash-next `UD-IQ1_S`, 62 GB       |     ~72 GiB |   ~53 GiB | **yes**, comfortable                                     |
| GLM-5.3-Flash `UD-IQ2_XXS`, 102 GB |    ~112 GiB |   ~13 GiB | **marginal**; the desktop and the 8 GiB ARC fight for it |
| DeepSeek V4.1-Flash, 233 GB        |           — |         — | no, already no on the host                               |

So a VM **lowers the ceiling** from "whatever the page cache will hold" to "the guest's allocation".
That is the opposite of what an LLM host wants, and it is the strongest technical argument against
moving the whole stack.

## 5. What it costs

| Cost                                                  | Detail                                                                                                                                                                | Mitigation                                                                                                                                                                                                             |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **The host loses the GPU entirely** while the VM runs | `MESA_VK_DEVICE_SELECT=1002:7551!` in `hosts-den/brys/llm.nix` would select nothing. No host-side llama.cpp, no host-side Vulkan compute.                             | Accept it; the guest owns the card, exactly as an appliance specialisation would.                                                                                                                                      |
| **Display stays on the Lexa**                         | Already true (`0e:00.0` drives `DP-4`, the R9700 is compute-only).                                                                                                    | None needed. Passthrough does not touch the Lexa: different root port, different group.                                                                                                                                |
| **Reboot coupling**                                   | A guest restart is cheap; a **host** reset is not. `virsh destroy` on an active AMD GPU is a documented way to wedge the card into a state only a host reboot clears. | Always stop the guest from inside the guest. Use `shutdown`, never a force-kill.                                                                                                                                       |
| **A wedged guest GPU may still need a host reset**    | If FLR fails, the card can stay in a bad state and `amdgpu` cannot rebind.                                                                                            | P2 tests five start/stop cycles before any of this is believed.                                                                                                                                                        |
| **A second OS to patch**                              | Guest kernel, guest ROCm or Mesa, guest llama.cpp.                                                                                                                    | The guest is one NixOS config in this flake, so `nix flake update` covers it.                                                                                                                                          |
| **Build story**                                       | The guest image is built by the host flake.                                                                                                                           | `microvm.deploy.installOnHost` builds on brys and installs the runner; `microvm@<guest>.service` starts it; `microvm.deploy.sshSwitch` switches in place because the guest mounts the host `/nix/store` over virtiofs. |
| **Debugging is one layer deeper**                     | A black console is now two systems to inspect.                                                                                                                        | Keep the serial console (`microvm.qemu.serialConsole`, default true) and the guest's journal on a virtiofs share.                                                                                                      |
| **brys-specific**: the power-off fault                | Any host reboot risks 20-60 minutes of downtime and sometimes an AC disconnect.                                                                                       | This is the cost that makes "restart a unit, not the host" valuable — and the cost that a _failed first test_ would charge.                                                                                            |

## 6. Decision and ranked plan

### The decision

1. **VFIO is available.** Build the test; do not assume the board blocks it.
2. **Do not move the served stack into a VM yet.** It costs RAM ceiling and adds a layer, and
   llama.cpp/Vulkan gains nothing.
3. **Test it anyway, in this order, because the first three tests are cheap and the fourth is the
   one that pays.** If P1 or P4 fails, the idea is dead and the answer is recorded.

### Ranked plan

Each step has one acceptance number. Stop at the first failure and write it down.

| #      | Step                                                                                                                                                                                                                                                                                                                         | Cost                                            | Acceptance                                                                                                                                                                                        |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **P0** | **Read-only baseline, already done in this task.** Record the groups, `reset_method`, `d3cold_allowed`, the BAR map, the link caps, the atomics bits, `/proc/cmdline`.                                                                                                                                                       | minutes, no change                              | groups 30/31 hold only R9700 functions; `reset_method` contains `flr`. **Met** — see section 3.                                                                                                   |
| **P1** | **One-shot QEMU smoke test, no Nix, no llama.cpp.** Stop `llama-swap`. `d3cold_allowed=0`, `power/control=on`, unbind `amdgpu` from `0d:00.0` and `0d:00.1`, bind `vfio-pci`, then `qemu-system-x86_64 -M q35 -cpu host -m 16G -device vfio-pci,host=0d:00.0`. Boot any Linux with `amdgpu` (kernel ≥ 6.13 for `gfx1201`; nixpkgs 6.18 is fine) and `rocminfo`. | ~30 min of exclusive GPU, no host config change | guest `lspci` shows `1002:7551`; `/dev/kfd` exists; `rocminfo` lists `gfx1201` and **no `gfx803`**; `hsa_init` succeeds with stock ROCm. **This is the test that proves the section-2 argument.** |
| **P2** | **Reset loop.** Five guest start/stop cycles on the same host boot.                                                                                                                                                                                                                                                          | ~20 min                                         | 5/5 cycles, `0d:00.0` returns to `amdgpu` each time, no host reboot, no `amdgpu` probe failure.                                                                                                   |
| **P3** | **Model-sharing shoot-out.** `fio` sequential read of the real 62 GB GGUF through virtiofs, through 9p, and through virtio-blk on a ZFS zvol with `cache=none`.                                                                                                                                                              | ~1 h, needs a zvol                              | the chosen mechanism reads at **≥ 1.5 GB/s**, and a cold llama.cpp load of 62 GB finishes in **≤ 120 s** (host today: ~135 s).                                                                    |
| **P4** | **The workload.** llama.cpp Vulkan in the guest, same preset as `data/llm.nix`: `ngl 99`, `nCpuMoe 26`, 64k, `q8_0` KV, `--fit off`, 16 threads.                                                                                                                                                                             | ~1 h                                            | decode **≥ 20.8 t/s** and prefill **≥ 242 t/s**, i.e. **within 5 %** of the host's 21.9 / 255-289. A larger loss means the VM is not worth it.                                                    |
| **P5** | **Package it.** A `nixosConfigurations.llm-guest` in this flake using `virt-microvm-host` + `virt-microvm-guest`, `microvm.devices`, `microvm.qemu.machine = "q35"`, a `microvm.preStart` that pins D0, and virtio-blk on a zvol.                                                                                            | days                                            | `systemctl restart microvm@llm` brings the API back with no host reboot, and `nix flake update` + `microvm.deploy.installOnHost` is the whole upgrade.                                            |

### When this beats just running on the host

It wins in exactly four cases:

1. **A HIP-only tool is required** — vLLM, PyTorch, Triton, or a vendor bundle whose runtime cannot
   be patched. The guest has no `gfx803` node, so stock ROCm works.
2. **The LLM stack must be restartable without restarting brys.** On this host that is worth more
   than usual, because a host reboot can cost an hour.
3. **The host must stay on the ZFS-bound 6.18 kernel while the guest needs something else.** True as
   a capability, not true as a present need.
4. **The appliance profile is wanted without a reboot.** A guest with an appliance `profile` gives
   the `llms` specialisation's semantics — the box is given to the models — while the desktop and
   SSH stay up. That is strictly better than a boot specialisation.

It loses whenever the answer is "serve flash-next at 21.9 t/s". The host does that today with no
virtualisation, no second OS, and the full 125 GiB of page cache.

## Risks and open questions

- **No proof of concept exists for an R9700 in a KVM guest.** AMD's own 2026 Proxmox article reports
  ROCm and PyTorch validated end-to-end on passed-through Radeon GPUs, and a Qubes user reports the
  R9700 working for "amd + vulkan" inference. A second Qubes user reports the same card failing in
  Xen with `MES(1) failed to respond to msg=SET_HW_RSRC` on four dom0 kernels and two guest kernels,
  while the card is stable unvirtualised. **P1 settles it for this board.**
- **The 32 GiB BAR0 is the likeliest mechanical failure.** cloud-hypervisor issue #4375 shows a
  64 GB BAR failing to enumerate; the CachyOS RDNA4 guide needed a 64 GiB OVMF MMIO window for a
  16 GiB BAR. `-M q35` plus a large `above-4g` window is the known-good shape.
- **`iommu=pt` is already set, so no boot-parameter change is needed.** If a later kernel is tested,
  keep `iommu=pt`; a device in passthrough mode still gets a VFIO DMA domain.
- **FLR is reported but not proven.** `reset_method=[flr bus]` means the kernel _offers_ FLR, not
  that the card recovers. P2 is the proof.
- **Do not enable ballooning or virtio-mem** on a guest with a passed-through device. A page the
  guest reports as free can still be a DMA target. microvm.nix's defaults are already correct.
- **The `llms` specialisation does not exist on the den host** (`hosts-den/brys/README.md` says it
  was not ported), so there is nothing to supersede today. A guest would replace it _if_ it is ever
  ported.

## Sources

Host facts, measured 2026-11-19 on brys, kernel `6.18.62`, read-only:

- `/sys/kernel/iommu_groups/*/devices`, `/sys/class/iommu/ivhd0`, `/proc/cmdline`,
  `journalctl -k -b` (the `Adding to iommu group N` lines).
- `/sys/bus/pci/devices/0000:0d:00.0/{reset_method,d3cold_allowed,power/control,power_state,resource}`.
- `lspci -Dnn`, `lspci -tv`, `lspci -vv` (with `sudo -n` for the extended capabilities: `DevCap2`,
  `AtomicOpsCap`, `LnkCap`, `LnkSta`).
- `free -g`, `lsmod`, `systemctl is-enabled libvirtd`.

Repository:

- `hosts-den/brys/default.nix` — `kdn.hw.gpu.vfio.use = true`, `iommu=pt` source.
- `modules/den/aspects/hw-gpu.nix` — the VFIO block: `vfio_pci`/`vfio`/`vfio_iommu_type1` initrd
  modules, `softdep amdgpu pre: vfio-pci`, and the `iommu=pt` kernel parameter with its comment
  that AMD needs no `amd_iommu=on`.
- `hosts-den/brys/llm.nix` — `MESA_VK_DEVICE_SELECT = "1002:7551!"`.
- `hosts-den/brys/performance.md` — load times (45 GB in ~105 s, 58.5 GB in ~129 s), ZFS read
  throughput (~2.0-2.2 GB/s cold, ~5.4-6.0 GB/s warm), PCIe topology, ARC cap.
- `hosts-den/brys/README.md` — the power-off fault.
- `modules/den/aspects/virt-microvm-host.nix`, `virt-microvm-guest.nix` — the existing microvm
  aspects and the `/nix/store` virtiofs share.
- `docs/tasks/2026-11/rocm-on-brys/definition.md` — the `gfx803` doorbell defect and the shim.
- `docs/tasks/2026-11/brys-kernel-7-zfs/definition.md` — why a newer host kernel buys nothing.
- `docs/tasks/2026-11/brys-r9700-model-fit/{definition,research,measurements}.md` — the served
  preset and its measured numbers.

microvm.nix (checked at the pinned `b7bd556`, 2026-10-29, and at `main` `194a254`, 2026-11-13):

- `nixos-modules/microvm/options.nix` — `microvm.devices`, `mem`, `balloon`, `hotplugMem`,
  `shares.*.{proto,dax}`, `virtiofsd.inodeFileHandles`, `deploy.installOnHost`, `deploy.sshSwitch`.
- `nixos-modules/microvm/pci-devices.nix` — the generated `pci-setup` script.
- `nixos-modules/host/default.nix` — the `pci-setup` unit.
- `lib/runners/cloud-hypervisor.nix` — `--device path=/sys/bus/pci/devices/<path>`; USB throws.
- `lib/runners/qemu.nix` — `-device vfio-pci,host=…,multifunction=on`, the `pcie-root-port`s, and
  `pcie=on` when PCI is required.
- Handbook: <https://microvm-nix.github.io/microvm.nix/microvm-options.html> and
  <https://microvm-nix.github.io/microvm.nix/devices.html>.
- README hypervisor restriction table (firecracker: no 9p/virtiofs; cloud-hypervisor: no 9p):
  <https://github.com/microvm-nix/microvm.nix>.

VFIO and RDNA4:

- cloud-hypervisor VFIO HOWTO — group rule, `--device`, migration requirements, "no virtual IOMMU":
  <https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/docs/vfio.md>.
- cloud-hypervisor v54 release notes — migratable VFIO only with a variant driver:
  <https://www.cloudhypervisor.org/blog/cloud-hypervisor-v54.0-released>.
- cloud-hypervisor issue #4375 (64 GB BAR, GPU, enumeration failure):
  <https://github.com/cloud-hypervisor/cloud-hypervisor/issues/4375>.
- cloud-hypervisor issue #6147 (BAR re-allocation failure):
  <https://github.com/cloud-hypervisor/cloud-hypervisor/issues/6147>.
- Single-GPU passthrough, RX 9070 XT (Navi 48, RDNA 4), CachyOS — D3cold fix, BAR2 resize, "do not
  pre-bind", "no reset bug on Navi 48", BIOS list:
  <https://gist.github.com/PhialsBasement/c34e908352bd2e8a49197edc70df2d94>.
- Qubes OS forum, "AMD R9700 GPU passthrough: advice?" — one working report, one failing with
  `MES(1) failed to respond to msg=SET_HW_RSRC`, and the separate-group observation:
  <https://forum.qubes-os.org/t/amd-r9700-gpu-passthrough-advice/42940>.
- AMD, "GPU passthrough on Proxmox VE" (2026) — ROCm + PyTorch validated end-to-end in a KVM guest;
  `/dev/kfd` and `rocminfo` inside the guest; `--no-dkms`. Search-index summary only: the page body
  did not load in this session.
  <https://www.amd.com/en/developer/resources/technical-articles/2026/gpu-passthrough-on-proxmox-ve.html>
- OpenNebula, "AMD GPU Passthrough" — Q35 and `host-passthrough` are required; PCIe atomics:
  <https://docs.opennebula.io/7.4/product/cluster_configuration/pci_passthrough_sriov/amd_gpu_passthrough>.
- ROCm, "How ROCm uses PCIe atomics" — routing bits in `DevCap2`:
  <https://rocm.docs.amd.com/en/docs-6.2.0/conceptual/More-about-how-ROCm-uses-PCIe-Atomics.html>.

Model sharing:

- virtio-fs vs virtio-9p `fio` numbers (single- and multi-queue, with and without DAX), qemu-devel
  2020: <https://lists.gnu.org/archive/html/qemu-devel/2020-12/msg03155.html>.
- "virtio-blk and virtio-fs are similar" thread, qemu-devel 2022 (virtio-blk much faster):
  <https://lists.nongnu.org/archive/html/qemu-devel/2022-07/msg04446.html>.
- virtiofsd issue #66, virtio-fs costs about twice the time of virtio-blk on the same workload:
  <https://gitlab.com/virtio-fs/virtiofsd/-/issues/66>.
- virtiofsd issue #121, too many open files on ZFS — the reason microvm.nix exposes
  `inodeFileHandles`: <https://gitlab.com/virtio-fs/virtiofsd/-/issues/121>.
- Proxmox forum, real-world virtiofs ~134-154 MB/s:
  <https://forum.proxmox.com/threads/i-want-to-like-virtiofs-but.164833>.
- virtio-fs project, DAX shares the host page cache and bypasses the guest cache:
  <https://virtio-fs.gitlab.io>.

## Related

- [research.md](research.md) — the raw probe output, the microvm.nix source walk, the throughput
  arithmetic, and the field reports in full.
- `docs/tasks/2026-11/rocm-on-brys/` — the `gfx803` defect this VM would hide. Read it; do not edit
  it from here.
- `docs/tasks/2026-11/brys-kernel-7-zfs/` — the ZFS kernel constraint the VM would escape.
- `docs/tasks/2026-11/brys-r9700-model-fit/` — the served preset and the numbers P4 must match.
- `docs/local-llms.md` — the deployed serving state (owned by another task).
