---
type: Research
description: Raw read-only probe output from brys, the microvm.nix VFIO source walk, the model-sharing throughput arithmetic, and the field reports that decide the R9700 passthrough risk.
task: definition.md
authored_by: agent
timestamp: 2026-11-19T12:00:00+01:00
---

# Evidence for and against the R9700 passthrough VM

Research for [definition.md](definition.md). Every brys number was read on 2026-11-19, kernel
`6.18.62`, with read-only commands. No VM was created, no VFIO binding was made, no host
configuration was changed, and the host was not rebooted.

## 1. The probe set

```sh
# identity and IOMMU state
uname -r; cat /proc/cmdline
ls -d /sys/class/iommu/*
journalctl -k -b --no-pager | grep -iE 'AMD-Vi|DMAR|IOMMU'

# groups, one line per group
for g in /sys/kernel/iommu_groups/*; do
  echo "group $(basename "$g"): $(ls "$g/devices" | tr '\n' ' ')"
done

# topology and device identity
lspci -Dnn; lspci -tv
for d in 0b:00.0 0c:00.0 0d:00.0 0d:00.1 0e:00.0 0e:00.1; do
  echo "$d -> group $(basename "$(readlink -f /sys/bus/pci/devices/0000:$d/iommu_group)")"
done

# reset, power, BARs, links
cat /sys/bus/pci/devices/0000:0d:00.0/reset_method
cat /sys/bus/pci/devices/0000:0d:00.0/{d3cold_allowed,power/control,power_state,resource}
sudo -n lspci -vv -s 00:03.1 | grep -E 'AtomicOps|DevCap2|LnkCap|LnkSta'
sudo -n lspci -vv -s 0d:00.0 | grep -E 'AtomicOps|DevCap2|LnkCap|LnkSta'
```

`sudo -n` was used only for `lspci -vv`, because the extended capability space (`DevCap2`, where the
PCIe atomics bits live, at offset 0x24 of the extended configuration space) is not readable by a
normal user. Everything else was read as the login user.

## 2. Raw output that matters

### 2.1 Kernel command line

```
initrd=\EFI\nixos\…-initrd-linux-6.18.62-initrd.efi
init=/nix/store/…-nixos-system-brys-26.11.20261106.296d5fa/init
zfs.zfs_arc_max=8589934592
transparent_hugepage=madvise
numa_balancing=disable
nohibernate
iommu=pt
plymouth.enable=0
consoleblank=90
root=fstab
loglevel=4
video=DP-4:e
drm.edid_firmware=DP-4:edid/PG278Q_120.bin
lsm=landlock,yama,bpf
vt.default_red=… vt.default_grn=… vt.default_blu=…
```

`iommu=pt` is present. `amd_iommu=on` is **absent and unnecessary**: an AMD part enables `amd_iommu`
by default, which is also what the comment in `modules/den/aspects/hw-gpu.nix` says ("An AMD part
turns `amd_iommu` on by default, so only Intel needs the parameter").

Note for any later experiment: this file is part of `hosts-den/brys/`, which this task must not
change. It is quoted here only as evidence.

### 2.2 AMD-Vi is active

```
AMD-Vi: Using global IVHD EFR:0x0, EFR2:0x0
iommu: Default domain type: Passthrough (set via kernel command line)
pci 0000:00:00.2: AMD-Vi: IOMMU performance counters supported
pci 0000:00:01.0: Adding to iommu group 0
…
pci 0000:00:03.1: Adding to iommu group 5
pci 0000:00:03.2: Adding to iommu group 6
…
```

`/sys/class/iommu/ivhd0` exists, which is the AMD IOMMU hardware unit. `EFR:0x0` is the global IVHD
extended-feature word; the kernel still reports performance counters, so the unit is functional. The
`iommu=pt` line proves the default domain is passthrough, which is the normal host setting for a
VFIO machine: host devices keep an identity mapping, and VFIO creates its own translating domain for
the group it owns.

### 2.3 The groups, in full

```
group 0:  0000:00:01.0
group 1:  0000:00:01.1
group 2:  0000:00:01.2
group 3:  0000:00:02.0
group 4:  0000:00:03.0
group 5:  0000:00:03.1              <- CPU root port, feeds [0b-0d]
group 6:  0000:00:03.2              <- CPU root port, feeds [0e]
group 7:  0000:00:04.0
group 8:  0000:00:05.0
group 9:  0000:00:07.0
group 10: 0000:00:07.1
group 11: 0000:00:08.0
group 12: 0000:00:08.1
group 13: 0000:00:14.0 0000:00:14.3
group 14: 0000:00:18.0 … 0000:00:18.7
group 15: 0000:01:00.0              <- nvme0n1
group 16: 0000:02:00.0              <- X570 uplink
group 17: 0000:03:01.0
group 18: 0000:03:03.0
group 19: 0000:03:04.0
group 20: 0000:03:05.0
group 21: 0000:03:08.0 0000:08:00.0 0000:08:00.1 0000:08:00.3
group 22: 0000:03:09.0 0000:09:00.0
group 23: 0000:03:0a.0 0000:0a:00.0
group 24: 0000:04:00.0              <- nvme1n1
group 25: 0000:05:00.0
group 26: 0000:06:00.0
group 27: 0000:07:00.0
group 28: 0000:0b:00.0              <- R9700 card switch, upstream port
group 29: 0000:0c:00.0              <- R9700 card switch, downstream port
group 30: 0000:0d:00.0              <- R9700 GPU
group 31: 0000:0d:00.1              <- R9700 HDMI audio
group 32: 0000:0e:00.0 0000:0e:00.1 <- Lexa GPU + audio
group 33: 0000:0f:00.0
group 34: 0000:10:00.0
group 35: 0000:10:00.1
group 36: 0000:10:00.3
group 37: 0000:10:00.4
```

### 2.4 The topology behind it

```
+-03.1-[0b-0d]----00.0-[0c-0d]----00.0-[0d]--+-00.0  Navi 48 [Radeon AI PRO R9700]  (1002:7551)
|                                            \-00.1  Navi 48 HDMI/DP Audio        (1002:ab40)
+-03.2-[0e]--+-00.0  Lexa PRO                    (1002:699f)
             \-00.1  Baffin HDMI/DP Audio        (1002:aae0)

0000:0b:00.0  PCI bridge  [0604]: AMD/ATI Navi 10 XL Upstream Port of PCI Express Switch
0000:0c:00.0  PCI bridge  [0604]: AMD/ATI Navi 10 XL Downstream Port of PCI Express Switch
```

The two "Navi 10 XL" bridges are **not** on the motherboard. They are the R9700's own PCIe switch:
the card presents an upstream port, a downstream port, and then the GPU and its audio function. The
Lexa is on a *different* CPU root port (`00:03.2`) with no bridge in between.

This is the single most important correction to the task's premise. The premise said "it shares
bridges with the Lexa in the topology — this may be the fatal blocker". It does not:

- the R9700's bridges are inside the R9700, and each sits in its own IOMMU group (28, 29);
- the Lexa is behind a different root port and shares group 32 only with its own audio;
- the kernel has already split the R9700's two functions into groups 30 and 31, so passing
  `0d:00.0` alone is legal.

A practical consequence of the split: the audio function `0d:00.1` has **no** `reset_method`, while
`0d:00.0` has `flr`. Leaving the audio function on the host therefore avoids the one device in the
pair that cannot be reset.

### 2.5 Reset, power and BARs

```
0d:00.0: reset_method=[flr bus]   driver=amdgpu
0d:00.1: reset_method=[n/a]       driver=snd_hda_intel
0e:00.0: reset_method=[bus]       driver=amdgpu
0b:00.0: reset_method=[bus]       driver=pcieport
0c:00.0: reset_method=[bus]       driver=pcieport

d3cold_allowed = 1
power/control  = auto
power_state    = D0

BAR0 0x0000007000000000-0x00000077ffffffff  -> 32 GiB   (ReBAR on)
BAR1 unused
BAR2 0x0000007800000000-0x000000780fffffff  -> 256 MiB
BAR4 0x000000000000f000-0x000000000000f0ff  -> 256 B     (MSI-X table)
BAR5 0x00000000fcc00000-0x00000000fcc7ffff  -> 512 KiB
BAR6 0x00000000fcc80000-0x00000000fcc9ffff  -> 128 KiB
```

`reset_method` is the kernel's ordered list: try FLR first, then a secondary bus reset. FLR exists
for the GPU function, so QEMU/libvirt can reset the card between guest boots without a host reboot —
in principle. The definition's P2 exists because "reported" is not "works".

`d3cold_allowed = 1` with `power/control = auto` is the D3cold trap described in section 5.

The 32 GiB BAR0 is the mechanical risk. A guest PCI allocator must place a 32 GiB 64-bit BAR, so the
guest needs a 64-bit MMIO window larger than 32 GiB. This is not exotic (a GPU with 32 GB of VRAM
has this shape), but it is the step where passthrough usually fails on a minimal VMM.

### 2.6 Links and atomics

```
00:03.1  LnkCap: Speed 16GT/s, Width x8     LnkSta: Speed 2.5GT/s, Width x8
0b:00.0  LnkCap: Speed 32GT/s, Width x16    LnkSta: Speed 2.5GT/s (downgraded), Width x8 (downgraded)
0c:00.0  LnkCap: Speed 32GT/s, Width x16    LnkSta: Speed 32GT/s, Width x16
0d:00.0  LnkCap: Speed 32GT/s, Width x16    LnkSta: Speed 32GT/s, Width x16
00:03.2  LnkCap: Speed 16GT/s, Width x8     LnkSta: Speed 8GT/s, Width x8
0e:00.0  LnkCap: Speed 8GT/s,  Width x8     LnkSta: Speed 8GT/s, Width x8

00:03.1  DevCap2: AtomicOpsCap: Routing+ 32bit+ 64bit+ 128bitCAS-
                  AtomicOpsCtl: ReqEn- EgressBlck-
0d:00.0  DevCap2: AtomicOpsCap: 32bit+ 64bit+ 128bitCAS-
                  AtomicOpsCtl: ReqEn+
```

Two readings:

1. **The host link is Gen4 x8.** `LnkCap` on `00:03.1` is 16 GT/s x8. The 2.5 GT/s `LnkSta` is idle
   link-speed management, not a downgrade: the card was idle. This matches
   `hosts-den/brys/performance.md` ("R9700 `0d:00.0` · PCIEX16_1 · CPU Gen4 x8"). The card's
   internal `0c → 0d` link is Gen5 x16, so the card is not the narrow part; the slot is.
2. **PCIe atomics are supported end to end.** ROCm needs atomic routing on AMD platforms, and the
   root port reports `Routing+ 32bit+ 64bit+`. `128bitCAS-` is normal on a consumer root complex
   and ROCm does not require it. This removes atomics from the risk list.

### 2.7 Host state at probe time

```
vfio_pci             20480  0
vfio_pci_core       102400  1 vfio_pci
vfio_iommu_type1     53248  0
vfio                 81920  3 vfio_pci_core,vfio_iommu_type1,vfio_pci
amdgpu            16117760  4

libvirtd.service: enabled, inactive
virsh -c qemu:///system list --all: (empty)

Mem: 125 GiB total, 13 GiB used, 65 GiB free, 48 GiB buff/cache, 112 GiB available
```

The VFIO modules are already loaded because brys sets `kdn.hw.gpu.vfio.use = true`. With
`kdn.hw.gpu.vfio.gpuIDs` left at its default `[]`, no `vfio-pci.ids=` kernel parameter exists, so
nothing is claimed at boot. That is the correct starting point: the card stays with `amdgpu` until a
guest asks for it.

## 3. The microvm.nix VFIO source walk

Checked at the revision this repository pins (`b7bd556974fa8a171b5b639200e81d52244dfde4`,
2026-10-29) and at `main` (`194a254693f49af939a2b53d04982bd4b276fdb3`, 2026-11-13). The VFIO files
are identical in both.

### 3.1 The option

```nix
# nixos-modules/microvm/options.nix
devices = mkOption {
  description = "PCI/USB devices that are passed from the host to the MicroVM";
  default = [];
  type = with types; listOf (submodule {
    options = {
      bus = mkOption { type = enum [ "pci" "usb" ]; … };
      path = mkOption { type = str; … };
      qemu = { id, bus, deviceExtraArgs };   # QEMU-only extras
    };
  });
};
```

### 3.2 The generated host-side setup

```nix
# nixos-modules/microvm/pci-devices.nix
microvm.binScripts.pci-setup = lib.mkIf (pciDevices != []) (''
  set -eou pipefail
  ${pkgs.kmod}/bin/modprobe vfio-pci
'' + lib.concatMapStrings ({ path, ... }: ''
  cd /sys/bus/pci/devices/${path}
  if [ -e driver ]; then
    echo ${path} > driver/unbind
  fi
  echo vfio-pci > driver_override
  echo ${path} > /sys/bus/pci/drivers_probe
'' + ''
  [[ -e iommu_group ]] || exit 1
  VFIO_DEV=$(basename $(readlink iommu_group))
  echo "Making VFIO device $VFIO_DEV accessible for user"
  chown microvm:kvm /dev/vfio/$VFIO_DEV
'') pciDevices);
```

`nixos-modules/host/default.nix` runs it as a unit: `ConditionPathExists =
"${stateDir}/%i/current/bin/pci-setup"`, `ExecStart = "${stateDir}/%i/current/bin/pci-setup"`.

What the script **does**: unbind the current driver, override it, probe, hand the VFIO node to the
VMM user.

What it **does not do**, and brys needs:

- `d3cold_allowed = 0` and `power/control = on` before the unbind (section 5);
- a BAR2 resize (only needed by the Windows driver, not by Linux).

`microvm.preStart` is the documented hook to add the D3 pin before `pci-setup`.

### 3.3 What the runners pass

```nix
# lib/runners/cloud-hypervisor.nix
lib.concatStringsSep " " (arg "--device" (map ({ bus, path, ... }: {
  pci = "path=/sys/bus/pci/devices/${path}";
  usb = throw "USB passthrough is not supported on cloud-hypervisor";
}.${bus}) devices))

# lib/runners/qemu.nix
# PCI required by vfio-pci for PCI passthrough
pciInDevices = lib.any ({ bus, ... }: bus == "pci") devices;
requirePci = graphics.enable || (! lib.hasPrefix "microvm" machine) || shares != [] || pciInDevices;
# machineOpts, for -M microvm:  pcie = if requirePci then "on" else "off"
…
"-device" "vfio-pci,host=${path},multifunction=on${optionalString (qemu.deviceExtraArgs != null) ",${qemu.deviceExtraArgs}"}"
# and before that:  "-device" "pcie-root-port,id=${id}…"
```

So the QEMU runner can do passthrough on both `-M microvm,pcie=on` and `-M q35`. `q35` is the shape
every RDNA4 and AMD document uses, so it is the one to use first.

### 3.4 The hypervisor restriction table

From the project README:

| Hypervisor | Restrictions |
| --- | --- |
| `qemu` | — |
| `cloud-hypervisor` | no 9p shares |
| `firecracker` | no 9p/virtiofs shares (and no PCI: virtio-MMIO only) |
| `crosvm` | 9p shares broken |
| `kvmtool` | no virtiofs shares, no control socket |
| `stratovirt` | no 9p shares, no control socket |
| `alioth` | no 9p shares, no control socket |
| `vfkit` | macOS only, no 9p shares, no tap/bridge networking |

`firecracker` is therefore **not** an option for a GPU: it has no PCIe bus to assign a device onto.

### 3.5 Memory behaviour that matters

- `microvm.mem` — "Amount of RAM in megabytes", a positive integer, default 512. A fixed
  reservation.
- `microvm.balloon` — default **false**. The description warns that on QEMU, cloud-hypervisor and
  crosvm it also enables free page reporting.
- `microvm.hotplugMem` / `hotpluggedMem` — default **0** (virtio-mem).
- `microvm.hugepageMem` — default false, cloud-hypervisor only.

The defaults are the correct settings for a guest with a passed-through device: a page the guest
reports as free must not be returned to the host while the device can still DMA to it. Any change to
these three options must be justified against that rule.

### 3.6 The share options

- `microvm.shares.*.proto` — `"9p"` (default) or `"virtiofs"`.
- `microvm.shares.*.dax` — "Enable DAX for this virtiofs share, letting the guest map file contents
  directly from the host's page cache. … Only `alioth` and `crosvm` support this. virtiofsd cannot
  do DAX."
- `microvm.shares.*.cache` — `auto | always | metadata | never`, guest-side, virtiofs only.
- `microvm.virtiofsd.inodeFileHandles` — default `"prefer"`, with the text "Allows you to overwrite
  default behavior in case you hit 'too many open files' on eg. ZFS" and a link to virtiofsd
  issue #121.

DAX is the option that would make virtiofs cheap for a 62 GB model, and it is unavailable on the two
hypervisors this task can use. That single fact drives the model-sharing decision.

### 3.7 The deploy story

- `microvm.deploy.installOnHost` — "Evaluate this MicroVM to a derivation, copy it to the target
  host, build the MicroVM runner on the target host, install/update the MicroVM on the host", then
  `systemctl restart microvm@$HOSTNAME.service`.
- `microvm.deploy.sshSwitch` — "Instead of restarting a MicroVM for an update, perform it via SSH.
  The host's `/nix/store` must be mounted."
- The repository's `virt-microvm-guest` aspect already mounts the host `/nix/store` read-only over
  virtiofs at `/nix/.ro-store`, so `sshSwitch` applies.

That is the whole `nixos-rebuild` answer: the guest is a NixOS configuration in this flake, the host
flake builds it, and `microvm@<guest>.service` is the lifecycle.

## 4. Model sharing: the arithmetic

### 4.1 What the guest must read

| Model | Quant | Size on disk | Shards |
| --- | --- | ---: | ---: |
| Qwen3.8-Flash-Next | `UD-IQ1_S` | **62 GB** | 3 |
| GLM-5.3-Flash 321B | `UD-IQ2_XXS` | **102 GB** | 4 |

Both go through `llama.cpp` with `--fit off` and `mmap`. The expert tensors stay in RAM and the CPU
computes them, so essentially the whole file is read by the guest.

### 4.2 The measured host baseline

From `hosts-den/brys/performance.md` (manual `llama-server`, `mmap`, threads 12, one model at a
time):

| Model | File | Load | Effective read rate |
| --- | ---: | ---: | ---: |
| `qwen3-coder-next` | 45 G | ~105 s | ~430 MB/s |
| `qwen3-next-80b` | 46 G | ~99 s | ~465 MB/s |
| `gpt-oss-120b` | 58.5 G | ~129 s | ~450 MB/s |

So a 62 GB model costs about **135 s** on the host today. The limit is not the ZFS device (measured
~2.0-2.2 GB/s cold at high queue depth) but the mmap page-fault pattern, which is closer to serial.

This is the number a guest must match. A share that reads at 2 GB/s does not automatically load a
model in 31 s, because the consumer is still faulting pages; but a share that reads at 0.4 GB/s is
strictly worse than the host.

### 4.3 The four mechanisms

| Mechanism | Cache copies | Measured or sourced rate | Notes |
| --- | --- | ---: | --- |
| **virtio-blk, zvol, `cache=none`** | 1 | ~2.0 GB/s cold (brys NVMe+ZFS measured) | one page cache; matches `mmap` |
| virtiofs, `virtiofsd`, no DAX | **2** | 650 MB/s single-queue, 2.5 GB/s multi-queue (qemu-devel 2020); 134-154 MB/s real 4k/1M (Proxmox 2025) | FUSE; guest + host both cache |
| virtio-9p | 2 | ~397 MB/s multi-queue, ~98 MB/s single-queue (same source) | legacy; worst semantics |
| NFS over virtio-net | 2 | TCP-bound; loopback NFS is fast but adds a copy and a daemon | no advantage over block |

The qemu-devel numbers (2020, `fio`, sequential read, ramfs backing) are the cleanest same-host
comparison available:

```
9p-none          seqread-psync-multi  397.6 MB/s
vtfs-none        seqread-psync-multi  360.0 MB/s
vtfs-auto        seqread-psync-multi 2530.7 MB/s
vtfs-auto-dax    seqread-psync-multi 2423.9 MB/s
vtfs-always-dax  seqread-psync-multi 2406.1 MB/s
```

The lesson is in the first two lines: **without DAX, virtiofs is no faster than 9p on a single
queue**, and only multi-queue pulls it to 2.5 GB/s. microvm.nix defaults `virtiofsd.threadPoolSize`
to `` `nproc` ``, so brys would get the multi-queue shape — but never DAX.

### 4.4 Why two copies is fatal here

A 62 GB model in a guest over virtiofs means ~62 GB in the guest page cache **and** up to 62 GB in
the host page cache (the ZFS ARC is separately capped at 8 GiB). On a 125 GiB host that is 124 GiB
before the guest's KV cache. The kernel will evict, and every eviction turns into a re-read through
FUSE, which is the slowest path in the system. For the 102 GB model it cannot work at all.

A block device has exactly one cache: the guest's. That is also the cache `mmap` wants.

### 4.5 The RAM ceiling

| Guest workload | Guest RAM | Host left of 125 GiB | Comment |
| --- | ---: | ---: | --- |
| flash-next `UD-IQ1_S` (62 GB) + 64k KV | ~72 GiB | ~53 GiB | fits with room |
| GLM-5.3-Flash `UD-IQ2_XXS` (102 GB) | ~112 GiB | ~13 GiB | desktop + 8 GiB ARC + qemu compete |
| both at once | ~120 GiB | ~5 GiB | no |

Today the host gives the whole page cache to whichever model is resident, which is why the 102 GB
GLM row exists at all. A VM trades that flexibility for isolation. That is the honest cost, and it
is the reason the definition does not recommend moving the served stack yet.

## 5. The D3cold trap, in the source's own words

From the field-tested RDNA4 guide (RX 9070 XT, Navi 48 — the same silicon family as the R9700's
Navi 48):

> **What causes it.** When `amdgpu` unbinds from the GPU, the kernel's runtime PM + ACPI drops the
> card into D3cold within ~1 second. In D3cold, the PCIe config space returns `0xFFFF` — the device
> is electrically powered off. When `vfio-pci` tries to bind or QEMU tries to access it, it reads
> `0xFFFF` everywhere and reports "stuck in D3."
>
> **The fix: lock the GPU in D0 before unbinding.**
> ```
> echo 0 > /sys/bus/pci/devices/$GPU/d3cold_allowed
> echo "on" > /sys/bus/pci/devices/$GPU/power/control
> ```

brys matches the precondition exactly: `d3cold_allowed = 1`, `power/control = auto`, and the card is
idle at `D0` when no model is loaded.

Three more statements from the same guide, each with a consequence for brys:

| Claim | Consequence |
| --- | --- |
| "No reset bug on Navi 48 (unlike RDNA 1-3). The card resets cleanly via PSP on kernel ≥ 6.13." | Plausible and matches the `flr` we measured, but a Proxmox thread reports an "RX 9070 reset bug", so it needs P2. |
| "Do NOT pre-bind the GPU to `vfio-pci` at boot … let `amdgpu` own the card at boot, then hand it to `vfio-pci` at VM start." | brys already behaves this way: `softdep amdgpu pre: vfio-pci` orders module load but no `vfio-pci.ids=` exists. microvm.nix's `pci-setup` also unbinds at start. |
| "Do NOT use `disable_idle_d3=1`. It makes D3 issues worse on Navi 48." | Do not copy the common `disable_idle_d3=1` advice from older AMD guides. |

And the failure mode that costs a host reboot:

> **`virsh destroy` while the GPU is active** — force-kills QEMU mid-operation, corrupts the GPU's
> SMU firmware. The card becomes completely unresponsive … Only a host **reboot** recovers it.
> **Always shut down from inside** the guest.

That is the cost the definition lists under "a wedged guest GPU". On brys a host reboot can mean 20-60
minutes of downtime.

## 6. Field reports on the R9700 itself

### 6.1 One success, one failure

Qubes OS forum thread "AMD R9700 GPU passthrough: advice?" (14 posts, 2026-08):

- **Success**, quoted by the failing user: "I use the R9700 for AI inference, using the amd + vulkan
  drivers, and that works in Qubes OS with PCIe passthrough." That is a **Vulkan/amdgpu** report, not
  a ROCm one, and Qubes uses Xen, not KVM.
- **Failure**: PowerColor R9700 on a Gigabyte B850 AI TOP, Ryzen 9950X3D. "With any kernel
  configuration I try, the result is the same: at boot, `MES(1) failed to respond to msg=SET_HW_RSRC`."
  Four dom0 kernels, two guest kernels, Debian 13 / Fedora 44 / Ubuntu 24.04 templates, and VM-local
  kernels. The same hardware "is stable and functions well in an unvirtualized installation of
  Ubuntu 24.04. So the issue I have in Qubes is in the passthrough."
- The same user independently found that the VGA and audio functions of the R9700 are in **different
  IOMMU groups**, and concluded the audio need not be passed. That matches brys exactly.

This is the honest state of the art: **the R9700 in a VM is reported working by one person and
failing by another, on different hypervisors, and nobody has published a KVM + ROCm + R9700
walkthrough.** P1 is the only way to know for this board.

### 6.2 AMD's own KVM guidance

AMD published "GPU passthrough on Proxmox VE" in 2026 and states that ROCm and PyTorch were
validated end-to-end in a KVM/QEMU guest with a passed-through Radeon, on both an integrated and a
discrete GPU. The useful specifics:

- `/dev/kfd` and the DRM render nodes appear in the guest from the guest's own in-kernel `amdgpu`
  driver; ROCm userspace then talks to the kernel driver.
- `--no-dkms` for the ROCm install: the guest kernel's `amdgpu` is the driver, no out-of-tree module.
- For an **integrated** GPU, a guest-side driver crash during teardown (`gmc_v11_0_sw_fini`) needs a
  **host** reboot; for a discrete GPU a guest reboot is enough. brys has a discrete card, so the
  cheaper recovery applies.

Caveat: the page body did not load in this session (two attempts timed out). The claims above come
from the search index of that page. Treat them as a lead, not as a verified quotation, and re-read
the page before P1.

### 6.3 The OpenNebula requirement

OpenNebula's "AMD GPU Passthrough" page states that **Q35 and `host-passthrough` are both required**:
"Q35 provides the PCIe topology used to expose atomic operation capabilities. `host-passthrough`
exposes the AVX and AVX2 CPU instructions required by ROCm libraries." brys's 5950X has AVX2 and no
AVX-512, so `-cpu host` is both sufficient and necessary.

This is the concrete reason the definition prefers `microvm.qemu.machine = "q35"` over the default
`microvm` machine type.

### 6.4 Large BARs are where passthrough breaks

- cloud-hypervisor issue #4375: a GPU with a 64 GB BAR ("BAR 3:: mem64 … 0x1000000000 (64 GB)")
  failed PCI enumeration in the guest on both direct-kernel and hypervisor-fw boot: "PCI enumeration
  fails in the same way with an allocation from 4g-5g, which doesn't even make sense, as it crosses
  the 32→64 bit boundary."
- cloud-hypervisor issue #6147: "Failed moving device BAR: failed allocating new MMIO range" on an
  Nvidia passthrough.
- The CachyOS RDNA4 guide needed `-fw_cfg opt/ovmf/X-PciMmio64Mb,string=65536` to get a 64 GiB
  64-bit MMIO window for a 16 GiB BAR0, and states "Without this, ReBAR collapses to 256 MiB
  in-guest."

The R9700's BAR0 is **32 GiB**, twice the 9070 XT's. A guest MMIO window of at least 64 GiB is the
minimum, and 128 GiB is the safe choice. This is the single most likely mechanical failure in P1.

## 7. ROCm in a guest: why it should work, from the defect's own chain

The `rocm-on-brys` task shows the whole chain, so the guest conclusion can be derived rather than
guessed:

1. `kfd_topology.c` sets `HSA_CAP_DOORBELL_TYPE_1_0` for `CHIP_POLARIS10/11/12` and `CHIP_FIJI`, and
   `2_0` for everything from gfx9 on.
2. `amd_gpu_agent.cpp:124` throws a generic `HSA_STATUS_ERROR` when a node has doorbell type ≠ 2.
3. `DiscoverGpu` only tolerates `HSA_STATUS_ERROR_INVALID_ISA`, so the throw kills `hsa_init()` for
   the whole machine.
4. A guest with only `0d:00.0` has one GPU node. Its `gfx_target_version` is `120001` and its
   capability word decodes to doorbell type 2. The `if` never fires.

Therefore: **stock ROCm 7.2.4 in the guest needs no patch and no `LD_PRELOAD`.** The Linux kernel is
not the variable — the host already runs 6.18 and the guest can run the same one. This is the
cleanest argument in favour of the VM, and P1 measures it directly (`rocminfo` should list
`gfx1201` and no `gfx803`).

One residual risk: the guest must be able to load the `amdgpu` firmware for `gfx1201` from
`linux-firmware`. That comes from the guest's nixpkgs, so it is not affected by the host's ZFS
constraint.

## 8. Why the newer-kernel argument does not carry

`docs/tasks/2026-11/brys-kernel-7-zfs/` already answers this for the host. The parts that apply to a
guest:

- nixpkgs carries only **7.3** in the 7.x line; 7.0, 7.1 and 7.2 are removed with `throw` entries.
- No released OpenZFS supports 7.3 (2.4.4 and 2.3.9 stop at 7.2), and 7.2 is **EOL** since
  2026-11-01.
- The host already drives the card at 6.18.62: every downloaded model ran over Vulkan.
- `gfx1201` is new on the **ROCm** side, not on the kernel side; AMD's own matrix tops out at kernel
  6.17, so 6.18 is above the newest validated kernel, not below the oldest.

A guest does remove the ZFS coupling, so it can pick any kernel the host flake can build. That is a
real capability. It is not a present need, and the definition says so.

## 9. What the tests must prove, stated as numbers

| Step | Number to beat | Why that number |
| --- | --- | --- |
| P1 | `rocminfo` lists `gfx1201`, and `grep -c gfx803` returns 0 | the whole section-2 argument |
| P2 | 5/5 start-stop cycles | the definition of "the card resets" |
| P3 | ≥ 1.5 GB/s read; 62 GB load ≤ 120 s | the host baseline is ~135 s; a slower share is a regression |
| P4 | ≥ 20.8 t/s decode, ≥ 242 t/s prefill | 5 % of the measured host 21.9 / 255-289 |
| P5 | API back after `systemctl restart microvm@llm`, no host reboot | the availability claim |

A fail at P1 or P4 ends the idea. A fail at P3 means "use a zvol". A fail at P2 means the host
reboot coupling is unchanged and the strongest argument for the VM disappears.

## Sources not already cited in the definition

- qemu-devel, virtio-fs vs virtio-9p benchmark numbers:
  <https://lists.gnu.org/archive/html/qemu-devel/2020-12/msg03155.html>
- virtiofsd issue #121 (ZFS open files): <https://gitlab.com/virtio-fs/virtiofsd/-/issues/121>
- Qubes OS forum thread: <https://forum.qubes-os.org/t/amd-r9700-gpu-passthrough-advice/42940>
- Proxmox forum, "AMD RX 7800/9070 XT vendor-reset?" (RDNA2/RDNA4 may reset, RDNA3 hard):
  <https://forum.proxmox.com/threads/amd-rx-7800-9070-xt-vendor-reset.179010>
- Void Linux issue #56829, "since linux 6.15 kernel AMD reset bug back again (RDNA 3 VFIO
  single-gpu passthrough)": <https://github.com/void-linux/void-packages/issues/56829>
- ArchWiki, "PCI passthrough via OVMF" (root ports and bridges must not be bound to vfio at boot):
  <https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF>
