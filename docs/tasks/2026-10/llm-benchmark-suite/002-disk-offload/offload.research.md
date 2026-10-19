---
type: Research
description: Inventory of llama.cpp disk-offload and RAM-reduction levers for large MoE serving on brys — exact flags, upstream sources, and which effects are documented upstream versus still to be measured.
task: ../definition.md
authored_by: agent
timestamp: 2026-10-19T18:21:00+02:00
---

# Disk-offload and RAM-reduction levers for llama.cpp

This document is a research inventory, not a measurement report. It lists the
llama.cpp and ggml levers that move weights or KV to disk, or that cut RAM. For
each lever it gives what the lever does, the exact CLI flag, the upstream
source, when it helps, and the known trade-off.

Every claim is marked either **documented upstream** (with the source) or **to
be measured** (on brys). Prior brys results are reproduced here only where a
task doc already recorded them; they are marked **measured on brys (prior)** and
are not re-measured.

Host under study: `brys` — AMD Ryzen 5950X (16 cores, AVX2, F16C, FMA, no
AVX512), 128 GB DDR4, 8 GB AMD Radeon Pro W6600 (RDNA2, `gfx1032`, Vulkan0),
ZFS storage. The measured disk floor is 2.3-2.5 GB/s cold read
(`docs/tasks/2026-10/llm-benchmark-suite/002-disk-offload/definition.md`).

A dash in the "brys effect" column means the lever was not tried on brys.

## 1. `--lazy-mode` and `--load-mode`

### `--lazy-mode` (SSD offload of large tensors)

- **Short flag.** `-lzm`, `--lazy-mode MODE`. Env `LLAMA_ARG_LAZY_MODE`.
- **What it does.** Reads certain large tensors, for example per-layer
  embedding (PLE) tables, as rows from disk on demand instead of keeping them
  resident. Requires `mmap`. **documented upstream**
  (`common/arg.cpp` in ggml-org/llama.cpp master, `--lazy-mode` option help).
- **Modes.**
  - `on` — read the rows of such tensors from disk on demand.
  - `auto` (default) — `on`, but only for tensors larger than 4 GiB.
  - `off` — always keep them resident.
- **When it helps.** A model whose large non-expert tensors (for example the
  n-gram / PLE table) are rarely used and can live on disk. It trades a slower
  first use for a smaller resident set.
- **Trade-off.** `off` makes the tensors resident and raises RAM. There is no
  throughput gain from `off`.
- **brys effect (measured on brys, prior).** Qwen3.8-Flash-Next `UD-IQ4_XS`
  (93.7 GB): `off` → `auto` freed about **46 GB** (`RssFile` 92.2 → 46.0 GB);
  prefill unchanged; decode rose slightly (11.14 → 12.26 t/s). `on` equals
  `auto` on this model, because the default already offloads the same tensors
  (`docs/local-llms.md`, "`--lazy-mode` SSD offload"). `auto` is the serving
  default and should not be changed.
- **To be measured.** `--lazy-mode` on the two frontier models (DeepSeek V4
  Flash, Qwen3.8-Flash-Next) at their served context, standalone, with RSS and
  disk-read volume recorded.

### `--load-mode` (mmap / mlock / none)

- **Short flag.** `-lm`, `--load-mode MODE`. Env `LLAMA_ARG_LOAD_MODE`.
- **What it does.** States how the mapped weights are locked or mapped.
  **documented upstream** (`common/arg.cpp`, `--load-mode` option help).
- **Modes.**
  - `auto` (default) — mmap, unless a device does not support it.
  - `mmap` — memory-map the model.
  - `mlock` — keep the model in RAM; blocks swap and compression.
  - `mmap+mlock` — mmap plus mlock.
  - `none` — no special loading mode.
  - `dio` — direct I/O if available.
- **Note.** v0.6.0 and later builds dropped `--mmap` / `--no-mmap` and accept
  only `--load-mode`. The router-mode INI key `mmap = on|off` maps onto
  `--load-mode mmap|none` (`modules/den/aspects/llm.nix:390-396`).
- **When it helps.** `mlock` helps only when the model fits with room; it stops
  reclaim under pressure. `mmap` (the default) lets the kernel reclaim weight
  pages, so a colocated model slows down instead of failing.
- **Trade-off.** `mlock` pins the weights and defeats reclaim; on brys it did
  nothing, because ~101 GB cannot be locked and `mmap` conflicts
  (measured on brys, prior: `docs/local-llms.md` benchmark log 2026-09-06,
  "mlock DID NOT materialize: 0 bytes locked"). `none` drops mmap and therefore
  the prefetch; on brys it OOMs the W6600 (`amdgpu: Not enough memory for
  command submission`).
- **brys effect (measured on brys, prior).** `mlock` null; `none` crashes the
  W6600. Keep `mmap` (`docs/local-llms.md`, "Freeing RAM when colocating").
- **To be measured.** `--load-mode dio` (direct I/O) has no brys result. It may
  match `mmap` without page cache. Record RAM and cold-read behavior.

## 2. `--no-mmap`, `--no-mmap-prefetch`

- **`--no-mmap`.** Removed in v0.6.0 and later; use `--load-mode none`.
  **documented upstream** (the removal is visible in `common/arg.cpp`; the
  option is absent, `--load-mode` is present).
- **`--no-mmap-prefetch` (upstream PR #29250).**
  - **What it does.** Skips the `MADV_WILLNEED` prefetch that `init_mappings`
    issues at load. Adds `llama_model_params.mmap_prefetch` (default `true`)
    plus the `--no-mmap-prefetch` CLI flag. **documented upstream**
    (<https://github.com/ggml-org/llama.cpp/pull/29250>).
  - **When it helps (upstream claim).** The PR targets macOS, where the
    prefetch is blocking and reads the whole file into page cache; for a model
    larger than about half of RAM the load hangs and thrashes swap.
  - **Status.** The PR is **closed, not merged** (closed 2026-10-08; base
    master head `9c2e0e4` has no such flag). Carried on brys as the
    experimental `llama-cpp-master-noprefetch-vulkan` package row.
  - **Trade-off.** Skipping the prefetch removes the load-time page-cache
    warm, so the first request pays the cold read instead.
  - **brys effect (measured on brys, prior).** Negative. On Qwen3.8-Flash-Next
    at 1M context: load fell 140.2 → 84.0 s, but the first request rose
    141.8 → 191.7 s and steady decode fell 4.20 → 2.36 t/s. The stall is
    cold-read bound, not prefetch bound
    (`docs/local-llms.md`, "The first-request stall";
    `packages/llama-cpp/README.md`). No host selects this build.
- **To be measured.** Re-confirm on a frontier model at the served context, and
  test the combination `--load-mode none --no-mmap-prefetch`. Note that
  `--load-mode none` already drops mmap and the prefetch.

## 3. MoE expert offload and streaming

### `--cpu-moe` (`-cmoe`)

- **What it does.** Keeps all Mixture-of-Experts weights on the CPU. Pushes the
  `ffn_*_exps` tensors to a CPU buffer. **documented upstream**
  (`common/arg.cpp`, `--cpu-moe` option help; env `LLAMA_ARG_CPU_MOE`).
- **When it helps.** A GPU host with a model whose experts exceed VRAM but fit
  in RAM. On a CPU-only model it is a no-op.
- **Trade-off.** Every expert matmul at prefill becomes a PCIe transfer when
  some layers sit on the GPU.
- **Related.** `--n-cpu-moe N` (`-ncmoe`) keeps the experts of only the first N
  layers on the CPU. `--cpu-moe-draft` / `-cmoed` does the same for the draft
  model.
- **brys effect (measured on brys, prior).** With `-ngl 99 -cmoe -nkvo`, decode
  fell to **2.01 t/s** against 9.13 on the CPU, because the 24 GiB F16 KV stays
  on the CPU and every attention step crosses PCIe
  (`docs/tasks/2026-10/qwen-gpu-offload/done.md`).

### `-ot` / `--override-tensor` (per-tensor placement)

- **What it does.** Overrides the buffer type of tensors that match a regex,
  for example `ffn_.*_exps=CPU`. The value is a list of
  `<tensor name pattern>=<buffer type>` pairs. **documented upstream**
  (`common/arg.cpp`, `--override-tensor` option help; env
  `LLAMA_ARG_OVERRIDE_TENSOR`).
- **When it helps.** Fine-grained control: place the experts of chosen layers,
  or one tensor class, on the CPU or a GPU.
- **Trade-off.** Wrong patterns silently match nothing. A regex that touches no
  tensor has no effect.
- **brys effect (measured on brys, prior).** `-ngl 99 -nkvo -ot "ffn_.*_exps=CPU"`
  gave the same 2.01 t/s as `-cmoe`; a partial `-ngl` without `-cmoe` filled
  VRAM and was slower (`qwen-gpu-offload/done.md`).
- **Slots.** `perf.extraFlags` passes arbitrary flags per model
  (`modules/den/aspects/llm.nix:385`); `-ot` is available that way.

### MoE expert streaming from disk — PR #25294

- **What it does.** Keeps the routed expert weights (`ffn_*_exps`) on disk and
  pages them into a fixed-size per-layer cache on demand. A CPU id-remap op
  after the router top-k maps expert ids to cache slots; misses load from the
  GGUF through a pread worker pool. Reads use `O_DIRECT` to bypass the page
  cache. Output is byte-identical to a non-streamed run. **documented upstream**
  (<https://github.com/ggml-org/llama.cpp/pull/25294>).
- **Flags.**
  - `--moe-stream` — enable.
  - `--moe-stream-cache <NG|Ns>` — GiB budget, or exact slots per layer with an
    `s` suffix. Implies `--moe-stream`.
  - `--moe-stream-io-threads N` — reader threads.
  - `--moe-stream-direct` — `O_DIRECT` expert reads.
- **When it helps (upstream claim).** A model larger than RAM. Upstream
  reports about 5.3x prefill and 2.4x decode against `--cpu-moe` + mmap on a
  model that does not fit.
- **Trade-off.** Streaming **auto-disables mmap**. When the model is mostly
  resident, `O_DIRECT` bypasses the page cache that serves the weights, so
  throughput falls. A known bug: the default cache sizes `2*n_expert_used`
  slots, but the wave prefill path needs `>= 3*n_expert_used`, so plain
  `--moe-stream` can `GGML_ABORT` at graph build. Single-context only.
- **Status.** Open, not merged (large PR, maintainers asked for a wider design
  review). Carried on brys as `llama-cpp-master-moe-stream-vulkan`.
- **brys effect (measured on brys, prior).** Negative on a mostly-resident
  model. With `--moe-stream --moe-stream-direct --moe-stream-cache 64s`,
  steady decode fell 4.68 → 3.10 t/s (−34%) and prefill 16.5 → 5.7 t/s (−65%),
  while RSS fell to about 41 GiB
  (`packages/llama-cpp/README.md`, "Expert-streaming experiments").
- **To be measured.** The positive case: a model that does **not** fit in RAM
  with `--moe-stream` versus `--cpu-moe` + `--load-mode mmap`, with the disk
  read volume recorded. `nemotron-3.5-bolt-74b` (21 GB, fails to load) is a
  candidate; a larger MoE than 128 GB is the true target.

### Pin hot experts — PR #26414

- **What it does.** Tracks expert usage at runtime and `mlock`s the N hottest
  experts per layer, so the page cache cannot evict them. Dense tensors are
  `mlock`ed first, because they are used on every token. Adds a load mode
  `--load-mode mmap+pin`. **documented upstream**
  (<https://github.com/ggml-org/llama.cpp/pull/26414>).
- **Flags.** `--pin-hot-experts N`, `--pin-hot-experts-budget-mib N`,
  `--pin-hot-experts-stats-interval N`, `--load-mode mmap+pin`.
- **When it helps (upstream claim).** A large MoE that is mostly resident but
  loses hot experts to eviction; on the author's GLM-5.2 test prefill rose
  from 24.4 to 37.5 tok/s and gen from 2.0 to 3.0 tok/s.
- **Trade-off.** Needs `mlock` limits raised (default `RLIMIT_MEMLOCK` is small,
  for example 8 MB). It plays badly with `--no-warmup`. Its callback keys on
  `ffn_moe_topk`.
- **Status.** Open, not merged. Carried on brys as
  `llama-cpp-master-pin-hot-experts-vulkan`.
- **brys effect (measured on brys, prior).** No-op on Qwen3.8-Flash-Next:
  the build prints `no MoE layers detected in model`, because the callback does
  not match `qwen4exp`. Decode and prefill equal the baseline
  (`packages/llama-cpp/README.md`).
- **To be measured.** A model with a matching MoE architecture, where eviction
  actually happens (a model close to the RAM limit). Confirm `mlock` limits and
  drop `--no-warmup`.

## 4. KV-cache reduction

### KV type — `--cache-type-k` / `--cache-type-v`

- **Short flags.** `-ctk` / `-ctv`. Env `LLAMA_ARG_CACHE_TYPE_K` /
  `LLAMA_ARG_CACHE_TYPE_V`. **documented upstream** (`common/arg.cpp`).
- **Allowed values.** `f32`, `f16`, `bf16`, `q8_0`, `q4_0`, `q4_1`, `iq4_nl`,
  `q5_0`, `q5_1`.
- **When it helps.** Shrinks KV RAM. `q8_0` roughly halves an F16 KV; `q4_0`
  halves it again.
- **Trade-off.** Lower KV precision costs decode speed and a little quality.
- **brys effect (measured on brys, prior).** Qwen at 1M: `-ctk q8_0 -ctv q8_0`
  halved KV (about 24 → 12 GiB); at 512K `RssAnon` fell 19.9 → 13.1 GB; decode
  fell slightly (about 8.49 → 7.9 t/s) (`docs/local-llms.md`, RAM-levers table).
  The older claim that `q8_0` is buggy for `qwen4exp` does **not** reproduce on
  v0.6.0.
- **To be measured.** `q4_0` KV on a frontier model, with quality probes.

### `--kv-unified` (`-kvu`)

- **What it does.** One KV buffer shared across all sequences, instead of a
  per-slot buffer. **documented upstream** (`common/arg.cpp`, `--kv-unified`;
  default enabled when the slot count is auto). The negative form is
  `--no-kv-unified` (`-no-kvu`).
- **When it helps.** It bounds the total cell count at `n_ctx` regardless of
  `parallel`, so `parallel` never multiplies KV RAM, and a second request does
  not queue behind the first request's full prefill. **documented upstream**
  (`src/llama-context.cpp:294-297` cited in `docs/local-llms.md`).
- **Trade-off.** None measured; it costs about 3 GB over `parallel 1` on Qwen.
- **brys effect (measured on brys, prior).** `parallel 4 --kv-unified` removed
  head-of-line blocking; a short request returned in 2.4-4.6 s while a 400-token
  request was in flight (51.5 s serialised without it)
  (`docs/local-llms.md`, "Concurrency").
- **Related.** `--kv-unified-per-slot N` caps context per slot.

### `--cache-ram` (`-cram`)

- **What it does.** Sets the maximum size of the **prompt** cache (cross-request
  KV state for prefix reuse), in MiB. Default 8192 MiB; `-1` no limit; `0`
  disable. `0` also selects decision models. **documented upstream**
  (`common/arg.cpp`, `--cache-ram`; PR #16391).
- **When it helps.** Lower it to shrink the prompt cache and free RAM. Raise it
  to stop constant evictions of large prompt entries.
- **Trade-off.** A smaller cache evicts prompt state sooner (slower reuse); a
  full large cache evicts weight pages.
- **brys effect (measured on brys, prior).** One long Qwen prompt is about
  5.7 GiB, so the 8 GiB default evicted constantly. The Qwen entries raise it to
  36864 (37 GiB); the session-cache entries use 16384
  (`docs/tasks/2026-10/llm-prompt-cache-ram/done.md`; `docs/local-llms.md`).
- **To be measured.** The low end on a frontier model at a fixed context: does
  a small `--cache-ram` free RAM without a large latency cost for a single-turn
  benchmark.

### `--swa-checkpoints` / `--ctx-checkpoints` (`-ctxcp`)

- **Short flag.** `-ctxcp`, with the aliases `--ctx-checkpoints` and
  `--swa-checkpoints`. Env `LLAMA_ARG_CTX_CHECKPOINTS`. **documented upstream**
  (`common/arg.cpp`; PR #15293).
- **What it does.** Maximum number of context checkpoints to create per slot.
  A checkpoint is a saved mid-context state that lets a later request resume
  instead of re-prefilling.
- **When it helps.** Long sessions with recurrent or hybrid state, where a
  saved checkpoint avoids a full re-prefill.
- **Trade-off.** Each checkpoint costs RAM. On brys each Qwen GDN checkpoint is
  about 112 MiB; `ctx-checkpoints 32` bounds checkpoint RAM at about 14 GiB over
  four slots (`docs/local-llms.md`, "Disk session cache").
- **Related.** `--checkpoint-min-step` (`-cms`) sets the minimum spacing in
  tokens. `--swa-full` uses a full-size SWA cache (PR #13194).
- **To be measured.** The RAM cost of a checkpoint on a frontier model, and
  whether a lower `--ctx-checkpoints` frees RAM with an acceptable reuse cost.

## 5. Quant choice at a fixed RAM budget

- **What it does.** The quant sets the weight size and therefore the RAM floor.
  A smaller quant is the most direct RAM reduction, at a quality cost.
  **documented upstream** (GGUF quant types, `llama-quantize`).
- **brys effect (measured on brys, prior).** On Qwen3.8-Flash-Next,
  `UD-IQ3_XXS` (82 GB) frees about **12 GB** against `UD-IQ4_XS` (93.7 GB), for
  a quality drop (85.4% vs 89.6% top-1). `UD-IQ4_XS` was chosen because it keeps
  the 51B n-gram table inside the weight shards and fits under the 8 GiB ZFS ARC
  cap; `UD-Q4_K_XL` is about 10 GB bigger and tight
  (`docs/tasks/2026-10/qwen-flash-next-quant/done.md`; `docs/local-llms.md`).
- **To be measured.** A quant sweep at one fixed context and RAM budget across
  the frontier models, with a quality probe per quant. Reuse the
  `qwen-flash-next-quant` method (perplexity or top-1) rather than an
  unsupervised size comparison.

## 6. GPU offload for the W6600

The W6600 has 8 GB VRAM and is **disabled for serving on brys**: it hard-hangs
under the Qwen MTP draft workload (amdgpu compute ring timeout, Vulkan device
lost). The history below is the record of what was tried
(`docs/local-llms.md`, "GPU draft head"). Keep it as a reference, not a plan.

- **`-ngl` / `--n-gpu-layers` / `--gpu-layers`.** Max layers in VRAM; an exact
  number, `auto`, or `all`. Env `LLAMA_ARG_N_GPU_LAYERS`. **documented
  upstream** (`common/arg.cpp`). When it helps: only when the KV cache also fits
  in VRAM.
- **`-nkvo` / `--no-kv-offload`.** Keeps the KV cache on the CPU. When the KV
  exceeds VRAM this is forced, and it then makes every attention step a PCIe
  transfer.
- **`-ngld` / `--n-gpu-layers-draft` / `--gpu-layers-draft`.** `-ngl` for the
  draft model. **documented upstream** (`common/arg.cpp`).
- **`--device` / `-dev`.** Selects the GPU; `Vulkan0` is the W6600,
  `Vulkan1` is the 4 GB Lexa. `MESA_VK_DEVICE_SELECT=1002:73e3!` pins it in the
  process.
- **brys effect (measured on brys, prior).**
  - `-ngl 99 -cmoe -nkvo`: 2.01 t/s (slower; KVA crosses PCIe).
  - `-ngl 99 -nvko -ot ffn_.*_exps=CPU`: 2.01 t/s.
  - `-ngl 20`: 5.04 t/s; `-ngl 8`: 5.89 t/s; `-ngl 40 -cmoe -nkvo`: 1.61 t/s.
    All slower than the CPU (9.13 t/s).
  - `n-gpu-layers-draft 99` (draft head only): **10.82 t/s**, +18.5% over the
    CPU, VRAM 6.40 GiB. This was the only win, and it is now disabled because
    the W6600 hard-hangs at long context.
  (`docs/tasks/2026-10/qwen-gpu-offload/done.md`.)
- **To be measured.** A re-test of the draft-head offload only after an amdgpu
  driver or firmware fix. Dense-layer offload is settled: slower.

## Summary table

| lever | flag | documented upstream | brys prior | brys effect |
|---|---|---|---|---|
| lazy-mode SSD offload | `-lzm`/`--lazy-mode` | yes (`arg.cpp`) | yes | -46 GB, decode flat |
| load mode | `-lm`/`--load-mode` | yes (`arg.cpp`) | yes | mlock null; none OOMs GPU |
| skip mmap prefetch | `--no-mmap-prefetch` | yes (PR #29250, closed) | yes | negative |
| drop mmap | `--no-mmap` | removed; use `--load-mode none` | yes | null / crash |
| CPU MoE | `-cmoe`/`--cpu-moe` | yes (`arg.cpp`) | yes | 2.01 t/s (worse) |
| tensor override | `-ot`/`--override-tensor` | yes (`arg.cpp`) | yes | same as cpu-moe |
| MoE stream | `--moe-stream*` | yes (PR #25294, open) | yes | -34% decode, RSS 41 GiB |
| pin hot experts | `--pin-hot-experts*` | yes (PR #26414, open) | yes | no-op on `qwen4exp` |
| KV type | `-ctk`/`-ctv` | yes (`arg.cpp`) | yes | q8_0 halves KV |
| unified KV | `-kvu`/`--kv-unified` | yes (`arg.cpp`) | yes | removes HOL blocking |
| prompt cache RAM | `-cram`/`--cache-ram` | yes (`arg.cpp`, PR #16391) | yes | 37 GiB stops evictions |
| context checkpoints | `-ctxcp`/`--ctx-checkpoints`/`--swa-checkpoints` | yes (`arg.cpp`, PR #15293) | yes | ~112 MiB each |
| quant choice | (GGUF file) | yes | yes | IQ3_XXS -12 GB, -4% top-1 |
| GPU layers | `-ngl` | yes (`arg.cpp`) | yes | slower than CPU |
| no KV offload | `-nkvo` | yes (`arg.cpp`) | yes | forces CPU KV |
| draft GPU layers | `-ngld` | yes (`arg.cpp`) | yes | +18.5%, then disabled |

## Highest-value levers

1. **`--lazy-mode auto`** — already the default; it holds about 46 GB off the
   resident set on Qwen with no throughput loss. Never set `off` on a colocated
   host.
2. **`mmap` + a capped ZFS ARC** — the weights stay file-backed and
   reclaimable; the ARC cap stops a second copy. This is the mechanism that
   keeps serving healthy under pressure.
3. **KV type and context size** — `-ctk q8_0 -ctv q8_0` halves KV; a smaller
   context is the direct KV-RAM knob. Lower the context first.
4. **Quant choice** — a smaller quant is the biggest single RAM reduction
   (`UD-IQ3_XXS` frees about 12 GB), at a measured quality cost.
5. **`--cache-ram`** — bounds the separate prompt cache; lower it to free RAM,
   raise it to stop evictions.

## The three most important things to measure

1. **The positive expert-streaming case.** All prior MoE-stream results are
   negative because the model was mostly resident. Measure `--moe-stream`
   versus `--cpu-moe` + `mmap` on a model larger than RAM, with disk read volume
   and tok/s. This is the only lever that lets a model exceed RAM.
2. **A quant sweep at one fixed RAM budget on a frontier model** (DeepSeek V4
   Flash and Qwen3.8-Flash-Next), with a quality probe per quant. The prior
   `qwen-flash-next-quant` work covers Qwen only, at one context.
3. **`--lazy-mode`, `--load-mode dio`, and KV quant on the frontier models at
   their served context**, standalone, with RSS and major-fault counts. Only
   Qwen3.8-Flash-Next has a measured `--lazy-mode` result today.
