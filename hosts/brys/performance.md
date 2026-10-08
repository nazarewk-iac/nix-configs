---
type: Reference
description: brys hardware and performance reference — CPU/RAM, motherboard and PCIe/M.2 topology, GPUs, the ZFS mirror and LUKS layout, measured NVMe read throughput, the ZFS ARC cap, measured memory bandwidth, and per-model resident footprints.
timestamp: 2026-10-08T02:22:28+02:00
---

# brys performance

Hardware inventory and measured performance of **brys** (Ryzen 9 5950X
workstation, 128 GB DDR4). The model-serving configuration, the boot
specialisations and the deployment state are in
[docs/local-llms.md](../../docs/local-llms.md); this file holds only the
hardware and the measurements.

## CPU and RAM

AMD Ryzen 9 5950X, 16 cores / 32 threads, one NUMA node, 64 MiB L3
(2 x 32 MiB), 8 MiB L2, boost to 5086 MHz. 128 GB DDR4, 125 GiB usable, no
swap.

## Motherboard and PCIe / M.2 topology

ASUS ROG Strix X570-E Gaming WiFi II (X570S, passive chipset). `lspci -tv`
confirms:

| device | slot | link | root port |
|---|---|---|---|
| `nvme0n1` (Goodram PX700 2 TB) | M.2_1 | CPU Gen4 x4 | `00:01.1` |
| `nvme1n1` (Viper VP4300L 2 TB) | M.2_2 | chipset Gen4 x4 | `00:01.2` → `02:00.0` |
| W6600 `0d:00.0` | PCIEX16_1 | CPU Gen4 x8 | |
| Radeon 550 "Lexa" `0e:00.0` | PCIEX16_2 | CPU Gen4 x8 | |

`nvme1n1` sits behind the X570 uplink (`00:01.2` → `02:00.0`). That PCIe 4.0 x4
link is shared with the MT7921K Wi-Fi, the RTL8125 2.5GbE, the I211 GbE, the
chipset USB, and the chipset SATA. The GPUs use CPU lanes. BIOS 5013 (2024-03;
latest 5044).

**Known issues, relevant and not.** There is no chipset fan: this is the passive
X570S, so the fan complaints belong to the older X570-E. The USB-dropout root
cause is fixed by AGESA 1.2.0.2, and brys is newer. The Wi-Fi/BT (MediaTek
MT7921K) driver issues are mostly on Windows. brys shows no PCIe AER errors.

## GPUs

| PCI | device | id | VRAM |
|---|---|---|---|
| `0d:00.0` | Radeon PRO W6600 (RADV NAVI23) | `1002:73e3` | 7.98 GiB (`8573157376` B) |
| `0e:00.0` | Lexa PRO (Radeon 540/550) | `1002:699f` | 4.00 GiB (`4294967296` B) |

`MESA_VK_DEVICE_SELECT=1002:73e3!` pins the W6600 as `Vulkan0`; the Lexa is
never selected. The W6600 is unusable for the dense model weights, but it runs
the Qwen MTP draft head — see [docs/local-llms.md](../../docs/local-llms.md),
"GPU draft head".

## Storage: ZFS mirror and LUKS

Two NVMe devices hold the pool. Two SATA HDDs and a USB stick are not part of
it.

| device | size | model |
|---|---|---|
| `nvme0n1` | 1.9 T | SSDPR-PX700-02T-80 |
| `nvme1n1` | 1.8 T | Viper VP4300L 2TB |

Both are LUKS2-encrypted (`px700-brys-crypted`, `vp4300-brys-crypted`) and form
a **2-device mirror**:

```
brys-main (ONLINE, 1.81 T, 1006 G alloc, 850 G free, 51% frag)
  mirror-0
    dm-...-px700-brys-crypted   ONLINE
    dm-...-vp4300-brys-crypted  ONLINE
```

The model dataset is `brys-main/brys/impermanence/usr/data` (735 G used,
793 G avail), mounted at `/nix/persist/usr/data` and persisted to
`/var/lib/kdn/llms/models`. Properties: `recordsize 128K`, `compression lz4`,
`primarycache all`, `atime on`, `sync standard`, `logbias latency`,
`direct standard`, `special_small_blocks 0`.

## Measured NVMe / ZFS read throughput

Measured 2026-10-08 (corrected). The first numbers were wrong. The `fio` job
capped the queue depth to 1 (QD1/psync), so it measured per-request latency,
not the drive. Re-measured with **asynchronous high queue depth** (`fio
io_uring`, `iodepth=64`, `numjobs=4`, `bs=128k`, `--direct=1`) on a 32 GiB
incompressible scratch file after `drop_caches`:

| read | throughput |
|---|---|
| cold sustained, per drive | **~2.0–2.2 GB/s** |
| warm band, per drive, at ~800–900 G LBA | **~5.4–6.0 GB/s** |
| mirror dataset, warm | **~10 GB/s** |

The advertised rate is 7,400 MB/s. 1M blocks are worse than 128k. **dm-crypt is
not the cap:** `cryptsetup benchmark` gives aes-xts ~4.8 GB/s, above the cold
sustained rate. The earlier **~1.08 GB/s was a QD1/psync artifact**. The ARC
stayed far below the 8 GiB cap, so the read is **device-bound, not ARC-bound**.
Disk offload is viable at these speeds.

**The ~2 GB/s cold figure is the genuine folded-flash read speed, not a fault.**
These drives fold TLC/QLC into a pSLC cache. The pSLC cache serves the warm band
(~5.4–6.0 GB/s); a cold read past the cache runs at the native TLC/QLC rate
(~2 GB/s). The advertised 7,400 MB/s is the pSLC burst only. Both drives are
DRAM-less, MAP1602-based, on YMTC 232-layer NAND, and reached about 72 °C under
sustained read. Recommendations: improve drive cooling; reconsider DRAM-less
QLC for a scrub-heavy ZFS mirror; and benchmark with asynchronous high queue
depth (a QD1/psync test measures latency, not the drive).

## ZFS ARC cap

`hosts/brys/llm.nix` caps the ZFS ARC at 8 GiB with the kernel parameter
`zfs.zfs_arc_max=8589934592`. The ARC is a *second* cache beside the Linux page
cache that backs the `mmap`'d model weights. At its default `c_max` (about half
of RAM) it grew to ~65 GB and the kernel evicted the weights to make room. The
cap keeps the weights resident. It is a kernel module parameter, so it applies
on a **cold boot** only (a `switch` does not apply it); to apply it live:

```bash
echo 8589934592 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
```

The serving-side effect and the measured context ladder are in
[docs/local-llms.md](../../docs/local-llms.md), "ZFS ARC quirk".

When a model runs on the main `brys` profile and shares the box with the
desktop, the tested RAM levers are in
[docs/local-llms.md](../../docs/local-llms.md), "Freeing RAM when colocating a
model with a workstation".

## Measured memory bandwidth

Real RAM throughput measured via a STREAM-style benchmark compiled for `znver3`
and run on brys under the `performance` governor (2026-09-05). This supersedes
the earlier *assumed* DDR4 figure of ~50 GB/s.

| op | MiB working set | GB/s |
|---|---|---|
| COPY | 4096 | 39.80 |
| TRIAD | 4096 | 27.90 |
| ADD | 4096 | 26.74 |
| SCALE | 4096 | 24.20 |
| COPY | 320 | 38.81 |

Implication for the tok/s ceiling: CPU decode reads activated weights
sequentially, so **COPY (~40 GB/s)** is the right figure. DeepSeek V4 Flash
IQ3_XXS reads ~5 GB of activated params per token, so the realistic ceiling is
**~8 tok/s** (was ~9–10 from the assumed 50 GB/s). The 6.25 tok/s best reaches
~78% of the real hardware ceiling.

## Measured per-model resident footprints

Each model loaded via a manual `llama-server` (llama.cpp 10408, `mmap`, threads
12) one at a time on the 128 GB box (DeepSeek router also resident for the small
models). Resident working set = `VmRSS` = `RssAnon` (compute/KV buffers) +
`RssFile` (mmap'd weights). `warm t/s` = 128-token generation.

| model | file | VmRSS | RssAnon | RssFile | VmPeak | load | warm t/s | coexist w/ DS4? |
|---|---|---|---|---|---|---|---|---|
| `phi-4` | 8.5 G | 17.7 G | 8.9 G | 8.7 G | 23 G | ~18 s | 2.86 | yes (fits; evicts little) |
| `qwen3-30b-a3b` | 18 G | 44.4 G | 26.4 G | 18.0 G | 50 G | ~42 s | 11.41 | partial (evicts ~45 G of DS4 cache) |
| `qwen3-coder-next` | 45 G | 65.6 G | 39.6 G | 25.9 G | 91 G | ~105 s | 5.34 | no (fully evicts DS4) |
| `qwen3-next-80b` | 46 G | 80.0 G | 39.2 G | 40.8 G | 94 G | ~99 s | 3.29 | no (fully evicts DS4) |
| `qwen3-235b` | 72 G | (fail) ~100 G est | — | — | — | fail @65 G avail | — | no (needs box alone) |
| `gpt-oss-120b` (Q4_K_M) | 58.5 G | 72.2 G | 60.2 G | 11.8 G | 128 G | ~129 s | **12.7** | yes (fits; DS4 file-cache evicted, re-faults) |

Multi-model implication: `models-max=1` (one resident at a time) is the right
policy on 128 GB. Only `phi-4` (17.7 G) fits comfortably alongside DeepSeek;
`qwen3-30b` (44.4 G) fits but evicts ~45 G of DS4's weight cache (DS4 re-reads
from disk on next use). Every 45 G+ MoE fully evicts DS4 and needs the box to
itself. This is why the topology splits into two routers — see
[docs/local-llms.md](../../docs/local-llms.md), "N-router topology and
routing".

## To test later (no changes yet)

- Update BIOS 5013 → 5044.
- Monitor NVMe temperatures under load.
- Keep the drive you care about in M.2_1 (CPU lanes), because M.2_2 always
  shares the chipset x4 uplink.
- Check APST/ASPM.
