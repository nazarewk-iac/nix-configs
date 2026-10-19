---
type: Solution
description: Closed the disk-offload study. Each lever has a measured effect or a documented reason it does not apply; the main result corrects the lazy-mode RAM claim.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T21:32:00+02:00
---

# Solution — disk-offload and RAM-reduction study

## What was delivered

- [offload.research.md](offload.research.md): the lever inventory, with the
  upstream source of each flag.
- [offload-measurements.research.md](offload-measurements.research.md): the
  standalone measurements on brys, one row per lever and model.

## Main result

`--lazy-mode off` does **not** cost 46 GB of real RAM. With `mmap` the weights
stay in reclaimable `buff/cache`, so system `used` is unchanged (~15.7 GB)
whether lazy mode is `off` or `auto`. The 46 GiB appears only as process
`RssFile`. `off` is in fact faster on a cold box (decode 5.22 vs 3.23 tok/s at
ctx 16384) because it reads the large tensors once at load.

The rule this study establishes: **read system `used`, not process `VmRSS`, to
judge the RAM budget on brys.** The `docs/local-llms.md` `--lazy-mode` section
now carries this correction.

## Other measured results

- `--load-mode none`: process RSS 271 MB, but 71 GB of non-reclaimable `used`.
  Standalone-only; 27% decode cost.
- `--load-mode mmap` (default): the correct colocated lever.
- `--load-mode mlock`: aborts (8 MiB `RLIMIT_MEMLOCK`).
- `--load-mode dio` and `-ngl -cmoe -nkvo`: crash or hang the W6600.
- KV quant and `--cache-ram`: no measurable effect at ctx 16384.

## Not tested

`--no-mmap-prefetch`, `--moe-stream*`, `--pin-hot-experts*`: no build with them
is present in the Nix store. The positive MoE-stream case (a model larger than
RAM) stays unmeasured.

## Follow-ups

- Re-test KV quant and `--cache-ram` at the served 1M context, where the KV is
  about 24 GiB.
- Build a master package before testing the streaming levers.
