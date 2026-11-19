---
type: Reference
description: brys hardware and performance reference — CPU/RAM, motherboard and PCIe/M.2 topology, GPUs, the ZFS mirror and LUKS layout, measured NVMe read throughput, the ZFS ARC cap, measured memory bandwidth, the model-load memory burst, and which older measurements are superseded.
timestamp: 2026-11-19T21:00:00+01:00
---

# brys performance

Hardware inventory and measured performance of **brys** (Ryzen 9 5950X workstation, 128 GB DDR4,
Radeon AI PRO R9700). The model-serving configuration, the boot specialisations and the deployment
state are in [docs/local-llms.md](../../docs/local-llms.md); the full engine and quant sweep is in
[docs/tasks/2026-11/brys-r9700-model-fit/measurements.md](../../docs/tasks/2026-11/brys-r9700-model-fit/measurements.md);
this file holds the hardware and the measurements taken on it.

## What is current and what is superseded

The card changed on 2026-11-17: a W6600 (8 GB) left and an R9700 (32 GB) arrived. Anything measured
on the old card is a lower bound at best and often simply wrong for sizing. Read this table first.

| section                          | status         | why                                                                       |
| -------------------------------- | -------------- | ------------------------------------------------------------------------- |
| CPU and RAM                      | current        | hardware                                                                  |
| Motherboard and PCIe/M.2         | current        | corrected 2026-11-19: the R9700 runs **x16**, not x8                      |
| GPUs                             | current        | hardware; the W6600 note is history                                       |
| Storage: ZFS mirror and LUKS     | current        | numbers refreshed 2026-11-19                                               |
| NVMe / ZFS read throughput       | current        | re-confirmed 2026-11-19 with `dd iflag=direct`                             |
| ZFS ARC cap                      | current        | file reference corrected 2026-11-19                                        |
| Memory bandwidth                 | current        | CPU hardware ceiling, independent of the card                              |
| The model-load memory burst      | current        | measured 2026-11-19, and it is what makes profile switching survive         |
| Per-model resident footprints    | **superseded** | W6600 era, llama.cpp, a model set that is no longer served                 |
| Warm long-task decode (Qwen/DS4) | **superseded** | 9.9 t/s on the W6600 against 66.7 t/s on the R9700 for the same family slot |

## CPU and RAM

AMD Ryzen 9 5950X, 16 cores / 32 threads, one NUMA node, 64 MiB L3
(2 x 32 MiB), 8 MiB L2, boost to 5086 MHz. 128 GB DDR4, 125 GiB usable, **no swap** (zram is off on
purpose, see `default.nix` "Reliability of the served models wins"). The absence of swap is not
cosmetic: with a served model holding about 95 GiB, a load that overshoots has nothing to fall back
on, so the kernel kills the engine instead of paging (see "The model-load memory burst").

## Motherboard and PCIe / M.2 topology

ASUS ROG Strix X570-E Gaming WiFi II (X570S, passive chipset). `lspci -tv` confirms:

| device                         | slot      | link                | root port             |
| ------------------------------ | --------- | ------------------- | --------------------- |
| `nvme0n1` (Goodram PX700 2 TB) | M.2_1     | CPU Gen4 x4         | `00:01.1`             |
| `nvme1n1` (Viper VP4300L 2 TB) | M.2_2     | chipset Gen4 x4     | `00:01.2` → `02:00.0` |
| R9700 `0d:00.0`                | PCIEX16_1 | CPU **Gen4 x16**    |                       |
| Radeon 550 "Lexa" `0e:00.0`    | PCIEX16_2 | CPU Gen3 x8         |                       |

The R9700 link was reported as "Gen4 x8" in earlier revisions of this file. That was wrong.
Measured 2026-11-19 from `/sys/bus/pci/devices/0000:0d:00.0/`:
`current_link_speed = 32.0 GT/s`, `current_link_width = 16`, and the maxima match, so the card is
not downlinked. The Lexa beside it runs `8.0 GT/s` at width 8 (Gen3 x8).

`nvme1n1` sits behind the X570 uplink (`00:01.2` → `02:00.0`). That PCIe 4.0 x4
link is shared with the MT7921K Wi-Fi, the RTL8125 2.5GbE, the I211 GbE, the
chipset USB, and the chipset SATA. The GPUs use CPU lanes. BIOS 5013 (2024-03;
latest 5044).

**Known issues, relevant and not.** There is no chipset fan: this is the passive
X570S, so the fan complaints belong to the older X570-E. The USB-dropout root
cause is fixed by AGESA 1.2.0.2, and brys is newer. The Wi-Fi/BT (MediaTek
MT7921K) driver issues are mostly on Windows. brys shows no PCIe AER errors.

## GPUs

| PCI       | device                         | id          | VRAM                      |
| --------- | ------------------------------ | ----------- | ------------------------- |
| `0d:00.0` | Radeon AI PRO R9700 (RADV NAVI48) | `1002:7551` | 31.86 GiB (`34213183488` B) |
| `0e:00.0` | Lexa PRO (Radeon 540/550)      | `1002:699f` | 4.00 GiB (`4294967296` B) |

`MESA_VK_DEVICE_SELECT=1002:7551!` pins the R9700 as `Vulkan0`; the Lexa is
never selected.

The Lexa is the reason `hack/rocm-skip-legacy-gpu.c` exists: ROCm 7.2 aborts `hsa_init` on the
gfx803 card (deprecated doorbell type), and the shim lets every HIP tool in the fleet initialise.
The R9700 itself does not need it.

**History.** The W6600 (8 GB) that this host ran until 2026-11-17 was a draft-head GPU. Every number
in the superseded tables below was taken on it. On the R9700 the same slot now measures **66.7 t/s
decode / 2779 t/s prefill** with Strata at 256k (IQ2_XS) and **22.3 t/s / 255 t/s** with
llama.cpp Vulkan at 64k — about 3× and 11× the old card, so old figures cannot be scaled, they must
be replaced.

## Storage: ZFS mirror and LUKS

Two NVMe devices hold the pool. Two SATA HDDs and a USB stick are not part of
it.

| device    | size  | model              |
| --------- | ----- | ------------------ |
| `nvme0n1` | 1.9 T | SSDPR-PX700-02T-80 |
| `nvme1n1` | 1.8 T | Viper VP4300L 2TB  |

Both are LUKS2-encrypted (`px700-brys-crypted`, `vp4300-brys-crypted`) and form
a **2-device mirror**:

```
brys-main (ONLINE, 1.81 T, 1.61 T used, 152 G avail)
  mirror-0
    dm-...-px700-brys-crypted   ONLINE
    dm-...-vp4300-brys-crypted  ONLINE
```

The model dataset is `brys-main/brys/impermanence/usr/data` (1.25 TiB used, 152 GiB avail on
2026-11-19), mounted at `/nix/persist/usr/data` and persisted to `/var/lib/kdn/llms/models`.
Properties: `recordsize 128K`, `compression lz4`, `primarycache all`, `atime on`, `sync standard`,
`logbias latency`, `direct standard`.

The 152 GiB free is the ceiling on a new pack: UD-Q4_K_XL (about 65 GiB) fits, a second full pack
beside the current one may not.

## Measured NVMe / ZFS read throughput

Measured 2026-10-08 (corrected). The first numbers were wrong. The `fio` job
capped the queue depth to 1 (QD1/psync), so it measured per-request latency,
not the drive. Re-measured with **asynchronous high queue depth** (`fio
io_uring`, `iodepth=64`, `numjobs=4`, `bs=128k`, `--direct=1`) on a 32 GiB
incompressible scratch file after `drop_caches`:

| read                                    | throughput        |
| --------------------------------------- | ----------------- |
| cold sustained, per drive               | **~2.0–2.2 GB/s** |
| warm band, per drive, at ~800–900 G LBA | **~5.4–6.0 GB/s** |
| mirror dataset, warm                    | **~10 GB/s**      |

Re-confirmed 2026-11-19 on a model shard: `dd iflag=direct bs=1M count=4096` on the 46 GiB
`UD-IQ4_XS` shard read **7.7 GB/s**. That number is why the profile manager drops the page cache
before a load instead of protecting it — a full 55 GiB re-read costs seconds, not minutes.

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

`hosts-den/brys/llm-tuning-shared.nix` caps the ZFS ARC at 8 GiB with the kernel parameter
`zfs.zfs_arc_max=8589934592`. The ARC is a _second_ cache beside the Linux page
cache that backs the `mmap`'d model weights. At its default `c_max` (about half
of RAM) it grew to ~65 GB and the kernel evicted the weights to make room. The
cap keeps the weights resident. It is a kernel module parameter, so it applies
on a **cold boot** only (a `switch` does not apply it); to apply it live:

```bash
echo 8589934592 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
```

The serving-side effect and the measured context ladder are in
[docs/local-llms.md](../../docs/local-llms.md), "ZFS ARC quirk".

## Measured memory bandwidth

Real RAM throughput measured via a STREAM-style benchmark compiled for `znver3`
and run on brys under the `performance` governor (2026-09-05). This supersedes
the earlier _assumed_ DDR4 figure of ~50 GB/s.

| op    | MiB working set | GB/s  |
| ----- | --------------- | ----- |
| COPY  | 4096            | 39.80 |
| TRIAD | 4096            | 27.90 |
| ADD   | 4096            | 26.74 |
| SCALE | 4096            | 24.20 |
| COPY  | 320             | 38.81 |

Implication for the tok/s ceiling: CPU decode reads activated weights
sequentially, so **COPY (~40 GB/s)** is the right figure. A model that streams
~5 GB of activated params per token has a realistic ceiling of **~8 tok/s** on
this CPU. Numbers above that are GPU work, not CPU work.

## The model-load memory burst

Measured 2026-11-19. A Strata load is one allocation burst, not a steady state, and it decides
whether a profile switch works:

| quantity                    | value                                                                 |
| --------------------------- | --------------------------------------------------------------------- |
| peak RSS during a load      | **88–98 GiB** (anon 58 GB + file-backed pack 28 GB + shmem KV 12 GB)   |
| settled RSS while serving   | **30 GiB** (`max`, 30 GiB VRAM)                                       |
| unevictable while serving   | `Mlocked` about 27 GiB, `Unevictable` about 28 GiB                     |
| swap                        | none                                                                  |

On a 125 GiB host with 40–48 GiB of the pack in page cache, the burst outruns reclaim: every failing
load ended at 88–98 GiB RSS with `free` at 0, the kernel OOM-killed the engine, `OOMPolicy=stop`
restarted the manager, and the cycle repeated. Raising `vm.min_free_kbytes` to 2 GiB and
`vm.watermark_scale_factor` to 200 did not prevent it.

The fix is to give the burst the cache: the manager drops the page cache (a root oneshot plus one
sudoers line for `llm-server`) between stopping the old engine and starting the new one. At 7.7 GB/s
a full re-read costs seconds, and the switch survives — measured 64 s for `max` → `omni-max` and
67 s back, with zero OOM kills. Details and the full table:
[docs/tasks/2026-11/brys-r9700-model-fit/measurements.md](../../docs/tasks/2026-11/brys-r9700-model-fit/measurements.md),
"The switch is memory-bound" and "The fix: drop the page cache before every load".

## Superseded: per-model resident footprints (W6600 era)

Kept only as history. The models below are no longer served on brys and the rates belong to the
8 GB W6600 with llama.cpp; the current pack is a 55 GiB Strata profile whose settled RSS is 30 GiB
with a 95 GiB load peak (see the section above).

Each model loaded via a manual `llama-server` (llama.cpp 10408, `mmap`, threads 12) one at a time on
the 128 GB box (DeepSeek router also resident for the small models). Resident working set = `VmRSS`
= `RssAnon` (compute/KV buffers) + `RssFile` (mmap'd weights). `warm t/s` = 128-token generation.

| model                   | file   | VmRSS             | RssAnon | RssFile | VmPeak | load             | warm t/s | coexist w/ DS4?                               |
| ----------------------- | ------ | ----------------- | ------- | ------- | ------ | ---------------- | -------- | --------------------------------------------- |
| `phi-4`                 | 8.5 G  | 17.7 G            | 8.9 G   | 8.7 G   | 23 G   | ~18 s            | 2.86     | yes (fits; evicts little)                     |
| `qwen3-30b-a3b`         | 18 G   | 44.4 G            | 26.4 G  | 18.0 G  | 50 G   | ~42 s            | 11.41    | partial (evicts ~45 G of DS4 cache)           |
| `qwen3-coder-next`      | 45 G   | 65.6 G            | 39.6 G  | 25.9 G  | 91 G   | ~105 s           | 5.34     | no (fully evicts DS4)                         |
| `qwen3-next-80b`        | 46 G   | 80.0 G            | 39.2 G  | 40.8 G  | 94 G   | ~99 s            | 3.29     | no (fully evicts DS4)                         |
| `qwen3-235b`            | 72 G   | (fail) ~100 G est | —       | —       | —      | fail @65 G avail | —        | no (needs box alone)                          |
| `gpt-oss-120b` (Q4_K_M) | 58.5 G | 72.2 G            | 60.2 G  | 11.8 G  | 128 G  | ~129 s           | **12.7** | yes (fits; DS4 file-cache evicted, re-faults) |

The RAM column is still a fair indication of what a llama.cpp model of that size costs on this host;
the t/s column is not transferable.

## Superseded: warm long-task decode, Qwen vs DS4 (W6600 era)

Kept only as history: the same family slot now runs 66.7 t/s through Strata on the R9700, so these
figures document the old card, not a current operating point.

Measured on brys, warm and contention-free, through the `llms-frontier` router,
on 1500–2000-token generations at temp 0. These are **post-no-BLAS** numbers
(see "The BLAS backend stall" in [docs/local-llms.md](../../docs/local-llms.md)).
"Sustained decode" covers the whole generation; "1st-half → 2nd-half" splits it
in two.

| model              | ctx depth | sustained decode | spec acceptance / mean-len | 1st-half → 2nd-half |
| ------------------ | --------- | ---------------- | -------------------------- | ------------------- |
| Qwen3.8-Flash-Next | ~0.2K     | 9.9 t/s          | 0.73 / 4.65                | 9.1 → 10.8          |
| Qwen3.8-Flash-Next | ~16K      | 8.1 t/s          | 0.64 / 4.18                | 7.8 → 8.5           |
| DeepSeek V4 Flash  | ~0.2K     | 3.2–3.4 t/s      | 0.65–0.69 / 4.2–4.4        | 2.7 → 3.9           |
| DeepSeek V4 Flash  | ~16K      | 3.2 t/s          | 0.63 / 4.2                 | 2.7 → 3.9           |

Two observations still hold as behaviour, whatever the card: decode does not decay over a long
generation (the second half is faster, from rising acceptance), and context depth barely moves the
per-token cost — the t/s gaps come from speculative acceptance, not attention length.

## To test later (no changes yet)

- Update BIOS 5013 → 5044.
- Monitor NVMe temperatures under load.
- Keep the drive you care about in M.2_1 (CPU lanes), because M.2_2 always
  shares the chipset x4 uplink.
- Check APST/ASPM.
