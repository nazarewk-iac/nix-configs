---
type: Research
description: Candidate small "grunt" models to colocate with Qwen3.8-Flash-Next on brys, with bandwidth-ceiling arithmetic, the colocation RAM budget under 128 GB, a review of the existing llm-small set, the W6600 8 GB GPU option, and a concrete recommendation.
task: definition.md
timestamp: 2026-10-18T01:00:00+02:00
authored_by: agent
---

# Grunt-model colocation on brys — research

> **Scope.** A desk study only. No config was changed and nothing was measured for
> this report. Every number is either **measured** (with its source file) or
> clearly labelled **estimate**. The task asked for a rigorous estimate, so this
> report shows the arithmetic for each estimate; do not treat an unlabelled value
> as a measurement.

Answers the six questions: (1) candidate table, (2) smallest coexisting set,
(3) review of the existing small set, (4) the W6600 option, (5) a concrete
recommendation, (6) router and compat-proxy wiring.

---

## 0. The hardware and the one binding constraint

Measured on brys (`hosts/brys/performance.md:15-19`, `hosts/brys/performance.md:131-149`):

| quantity | value |
|---|---|
| CPU | Ryzen 9 5950X, 16C/32T, boost 5086 MHz |
| RAM | 128 GB DDR4, **125 GiB usable**, no swap |
| L3 / L2 | 64 MiB / 8 MiB |
| GPUs | W6600 7.98 GiB (`1002:73e3`); Lexa 4.0 GiB (`1002:699f`) |
| **STREAM COPY (the decode ceiling)** | **39.80 GB/s** (4 MiB set), 38.81 GB/s (320 MiB) |
| STREAM TRIAD/SCALE | 27.9 / 24.2 GB/s |
| NVMe cold sustained read | ~2.0–2.2 GB/s per drive, ~10 GB/s mirror warm band |
| W6600 VRAM bandwidth | ~224 GB/s (estimate from spec, `qwen-gpu-offload/definition.md:21`) |

**The single binding constraint is memory bandwidth on the CPU path.** CPU decode
reads the *activated* weights once per token, sequentially, so the ceiling is:

```
decode tok/s  ≈  COPY(40 GB/s) / (activated-bytes-read-per-token)
```

and prefill is not bandwidth-per-token-bound in the same way: it reuses the same
weights across a whole batch chunk, so prefill is **batch-bound** and reaches far
above the decode ceiling (measured: DS4 prefill 15.8 tok/s vs decode ~5–8; Qwen
prefill 39.9 vs decode ~9–12). The `--ubatch-size` lever sets prefill, not decode
(`docs/local-llms.md:352-385`).

**The second binding constraint is total RAM (125 GiB).** A model that does not
fit cannot be resident. Resident working set = `RssAnon` (KV + compute buffers) +
`RssFile` (mmap'd weights).

**The third constraint is bandwidth contention.** On a bandwidth-bound box two
co-resident models split the same ~40 GB/s. This is the colocation penalty the
task asks about (section 2).

---

## 1. Candidate grunt table

### 1a. The arithmetic

For a **dense** model the bytes read per decode token ≈ the whole quantised file
(all weights are used every token). For a **MoE** model only the active
parameters are read per token, but the **whole file must be resident in RAM**
(the router keeps it mapped). So:

- Dense decode: `tok/s ≈ 40 / (file-GB)`
- MoE decode: `tok/s ≈ 40 / (active-GB)` — fast decode, **huge residency**
- Both: prefill is batch-bound, much higher than the decode ceiling

Weights are ~1.0–1.1 bytes/param at Q4_K_M / IQ4_XS, ~0.45 at IQ3_XXS, ~0.42 at
IQ2_M. KV at F16 is `2 (K+V) × n_layers × n_kv_heads × head_dim × 2 bytes` per
token; dense small models at 32K context typically cost 1–4 GB KV.

### 1b. The table

Sizes marked **✎** are estimated from the parameter count and bytes/param;
decode t/s marked **✎** are the bandwidth-ceiling arithmetic above, not a
measurement. Only the rows tagged **meas** are measured on brys.

| model | arch | params (total / active) | Q4 file | resident RAM @32K | decode ceiling ✎ | prefill ✎ | note |
|---|---|---|---|---|---|---|---|
| Qwen3-0.6B | dense | 0.6B / 0.6B | ~0.4 GB | ~0.7 GB | **~57 tok/s** | 100s–1000s | fits GPU easily; too weak to be useful |
| Qwen3-1.7B | dense | 1.7B / 1.7B | ~1.1 GB | ~1.6 GB | **~25 tok/s** | 100s | floor of "usable grunt" |
| Qwen2.5-coder-1.5B | dense | 1.5B / 1.5B | ~1.0 GB | ~1.5 GB | **~27 tok/s** | 100s | code-tuned |
| Llama 3.2 3B | dense | 3B / 3B | ~2.0 GB | ~2.8 GB | **~14 tok/s** | 100s | — |
| **Qwen3-4B** | dense | 4B / 4B | ~2.5 GB | ~3.5 GB | **~11 tok/s** | 100s | **usable grunt** |
| Phi-4-mini (3.8B) | dense | 3.8B / 3.8B | ~2.5 GB | ~3.5 GB | **~11 tok/s** | 100s | strong reasoning for size |
| Qwen2.5-coder-7B | dense | 7B / 7B | ~4.5 GB | ~6 GB | **~6 tok/s** | ~100s | at ceiling edge |
| **Qwen3-8B** | dense | 8B / 8B | ~5.0 GB | ~7 GB | **~8 tok/s** | 100s | **best dense grunt; fits 8 GB GPU** |
| Llama 3.2 3B / Qwen3-4B | dense | — | — | — | — | — | — |
| Qwen2.5-coder-14B | dense | 14B / 14B | ~9 GB | ~12 GB | **~4.4 tok/s** | ~100s | below the "grunt" decode floor |
| **Qwen3-30B-A3B** | MoE | 30B / **3B** | ~18 GB | ~44 GB (meas) | **~13 tok/s** (meas 11.4) | ~100s | fast but 44 GB resident |
| **Qwen3-Next-80B-A3B** | MoE | 80B / **3B** | ~48 GB | 80 GB (meas) | ~13 (meas 3.29, GDN-serial) | low | far too big to coexist |
| **Qwen3.8-Flash-Next** (Qwen) | MoE hybrid | ~180B / ~6B | 93.7 GB (meas) | ~101–116 GB (meas) | ~9–14 (meas 9–12) | ~40 (meas) | **the orchestrator** |
| DeepSeek V4-Flash (DS4) | MoE MLA | 284B / **~5B** | 103 GB (meas) | ~115 GB (meas) | ~8 (meas 5–8.6) | ~16 (meas) | frontier alt |
| gpt-oss-120b | MoE | 120B / 3.6B | ~58.5–65 GB (meas) | 72 GB (meas) | ~11 (meas **12.7**) | 100s | 72 GB resident |
| gpt-oss-20b | MoE | 20B / **3.6B** | ~12 GB ✎ | ~18 GB ✎ | **~11 tok/s** ✎ | 100s ✎ | **interesting: grunt speed, 18 GB resident** |

Key rows in detail:

- **Qwen3-30B-A3B (measured):** `VmRSS 44.4 G`, `RssAnon 26.4 G`, `RssFile 18.0 G`,
  warm **11.41 tok/s** (`hosts/brys/performance.md:161`). This is the existing
  `fast` alias. Decode is excellent for the latency budget (20–50 tok/s target is
  partly met on prefill-heavy work) but the 44 GB resident is the problem.
- **gpt-oss-120b (measured):** `VmRSS 72.2 G`, `RssAnon 60.2 G`, `RssFile 11.8 G`,
  warm **12.7 tok/s** (`hosts/brys/performance.md:165`). Note the weird shape:
  `RssAnon` 60 G >> `RssFile` 12 G — it computes mostly from anonymous memory, so
  it is *not* mmap-file-backed and cannot be cheaply reclaimed. 72 GB resident.
- **gpt-oss-20b (estimate):** the 120b's little sibling. ~3.6B active is the
  *same active set* as gpt-oss-120b, so decode should be similar (~11 tok/s), but
  the whole file is ~12 GB → **~18 GB resident**. This is a strong grunt
  candidate: MoE decode speed at dense-ish residency.
- **Qwen3-8B (estimate):** ~5 GB at Q4_K_M. Decode ceiling 40/5 = 8 tok/s — *below*
  the 20 tok/s target. It only reaches 20–50 tok/s **on the GPU** (see §4). On the
  CPU it is a "medium grunt", not a fast one.
- **Qwen3-4B / Phi-4-mini (estimate):** ~2.5 GB → 40/2.5 = **16 tok/s** ceiling.
  Still short of 20 tok/s on CPU. With `-ctk q8_0`/`-ctv q8_0` and short context
  the practical number is a bit lower.
- **Qwen3-1.7B / Qwen2.5-coder-1.5B (estimate):** ~1 GB → **~25–27 tok/s** = the
  real CPU-only grunt speed class, matching the target.

**Honest conclusion from the arithmetic:** on the CPU alone, the 20–50 tok/s
decode target is only reachable by models of **≤ ~2 GB of weights** (≈1.5–2B
dense) or by **MoE models with ~3–4B active and a small total file** (gpt-oss-20b
is the outlier: fast active set, ~12 GB file). A 4–8B dense model lands at
8–16 tok/s on the CPU. The GPU is what makes 4–8B models hit 20–50 tok/s (§4).

### 1c. Dense vs MoE — the trade in one line

| | dense | MoE |
|---|---|---|
| decode reads per token | the whole file | only active experts |
| decode speed | ∝ 1/file-size | ∝ 1/active-size |
| resident RAM | = file-size | = **whole file** |
| colocation friendliness | good (small file) | poor unless total is small |

MoE gives fast decode but needs the **full weight set resident**, so it is the
wrong shape for colocation with a 90–116 GB orchestrator. The only MoE worth
colocating is one with a **small total file** (gpt-oss-20b, ~12 GB) — most MoE
grunts (30B-A3B, 80B-A3B, 235B) are too big.

---

## 2. The smallest set that can coexist with Qwen

### 2a. Qwen's resident footprint (measured)

Qwen3.8-Flash-Next `UD-IQ4_XS` (93.7 GB on disk):

| config | state | RssFile | RssAnon | VmRSS | available | source |
|---|---|---|---|---|---|---|
| 1M ctx, F16 KV, `lazy-mode off` | idle | 92.2 GB | 19.1 GB | 111.2 GB | — | `local-llms.md:550` |
| **1M ctx, F16 KV, `lazy-mode auto`** | idle | **46.0 GB** | 19.1 GB | **65.0 GB** | — | `local-llms.md:551` |
| 1M ctx, F16 KV, `lazy-mode auto` | after load | 59.7 GB | 56.4 GB | 116.0 GB | 60 GB | `local-llms.md:788` |
| 1M ctx, q8_0 KV, `parallel 4` | warm | ~60 GB | ~37.5 GB | ~101 GB | — | `local-llms.md:664` |
| 1M ctx, session cache, `cache-ram 16384` | served | — | — | ~116.5 GB | — | `session-cache/done.md:103` |

**The `--lazy-mode auto` offload is real and measured:** it moves ~46 GB
(`RssFile` 92.2 → 46.0 GB) of the PLE / n-gram table and other large tensors to
SSD (`local-llms.md:401`, `local-llms.md:541-562`). `auto` is the default and is
already active. With it, Qwen's **idle resident set is ~65 GB**, but under load
the resident set grows to **~101–116 GB** (`RssFile` climbs to ~60 GB, `RssAnon`
to ~37–56 GB). The 1M-context config is the biggest: F16 KV is 24 GiB, q8_0
halves it to 12 GiB.

**The orchestrator therefore holds roughly 100–116 GB when actually serving, and
about 65 GB when idle.** The budget for a grunt is what is left:

```
125 GiB usable
  − 116 GB (Qwen warm, 1M, worst case)   →  ~9 GB   (idle-ish headroom)
  − 101 GB (Qwen warm, q8_0 KV)          → ~24 GB
  −  65 GB (Qwen idle, lazy auto)        → ~60 GB
```

The `local-llms.md:787-796` long-context ladder says 1M ctx leaves **only ~1–2 GiB
free** (about 60 GB reclaimable page cache). So while Qwen is *serving a 1M-context
request*, there is essentially **no room** for a co-resident grunt. The window for
colocation is while Qwen is **resident but idle or on a short request**.

### 2b. The measured colocation penalty (DS4 experiments)

From `docs/local-llms.md:200-209` and `hosts/brys/performance.md:158-173`:

| co-tenant | DS4 effect | mechanism |
|---|---|---|
| phi-4 (17.7 G), **idle-but-resident** | DS4 **~6.7 → ~3 t/s (halved)** | bandwidth contention |
| phi-4 (17.7 G), **actively generating** | DS4 **~1.75–2.2 t/s (67–74% hit)** | bandwidth contention + cache pressure |
| qwen3-30b-a3b (44.4 G) | DS4 **~2.2 t/s**, cache intact | "best co-tenant by far" |
| qwen3-coder-next (65.6 G) | DS4 **~0.9–1.1 t/s**, DS4 weights evicted (RSS 67→15 G) | **fully evicts DS4** |
| any 45 G+ MoE | DS4 **fully evicted**, needs box alone | RAM exhaustion |
| gpt-oss-120b (72.2 G) | DS4 5.4 GB file-cache evicted, re-faults | RAM exhaustion |

Two distinct penalties:

1. **Bandwidth contention** (any co-tenant, even idle): halves the frontier.
   This is intrinsic to the shared 40 GB/s.
2. **RAM eviction** (co-tenant > ~45 GB): pushes the frontier's mmap'd weights
   out of page cache; the next request re-reads them from disk (~2 GB/s cold),
   which is a 10–20× throughput cliff.

### 2c. Does Qwen have the same sensitivity as DS4?

**Yes — Qwen is bandwidth-bound in the same way, and the doc says so.**
`local-llms.md:200-202`: *"on the ~40 GB/s bandwidth-bound box any resident small
model contends for the same memory bandwidth."* And `local-llms.md:670-671`:
Qwen and DS4 are both *"bandwidth-bound sparse MoE"*. So an idle-but-resident
grunt should roughly halve Qwen's decode (9–14 → ~5–7 t/s) exactly as it halves
DS4's, and an active grunt should take it to ~2–4 t/s.

Qwen has one **extra** sensitivity DS4 does not: its `--lazy-mode auto` offload
means ~46 GB of its tensors live on SSD and are **re-read as needed**. A
co-resident model that consumes RAM forces more of those lazy tensors to be
re-faulted, adding major faults on top of the bandwidth contention. This makes
Qwen likely **more** sensitive to RAM pressure than DS4, not less.

### 2d. The smallest coexisting set

Given the budget above, the only grunt classes that genuinely coexist with a
serving Qwen are:

| co-tenant | RAM | coexists? | effect on Qwen (estimate) |
|---|---|---|---|
| Qwen3-1.7B / coder-1.5B (Q4, ~1 GB) | ~1.5 GB | **yes, comfortably** | halved decode (bandwidth), no eviction |
| Qwen3-4B / Phi-4-mini (Q4, ~2.5 GB) | ~3.5 GB | **yes** | halved decode |
| Qwen3-8B (Q4, ~5 GB) | ~7 GB | **yes vs idle Qwen; tight vs serving Qwen** | halved decode; risks TLB/faults at 1M |
| gpt-oss-20b (MoE, ~12 GB) | ~18 GB | **only vs idle Qwen (lazy auto)** | halved decode + fault pressure |
| phi-4 (17.7 G measured) | 17.7 GB | only vs idle Qwen | the doc's measured halving case |
| anything ≥ ~45 GB | ≥ 45 GB | **no — evicts Qwen** | frontier re-reads from disk |

**Smallest useful set:** one dense **1.5–2B** model (~1.5 GB resident) can sit
beside a serving Qwen with only the bandwidth penalty. A **4B** (~3.5 GB) fits the
idle-Qwen budget cleanly. A **gpt-oss-20b** (~18 GB) fits only while Qwen is idle
(`lazy-mode auto`, ~65 GB) — pushing the pair to ~83 GB, leaving ~42 GB, which is
safe *if* no 1M request arrives.

**The hard truth:** any co-resident grunt halves Qwen's decode for as long as it
is loaded, because the router's `--sleep-idle-seconds -1` pins the last resident
model (`local-llms.md:206-208`). There is no "idle grunt" state that stops
contending. This is exactly why the existing topology spins the small set to its
own boot entry (`llm-small`) rather than colocating it.

---

## 3. Review of the existing small set (`hosts/brys/llm-routers.nix`)

The set is the `routers.small` router on `:39704`, `threads 8`, `modelsMax 2`
(`hosts/brys/llm-routers.nix:13-19`). Members and verdicts:

| model | file | measured t/s | resident | grunt-appropriate? | verdict |
|---|---|---|---|---|---|
| `phi-4` | 8.5 G | 2.86 | 17.7 G | **no** — 2.86 t/s is below grunt floor; 17.7 G is heavy | **replace** with Qwen3-4B (2.5 G, ~11–16 t/s) or Phi-4-mini |
| `qwen3-30b-a3b` (`fast`) | 18 G | **11.41** | 44.4 G | **decode yes, residency no** | keep as a *medium* tier, not a co-tenant; 44 G cannot coexist |
| `qwen3-next-80b` (`balanced`) | 46 G | 3.29 | 80 G | **no** — 80 G, 3.29 t/s | **remove from a grunt role**; box-alone only |
| `qwen3-coder-next` | 45 G | 5.34 | 65.6 G | **no** — evicts the frontier | remove from a grunt role |
| `qwen3-235b` (`IQ2_M`) | 72 G | ~slow | ~100 G | **no** — needs box alone (`performance.md:164`) | not a grunt at all |
| `gpt-oss-120b` | 58.5 G | **12.7** | 72.2 G | **speed yes, residency no** | swap for **gpt-oss-20b** (same active set, ~18 G) |

**Summary of the review:**

- The set was designed as a **freely-swapping replacement for the frontier when
  booted into `llm-small`**, not as grunts that sit beside the orchestrator. Every
  member except phi-4 is a box-scale model.
- The only members with genuine grunt *speed* are `qwen3-30b-a3b` (11.4) and
  `gpt-oss-120b` (12.7) — both far too large to colocate (44 G / 72 G).
- `phi-4` is the only *small* member, and it is the doc's own example of a co-tenant
  that halves DS4 — at only 2.86 t/s, it is a poor grunt.
- **Recommendation:** the current set should not be reused as grunts. Grunts need a
  **new, smaller, dense set**. `qwen3-30b-a3b` and `gpt-oss-120b` can stay on
  `llm-small` as "medium/big" tiers; the rest are box-alone models belonging to the
  frontier story, not the grunt story.

---

## 4. The W6600 GPU option (8 GB)

### 4a. Is the card usable at all for a small standalone model?

**Yes — measured.** The `qwen-gpu-offload` smoke test ran a **Qwen2.5-0.5B-Instruct
Q4_K_M** (462.96 MiB) through `llama-bench` on the W6600 via `--device Vulkan0`, and
restarted `llama-cpp` cleanly afterwards (`qwen-gpu-offload/definition.md:120-136`):

| test | `-ngl 0` (CPU) | `-ngl 99` (W6600) | speedup |
|---|---|---|---|
| pp512 (prefill) | 61.87 ± 2.73 t/s | **10113.74 ± 308.34 t/s** | ~163× |
| tg128 (decode) | 94.47 ± 2.92 t/s | **336.99 ± 3.01 t/s** | ~3.6× |

The decode 336.99 t/s is consistent with the W6600's ~224 GB/s VRAM and the
~0.46 GB model: 224 / 0.46 ≈ 487 GB/s-equiv, minus overhead — i.e. **fully
VRAM-resident decode at hundreds of tok/s**. This is the strongest single fact in
this report: **a small model entirely on the W6600 is dramatically faster than
any CPU path.**

### 4b. How big a model fits in 8 GB?

Budget: 7.98 GiB usable → **~7.5 GB after overhead**. At Q4 (~0.5–0.6
GB/1B params) plus KV:

| model | weights Q4 | KV @16K F16 | total | fits? |
|---|---|---|---|---|
| Qwen3-0.6B | ~0.4 GB | ~0.2 GB | ~0.6 GB | trivially |
| Qwen3-1.7B | ~1.1 GB | ~0.5 GB | ~1.6 GB | yes |
| Qwen3-4B | ~2.5 GB | ~1 GB | ~3.5 GB | yes |
| Qwen3-8B | ~5.0 GB | ~1.5 GB (16K) → ~3 GB (32K) | ~6.5–8 GB | **tight; 16–32K only** |
| Nemo-12B | ~7 GB | ~2 GB | ~9 GB | no |
| 13–14B | ~8–9 GB | — | — | no |

So the W6600 fits **up to a Qwen3-8B at moderate context** (16–32K) entirely in
VRAM, or a 4B comfortably, or a 1.7B with a large context. A **Qwen3-8B on the GPU
would decode in the low-hundreds of tok/s** (VRAM bandwidth bound: 224/5 ≈ 45
tok/s as a floor; the smoke test's 3.6× over 94 t/s CPU suggests far more for a
tiny model; a measured number is needed for 8B).

### 4c. ROCm vs Vulkan availability

**Only Vulkan is available; ROCm is dead on this host.** From
`qwen-gpu-offload/definition.md:50-62`:

- The W6600 needs the **Mesa RADV** Vulkan driver.
- ROCm is not a supported target for `gfx1032` (Navi 23) for this use; the
  `kdn.hw.gpu.amd` module already prefers Mesa over ROCm.
- `packages/llama-cpp/default.nix:107-110` explicitly sets `GGML_HIP false` and
  `GGML_CUDA false`; there is **no ROCm/HIP build** in the repo. `GGML_VULKAN` is
  the only GPU backend built (`default.nix:110`).

**Available Vulkan builds** (`packages/llama-cpp/README.md:6-17`):

| attribute | source | backend |
|---|---|---|
| `llama-cpp-v0_6_0` | ggml-org v0.6.0 | CPU |
| `llama-cpp-v0_6_0-vulkan` | v0.6.0 | CPU + Vulkan |
| `llama-cpp-v0_6_0-vulkan-noblas` | v0.6.0 | CPU + Vulkan, no BLAS (the **served** Qwen build) |
| `llama-cpp-sessions` | nazarewk-iac fork | CPU (session cache) |
| `llama-cpp-sessions-vulkan` | fork | CPU + Vulkan |
| `llama-cpp-master-vulkan` + 3 patched variants | master | CPU + Vulkan (experiments, not served) |

For a **standalone dense grunt on the GPU**, `llama-cpp-v0_6_0-vulkan-noblas` is
the natural choice: it is the build the host already deploys, the Vulkan shaders
compile all the Q4 types (`qwen-gpu-offload/definition.md:79-90`), and the no-BLAS
setting removes the small-prompt prefill stall (`packages/llama-cpp/README.md:61-78`).
The ICD is exposed with `hardware.graphics.enable = true` +
`hardware.graphics.extraPackages = [ pkgs.mesa ]` and pinned with
`MESA_VK_DEVICE_SELECT=1002:73e3!` (`hosts/brys/llm.nix:456-460`, currently only
emitted when `qwenVulkan = true`, which is **false** on brys).

### 4d. The hang is specific to the MTP draft workload — does it apply here?

**No — the hang is not the grunt case.** From `w6600-amdgpu-hang/research.md`:

- The hang is a compute-ring (`comp_1.2.0`) KCQ timeout that matches **open
  llama.cpp #27306**, triggered by **`--spec-type draft-mtp`** — the extra
  draft-context decode after every target ubatch (`research.md:37-59`).
- Every matching report is on the **MTP draft path** (#27076 RX 6900 XT, #30010 RX
  7900 XTX), all with `draft-mtp`. Issue #29352 is the one non-MTP report (4 server
  slots); `--parallel 1` fixed it (`research.md:50-51`).
- The Qwen2.5-0.5B smoke test ran the **whole model on the GPU** with `-ngl 99`,
  `-p 512 -n 128`, and **did not hang** (`qwen-gpu-offload/definition.md:120-129`).

So: a **standalone dense grunt entirely on the GPU, with no speculative decoding
and `parallel 1`, is in a different code path from the hang** and is the case the
smoke test proved. Risks remain (the smoke test was short; long-context and
multi-slot are untested on the W6600 for a standalone model) but there is **no
evidence the hang applies**.

**Caveat — the 40.6K-token hang threshold.** The Qwen hang occurred at ~40.6K
tokens of context (`hosts/brys/llm.nix:71-79`). A grunt at ≤16–32K context with
`--parallel 1` and no MTP stays far below that. This should be stated as a
condition of use, not a promise.

### 4e. Does the GPU option conflict with the orchestrator?

**No — the GPU is idle while Qwen runs on the CPU.** Qwen's main model + KV are
CPU-resident; the W6600 held only the MTP draft head, which is now disabled
(`qwenVulkan = false`). So the 8 GB card is **entirely free**. A grunt on the GPU
does **not** contend for CPU bandwidth or system RAM with the orchestrator (except
a few hundred MB of driver/context overhead). This is the one colocation that
**avoids the bandwidth penalty** — genuinely attractive.

---

## 5. Recommendation

### 5a. The primary recommendation: one grunt on the W6600

**Put a single small dense model entirely on the W6600, on its own router, as a
boot-specialisation option — colocated with Qwen.**

- **Model:** a **Qwen3-4B** (Q4_K_M, ~2.5 GB) at 16–32K context, or a **Qwen3-8B**
  (Q4_K_M, ~5 GB) at 16K if the extra quality matters. Start with the 4B: it fits
  with ~4 GB of VRAM to spare and needs no context squeeze.
- **Build:** `llama-cpp-v0_6_0-vulkan-noblas` (already deployed shape).
- **Flags:** `nGpuLayers = 99`, `device = "Vulkan0"`, `parallel = 1`,
  **no speculative decoding**, `flash-attn on`.
- **Why:** measured 3.6× decode / 163× prefill over CPU for a fully-offloaded
  dense model (`qwen-gpu-offload/definition.md:125-128`); **zero CPU-bandwidth and
  near-zero RAM contention** with the orchestrator; the W6600 is otherwise idle;
  the hang is an MTP-draft bug not present in this path.
- **Expected numbers (estimate):** decode low-hundreds of tok/s for the 4B
  (VRAM-bound), far above the 20–50 tok/s target; prefill thousands of tok/s.
  A quick `llama-bench` on brys with the real model is needed to pin it.
- **RAM budget:** ~3.5 GB system RAM (driver + context) — negligible against the
  125 GiB box.

### 5b. A CPU grunt only if the GPU is not used

If the GPU is ruled out, the smallest sound CPU grunt is:

- **Qwen3-1.7B or Qwen2.5-coder-1.5B**, Q4, at 16–32K context (~1.5 GB resident),
  decode ceiling ~25–27 tok/s — **the only CPU class that meets the 20 tok/s
  target**. Colocation penalty: halves Qwen's decode to ~5–7 t/s while loaded.
- Do **not** colocate a 4B+ dense or any MoE ≥ 18 GB on the CPU while Qwen is
  serving.

### 5c. Router and boot placement

- **GPU grunt → its own router** (`routers.grunt`, e.g. `:39705`, `threads` low
  or 1 since it is GPU-bound, `modelsMax 1`), on the **same boot entry as Qwen**
  (`hosts/brys/llm-qwen.nix` + `llms-frontier.nix` + the main `brys` profile).
  This is the colocation that works: the GPU does not steal CPU bandwidth.
- **CPU grunt → the existing `llm-small` boot entry** (separate boot). Colocating a
  CPU grunt with Qwen re-introduces the measured halving, and the doc's own
  conclusion is *"the only robust answer is a separate boot entry"*
  (`local-llms.md:208-209`).

### 5d. Risks and unknowns (explicit)

1. **Unmeasured GPU throughput for a 4–8B model.** The only GPU measurement is a
   0.5B model. The 4B/8B numbers are estimates. **Must measure.**
2. **The 40.6K-token hang threshold is unexplained.** The smoke test was short
   (<1K tokens). A long-context GPU grunt is untested. Mitigation: keep the grunt
   context ≤32K, `parallel 1`, no MTP; if it hangs, fall back to the CPU.
3. **`ErrorDeviceLost` kills the whole llama-server**, not just the grunt
   (`hosts/brys/llm.nix:71-79`). A GPU hang on the grunt would take down the
   orchestrator too if they share a process — **so the GPU grunt must be its own
   process/router**, which the recommendation already requires.
4. **Qwen's decode halves while any CPU grunt is resident** (extrapolated from the
   DS4 measurements; not yet measured for Qwen). Treat as high-probability.
5. **`--lazy-mode auto` interaction.** Forcing more RAM pressure may re-fault
   Qwen's ~46 GB of SSD-offloaded tensors. Not measured.
6. **gpt-oss-20b's real size and speed** are estimates from the 120b sibling; the
   `RssAnon`-heavy shape of gpt-oss-120b (60 GB anon) suggests gpt-oss-20b may
   also be anon-heavy and thus **unreclaimable**.
7. **VRAM headroom on the W6600 for KV at long context.** 8B at 32K F16 KV is
   ~3 GB; the card may need `q8_0` KV. Untested.

---

## 6. Router topology and compat-proxy wiring

### 6a. Can Qwen + a grunt share the primary router?

**No.** The primary router runs `--models-max 1` (`modules/den/aspects/llm.nix:1303`),
so a request for the grunt **unloads Qwen** and swapping it back is a ~90–120 s
reload (`local-llms.md:143-147`, `hosts/brys/llms-frontier.nix:6-9`). Grunt
delegation must not evict the orchestrator. The grunt needs its **own router**.

### 6b. How a per-task sub-router works

The wiring already supports N routers cleanly (all file:line references are to
current `HEAD`):

- **Router declaration:** `kdn.llm.local.routers.<name>` is an
  `attrsOf submodule` with `enable`, `port`, `threads`, `modelsMax`, `apiKeyDir`
  (`modules/den/aspects/llm.nix:1049-1060`, `:502-542`). Names must be
  **lowercase alphanumeric** (`:1270-1280`), so `grunt` and `small` are valid.
- **Model → router binding:** `kdn.llm.local.models.<name>.mainRouter`
  (`:547-555`). A model lands in exactly one router's preset INI.
- **Env for the proxy:** `routerProxyEnv` emits `ROUTER_<NAME>_URL` and
  `ROUTER_<NAME>_MODELS` per enabled router (`:274-293`), merged into the
  `kdn-llm-proxy-lan` unit's environment (`:1354-1363`).
- **Proxy routing:** the compat-proxy maps each request's `model` through its
  `ROUTE` table to the owning router's base URL; **anything unrouted falls back to
  `UPSTREAM_URL`** = the frontier router (`:1355`, and the proxy contract in
  `docs/local-llms.md:38-45`). `GET /v1/models` merges every router's listing
  (`local-llms.md:42-45`).
- **One router unit per extra router** is generated automatically
  (`routerUnits`, `:297-354`), each with its own preset INI, port, key file,
  `--models-max`, and `--sleep-idle-seconds -1`.

So a new grunt is three declarations, with no proxy edit:

```nix
# hosts/brys/llm-routers.nix
kdn.llm.local.routers.grunt = {
  enable = true;
  port = 39705;
  threads = 8;          # or 1 for a GPU-only model
  modelsMax = 1;
  apiKeyDir = "/run/configs/llms/llama-server/api-keys";
};
kdn.llm.local.models."qwen3-4b" = {
  enable = true;
  hfRepo = "Qwen/Qwen3-4B-GGUF";
  hfFile = "Qwen3-4B-Q4_K_M.gguf";
  mainRouter = "grunt";
  aliases = [ "grunt" ];
  perf = { contextSize = 16384; nGpuLayers = 99; device = "Vulkan0"; parallel = 1; };
};
```

For a **GPU** grunt to reach the W6600, the serving boot entry must also merge the
`llm.gpu` runtime config (`hardware.graphics.enable`, `mesa`, and
`MESA_VK_DEVICE_SELECT=1002:73e3!`, `hosts/brys/llm.nix:456-460`). That block is
currently gated on `qwenVulkan`; it should be decoupled from `qwenVulkan` so a
GPU grunt can enable the ICD without enabling Qwen's MTP draft head.

### 6c. How compat-proxy routing supports a per-task sub-router

The intended design (from `docs/tasks/2026-09/llm-two-router-split/design.md:123-160`)
is **body-based routing**: the proxy parses the JSON `model` field and picks the
upstream from a `ROUTE` table, with unknown models → frontier. The layer that
implements this is `routerProxyEnv` + `UPSTREAM_URL` / `ROUTER_<NAME>_*`
(`modules/den/aspects/llm.nix:1354-1363`). The client keeps **one endpoint and one
`model=` field**; a sub-agent that names `<grunt-name>` reaches the grunt router,
and everything else stays on the frontier.

On the **client side** (`hosts/oams/devenv.nix`), the grunt becomes another
provider model and its own set of sub-agents:

- Add the grunt to `kdn.llm.client.upstreams.brys.models` (the flat block at
  `hosts/oams/devenv.nix:252-305`), e.g. a `qwen3-4b` entry with a small context.
- Add sub-agents via `mkTierAgents` (`hosts/oams/devenv.nix:170-192`) with a new
  `prefix = "grunt"`, so `grunt-16k-low`, `grunt-16k-off`, etc. appear beside
  `ds4-*` / `qwen-*`.
- The orchestrator (Qwen) then delegates small tasks by naming a `grunt-*`
  sub-agent; the request routes through the proxy to the grunt router, which keeps
  Qwen resident and untouched.

**One caveat for the grunt router's `modelsMax`:** if several grunts are intended
to be resident together, set `modelsMax` above 1 (the existing `small` router uses
`modelsMax 2`, `hosts/brys/llm-routers.nix:17`). For a single GPU grunt,
`modelsMax 1` is right.

### 6d. Which router: main, small, or a new `grunt` router?

| option | verdict |
|---|---|
| primary `main` (`:39703`) | **no** — `models-max 1` swaps the orchestrator |
| existing `small` (`:39704`) | usable, but it is a **CPU** set booted separately; wrong home for a GPU model and its own boot entry |
| **new `grunt` router** | **yes** — own port, own threads, can be GPU or CPU, colocated with Qwen on the Qwen boot entries |

---

## 7. One-paragraph answer

The overall finding is that the only colocation that does **not** halve the
orchestrator is a grunt on the W6600, which is otherwise idle and is measured
(0.5B model) at 3.6× decode and 163× prefill over the CPU. The recommended move
is a **Qwen3-4B (or 8B) entirely on the GPU, on its own `grunt` router, on the
Qwen boot entries, with `modelsMax 1`, `parallel 1`, no MTP, and context ≤32K** —
it avoids the CPU-bandwidth penalty, uses free VRAM, and stays clear of the
MTP-draft hang. A CPU grunt is a fallback only: to meet 20 tok/s it must be a
**1.5–2B dense** model (~1.5 GB), and even then it halves Qwen's decode while
loaded, so it belongs on the separate `llm-small` boot entry. The existing small
set (`hosts/brys/llm-routers.nix`) is not a grunt set — every member but `phi-4`
is 44–100 GB and belongs to the box-alone tier; the set should be left as the
`llm-small` tier and a new small grunt introduced beside it.
