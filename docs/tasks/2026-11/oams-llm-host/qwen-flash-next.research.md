# Can `qwen3.8-flash-next` run on `oams` (12 GB VRAM, 64 GB RAM)?

Research-only report, 2026-11-05. No files changed, no benchmarks run.
Every number is either **VERIFIED** (cited) or **ESTIMATE** (arithmetic shown).
Sources: this repo's own measured docs, the official Qwen/Unsloth model cards, and
current llama.cpp issue threads.

---

## TL;DR

- **256K context is feasible on oams.** This report's first version wrongly
  compared the GGUF file size to RAM; with `--lazy-mode auto` + `mmap` the
  weights are file-backed page cache (brys serves the 93.7 GB file in **54.1 GiB
  RSS**), so what must fit in RAM is the **KV cache**, not the weights. At 256K
  that is **3.2 GB (q8_0) / 6.4 GB (F16)**, plus a small prompt cache and compute
  buffers: ~7-10 GB anonymous, against 45-50 GiB usable. **It fits.**
- **1M is the part that does not comfortably fit**, and 256K is the sensible
  target; see §2.1 for the arithmetic.
- **The "active set fits in 12 GB VRAM" claim is TRUE but nearly irrelevant to
  decode speed.** Decode reads 10 of 512 routed experts chosen unpredictably
  each token, from **RAM**, and VRAM residency of one active set does not remove
  that bandwidth cost. What VRAM helps with is the attention + shared-expert +
  KV path. So expect oams decode to be governed by RAM bandwidth, roughly in
  brys's league, not 12x faster because of the bigger GPU.
- **Disk cost is the real trade-off**: 82-94 GB for this model, affordable on
  oams's 530 GB free but not "low". Run `qwen3.5-35b-a3b` (17.5 GB, full 256K) as
  the everyday model and treat flash-next on oams as an experiment, not the default.

---

## 1. Model facts — ground truth

### 1.1 What the model actually is — VERIFIED

Name `qwen3.8-flash-next` is a local alias. The base repo is
`Qwen/Qwen3.8-Flash-Next`, architecture `qwen4_exp`
([config.json](https://huggingface.co/Qwen/Qwen3.8-Flash-Next/raw/main/config.json),
[unsloth model card](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF)).

| Property | Value | Source |
| --- | --- | --- |
| Total params | 125 B main + 51 B n-gram embedding + 4 B MTP head = **~180 B** | Unsloth card (shows "177B params") |
| Active params / token | **~6 B** (125 B main is sparse; n-gram table is a lookup) | Unsloth card "125B with 6B activated" |
| Experts | **512**, **10 routed active** + **1 shared** per token | config `num_experts`, `num_experts_per_tok` |
| Shared expert size | intermediate **640** (1 per layer, always on) | config `shared_expert_intermediate_size: 640` |
| Layers | 48; layout `12 × (3×(Gated DeltaNet→MoE) → 1×(Qwen Sparse Attention→MoE))` | config `layer_types`, Unsloth card |
| Hidden size | 2560 | config |
| Full-attention layers | `full_attention_interval: 4` → **12 of 48** (25%) are full attention; **36 are linear (GDN)** | config |
| QSA (full) heads | 24 Q, **2 KV**, head_dim **256**, rope dim 64 | config |
| GDN (linear) heads | 48 V, 16 QK, head_dim 128 | config |
| Context native / max | **262 144** native, extensible to **1 000 000** (YaRN) | config `max_position_embeddings`, card |

**Is it really hybrid linear + periodic full attention?** Yes — **VERIFIED**. The
architecture is **Gated DeltaNet (linear attention) in 36 layers + Qwen Sparse
Attention (full, top-k micro-block sparse) in 12 layers**, every 4th layer. This
matches the repo's own architecture note
([qwen-flash-next-quant/definition.md:47-54](docs/tasks/2026-10/qwen-flash-next-quant/definition.md)).

### 1.2 Full-attention KV cache cost per token — VERIFIED, arithmetic shown

Only the **12 full-attention layers** hold a token-growing KV cache; the 36 GDN
layers keep a constant-size recurrent state (no per-token KV). Formula:

```
per-token KV = (full-attn layers) × (kv heads) × (head_dim) × (K and V) × (bytes)
             = 12 × 2 × 256 × 2 × 2 bytes   (F16)
             = 24 576 bytes = 24.0 KiB/token   (F16)
             = 12.0 KiB/token                  (Q8_0, ≈half)
```

This **exactly matches the brys measurement**: the repo records "KV is 24 KiB/token
at F16 … 6/12/24 GiB at 256K/512K/1M"
([done.md:115-119](docs/tasks/2026-10/qwen-flash-next-quant/done.md)) — a strong
cross-check that the formula and the config agree.

| Context | KV @ F16 | KV @ Q8_0 |
| --- | ---: | ---: |
| 256K native | 6.0 GiB | 3.0 GiB |
| 512K | 12.0 GiB | 6.0 GiB |
| **1M** | **24.0 GiB** | **12.0 GiB** |

(3.5-35B-A3B for comparison: 40 layers, 10 full-attn → 20 KiB/tok F16, 10 KiB Q8.)

### 1.3 Smallest published GGUFs — VERIFIED

From the Unsloth card's quant table (sizes on disk, whole repo):

| Quant | Size | Note |
| --- | ---: | --- |
| UD-IQ1_S | **66.4 GB** | smallest published |
| UD-IQ1_M | 68 GB | |
| UD-Q2_0 | 70.5 GB | |
| UD-IQ2_XS | 75.8 GB | |
| UD-Q2_K_XL | 79.6 GB | |
| UD-IQ3_XXS | **83.6 GB** | ≈ repo's "comfortable, most KV room" |
| UD-Q3_K_XL | 89.5 GB | |
| UD-IQ4_XS | **93.7 GB** | brys's choice |
| UD-Q4_K_XL | 111 GB | |
| Q8_0 | 192 GB | |

The repo's own measured shard totals agree
([qwen-flash-next-quant/definition.md:73-83](docs/tasks/2026-10/qwen-flash-next-quant/definition.md)):
IQ4_XS 87.2 GB measured, IQ3_XXS 76.3 GB, IQ2_K_XL 73.5 GB, IQ1_S 67.6 GB.

**There is no "small enough" quant.** Even IQ1_S, the tiniest, is 66 GiB.

### 1.4 How much is "always active" vs routed — ESTIMATE (arithmetic)

This decides what *must* be in VRAM for speed. Per decode token you must read:
embeddings (lookup) + all attention/GDN weights + **shared expert** + router +
**10 of 512 routed experts per layer** + the full KV cache.

Per-layer expert params (gate+up+down = 3 × 2560 × 640 = 4.92 M params/expert):

```
routed active   = 10 × 4.92M × 48 layers = 2.36 B params  (must read every token)
shared expert   =  1 × 4.92M × 48 layers = 0.24 B params  (must read every token)
attention+GDN   ≈ 1.73 B params                           (must read every token)
------------------------------------------------------------
resident compute per token ≈ 4.3 B params
```

Total weight file = ~177 B params. So **only ~4.3 B of ~177 B (≈2.4%) is read
per token**; the other ~97% are idle experts. At IQ3_XXS (~3.06 bits/param) that
is **≈1.54 GiB of weight traffic per token**; at IQ4_XS (≈4.25 bits) **≈2.14 GiB**.
(This matches the repo's statement that for this model "the dense weights are
about 80% of the bytes one decode token reads" — the 4.3 B always-active compute
+ the n-gram lookups + KV dominate, the routed experts are a minority of per-token
bytes but the majority of *file size*.)

**Key insight for the claim:** the "active expert set" that fits in 12 GB is
exactly this ~4.3 B-param compute graph (≈1.5–2.1 GiB at 3–4 bit) plus the
always-staged experts. That fits in 12 GB easily. **But the routed experts that
are *not* active still have to be read from RAM on every token** (any of 512 can
be chosen), so VRAM residency of the active set does **not** remove the RAM
bandwidth cost — see §3.3.

---

## 2. Feasibility on 12 GB VRAM + 64 GB RAM

### 2.1 CORRECTED 2026-11-05: the file size is not the RAM requirement

The first version of this report compared the GGUF file size against RAM and
concluded "does not fit". **That comparison was wrong**: llama.cpp serves this
model with `--lazy-mode auto` + `mmap`, so the weights are **file-backed page
cache**, not anonymous resident memory. The proof is on `brys` itself:

> `brys` serves `qwen3.8-flash-next` from a **93.7 GB** file
> (`UD-IQ4_XS` 43.8 + 49.8 GB + 4.1 GB MTP), and its measured RSS at **1M
> context is 54.1 GiB** ([docs/local-llms.md:506](docs/local-llms.md)),
> not 94 GB. The `--lazy-mode` lever is documented as freeing **~46 GB**
> (`RssFile` 92.2 → 46.0 GB) precisely because the tensors are file-backed.

So the binding constraint is the **anonymous** memory: KV cache, prompt cache
(`--cache-ram`), and compute buffers. The weights cost SSD read bandwidth, not
RAM residency.

oams physical RAM ≈ **62 GiB**; headless usable ≈ **45–50 GiB**.
oams storage: **1.8 TB NVMe (Corsair MP600 GS), measured 9.0 GB/s sequential
read**, ZFS `primarycache=all` + `lz4` on the pool — faster than brys's storage.

```
--- anonymous RAM at 256K (the question that matters) ---
KV per token, F16: 24 KiB  (12 full-attn layers x 2 KV heads x 256 head_dim)
  256K  F16 KV  =  6.4 GB     256K q8_0 KV = 3.2 GB
  512K  F16 KV  = 12.9 GB     512K q8_0 KV = 6.4 GB
    1M  F16 KV  = 25.8 GB       1M q8_0 KV = 12.9 GB

oams @ 256K q8_0: KV 3.2 GB + cache-ram 1 GB (lower from the 37 GB brys uses)
                  + compute/gen buffers ~2 GB  =  ~7-10 GB anonymous.
                  Machine has 45-50 GiB usable.  FITS COMFORTABLY.
```

**Verdict for 256K: feasible.** This is the configuration the user asked about,
and it is the right one. 1M is *not* comfortable (12.9 GB KV + the 37 GB
cache-ram brys uses must drop to ~4 GB, and prefill over 1M tokens at SSD-backed
weights is very slow), but 256K is fine.

The disk caveat stands and is the real cost: **93.7 GB** for `UD-IQ4_XS`
(82 GB for `UD-IQ3_XXS`), which is a lot against "keep disk low" — but oams has
530 GB free, so it is affordable, unlike on a small volume.

Two theoretical escapes, neither good:

- **Expert streaming (`--moe-stream`, PR #25294)** keeps routed experts on SSD with
  a per-layer cache. Upstream claims ~2.4× decode vs `--cpu-moe` mmap on a
  non-fitting model. **But it "auto-disables mmap" and needs O_DIRECT**, and on
  brys it was measured **−34% decode, −65% prefill** when the model mostly fit
  ([offload.research.md:166-181](docs/tasks/2026-10/llama-benchmark-suite/002-disk-offload/offload.research.md)).
  On oams the model *badly* does not fit, so this is the intended use — but you
  pay disk-read latency per token and the disk must sustain it for the whole run.
  **ESTIMATE: not a practical path for interactive use.**
- **The 51 B n-gram table** (~40% of params) is a pure embedding lookup. Atomic
  Chat's build separates it into its own shard so it can live on SSD and free
  ~40 GB ([definition.md:56-59](docs/tasks/2026-10/qwen-flash-next-quant/definition.md)).
  Even then the remaining ~85 GiB main model is still > 45 GiB. **Not enough.**

### 2.2 What `--n-cpu-moe` / `--cpu-moe` keeps on the GPU, and does it work on Vulkan?

**What it does — VERIFIED** (llama.cpp server docs, and repo research): `--cpu-moe`
pushes all `ffn_*_exps` (routed-expert) tensors to a CPU buffer, keeping attention,
KV, embeddings, shared expert and the dense compute on the GPU. `--n-cpu-moe N`
does the same for only the first N layers' experts (finer control when VRAM is
tight) ([serving-ops-insights.research.md:44-56](docs/tasks/2026-10/llm-model-expansion/serving-ops-insights.research.md),
[offload.research.md:113-131](docs/tasks/2026-10/llm-benchmark-suite/002-disk-offload/offload.research.md)).

**Does it work on Vulkan? YES — VERIFIED, not CUDA-only.** Current llama.cpp issue
threads show `--cpu-moe` / `--n-cpu-moe` running on Vulkan across AMD and Intel
GPUs:

- **RX 6900 XT (gfx1030, same RDNA2 as oams), 64 GB RAM, Qwen3.6-35B-A3B Q4_K_XL,
  `--cpu-moe --parallel 1`: 30.8 tok/s generation at 8.5k tokens, 37 tok/s at 1.6k**
  on ROCm; Vulkan works too but the MoE *cache* path is buggy —
  [issue #30697](https://github.com/ggml-org/llama.cpp/issues/30697).
- **RX 5700 XT (RDNA1), Qwen3.5 family with `-ncmoe 24` runs on Vulkan** —
  [issue #30039](https://github.com/ggml-org/llama.cpp/issues/30039).
- **`qwen4exp` (this exact arch) with `-ngl 99 --n-cpu-moe 25…29` runs on Vulkan**
  (Intel Arc B65/B70): **~166 pp / 13 tg at fresh context, 118 pp / 9.1–9.7 tg at
  long context** — [issue #28247](https://github.com/ggml-org/llama.cpp/issues/28247).

**But material Vulkan caveats exist — VERIFIED:**

1. **RDNA2 ~45% prefill regression** in b11010..b11856 with GDN-hybrid models
   (`qwen4exp` is GDN-hybrid). Decode (TG) unchanged. Confirmed on RX 6700 XT
   (RDNA2), independent third report on gfx1010; the regression is
   **length-dependent** (invisible at 4K, loses 5–20%+ as context grows). Suspect
   PR #28105 "sparse Flash Attention" — [#30039](https://github.com/ggml-org/llama.cpp/issues/30039).
2. **`-c` (allocated context) vs VRAM spill trap**: past ~30K the QSA top-k scratch
   (`n_kv × n_ubatch × 4` bytes) + KV can exceed VRAM and the AMD driver spills
   silently over PCIe, dropping prefill 5–7×. Fix: raise `--n-cpu-moe` with `-c`.
   Read a sudden 5–7× prefill drop as a VRAM-spill signal — [#28247](https://github.com/ggml-org/llama.cpp/issues/28247).
3. **`ggml_vk_fill` workgroup overflow**: `qwen4exp` builds a full KQ mask sized
   `n_kv × batch`; if that exceeds ~33.5M elements it hits
   `maxComputeWorkGroupCount` and aborts. Crashes once `ubatch × kv_len > ~33M`
   (≈ `-ub 1024 -c 30720`). Fix merged as PR #28592, but pin a recent build —
   [#28247](https://github.com/ggml-org/llama.cpp/issues/28247).
4. **MoE expert cache (`--moe-cache-mib`) is broken on Vulkan** — load aborts
   ([#30697](https://github.com/ggml-org/llama.cpp/issues/30697),
   [#31675](https://github.com/ggml-org/llama.cpp/issues/31675)). Plain
   `--cpu-moe` (no cache) is stable; only the cache path aborts.
5. **Vulkan pinned-host-memory allocation fails on RADV** — cosmetic; llama.cpp
   falls back to unpinned transfers ([qwen-gpu-offload/done.md:131-134](docs/tasks/2026-10/qwen-gpu-offload/done.md)).

So: **`--n-cpu-moe`/`--cpu-moe` is usable on Vulkan**, but the model you want is
GDN-hybrid, so you hit the RDNA2 prefill regression and must babysit `-c` vs
`--n-cpu-moe`. On oams the weights are SSD-backed, so the relevant question is
whether expert traffic from SSD keeps up — see the verdict in §4.

### 2.3 Context sizing — 256K fits, 1M does not

```
KV cost (12 full-attn layers x 2 KV heads x 256 head_dim = 24 KiB/token F16):
  256K:  6.4 GB F16   3.2 GB q8_0
  512K: 12.9 GB F16   6.4 GB q8_0
    1M: 25.8 GB F16  12.9 GB q8_0
```

The weights are **file-backed** (§2.1), so they do not compete with the KV cache
for RAM. What must fit is KV + prompt cache + compute buffers:

| config | anaonymous RAM | verdict on oams (45-50 GiB usable) |
| --- | ---: | --- |
| 256K, q8_0 KV, cache-ram 1 GB | ~7 GB | **comfortable** |
| 256K, F16 KV, cache-ram 8 GB | ~15 GB | **comfortable** |
| 512K, q8_0 KV, cache-ram 8 GB | ~16 GB | fits, less headroom |
| 1M, q8_0 KV, cache-ram 37 GB (brys) | ~51 GB | **too tight** — must cut cache-ram |
| 1M, q8_0 KV, cache-ram 2 GB | ~17 GB | fits RAM, but SSD-bound prefill is slow |

**256K is the sensible target**: it fits with wide margin whatever the KV type,
and it is 4x the 64K working set most agent tasks need. 1M is possible only with a
cut prompt cache and very slow first token.

### 2.4 Why the earlier "file must fit in RAM" table was wrong

The first version of this report tabulated GGUF file sizes against RAM:

| Quant | File | naive verdict |
| --- | ---: | --- |
| IQ1_S | 66.4 | "NO" |
| IQ4_XS | 93.7 | "NO" |

That table is **invalid** and is kept only to record the mistake: it treats the
file as resident. `brys` disproves it — it serves the **93.7 GB** IQ4_XS file at
**54.1 GiB RSS with 1M context** ([docs/local-llms.md:506](docs/local-llms.md)),
because `--lazy-mode auto` + `mmap` keep the tensors file-backed and reclaimable.
The correct resource model is "SSD bandwidth for weights, RAM for KV", which is
what §2.3 uses.

## 3. Expected performance

### 3.1 Published MoE-partial-offload numbers for this class

| Setup | Model | t/s | Source |
| --- | --- | ---: | --- |
| RX 6900 XT (RDNA2), 64 GB, `--cpu-moe --parallel 1` | Qwen3.6-35B-A3B Q4_K_XL | **30.8 gen @8.5k, 37 @1.6k** (ROCm) | [#30697](https://github.com/ggml-org/llama.cpp/issues/30697) |
| Intel Arc B65 (Vulkan), `--n-cpu-moe 29 -c 49152` | Qwen3.8-Flash-Next Q3_K_XL | **118 pp / 9.1–9.7 tg** @long ctx | [#28247](https://github.com/ggml-org/llama.cpp/issues/28247) |
| CPU-only 5950X + RTX 3090 Ti (reference) | Qwen3.8-Flash-Next Q4_K_XL | 15 gen / ~340 pp @30K | [definition.md:98-101](docs/tasks/2026-10/qwen-flash-next-quant/definition.md) |
| **brys, 1M ctx, CPU, competing** | Qwen3.8-Flash-Next IQ4_XS | **2.36 decode** | [local-llms.md, decisions](docs/tasks/2026-11/pi-orchestrator-model-selection/decision-prune-2026-11-04.md) |
| **brys, 1M ctx, CPU, alone** | Qwen3.8-Flash-Next IQ4_XS | **9.3 decode, 30.8 prefill** | [done.md:113](docs/tasks/2026-10/qwen-flash-next-quant/done.md) |

Note the enormous spread between "alone" (9.3) and "competing" (2.36) on the same
box — co-residency costs ~4×, which is exactly the "CPU-heavy / competing" regime
the user measured.

### 3.2 oams decode & prefill — ESTIMATE, arithmetic

oams CPU/RAM: **Ryzen 9 5900HX (Zen3 mobile), dual-channel DDR4-3200** (ROG Strix
G15 Advantage). Bandwidth ceiling:

```
DDR4-3200 dual channel = 3200 MT/s × 8 B × 2 = 51.2 GB/s theoretical
real-world COPY ≈ 60–70% → ~32–36 GB/s   (brys is measured ~40 GB/s COPY, DDR4 too)
```

Decode is bandwidth-bound on per-token weight traffic (§1.4):

```
IQ3_XXS: 1.54 GiB/token weights
   oams @35 GB/s (0 KV):   35 / 1.54  ≈ 22.7 tok/s ceiling
   oams @32 GB/s:          ≈ 20.8 tok/s
IQ4_XS:  2.14 GiB/token
   oams @35 GB/s (0 KV):   ≈ 16.3 tok/s
```

Subtract the n-gram lookups, KV reads, and vulkan/PCIe overhead → **ESTIMATE
oams decode ~12–18 t/s at low context, IQ3_XXS, IF it fit.** With long context the
QSA scratch and KV reads dominate and it falls fast. **Prefill** would be
severely hurt by the RDNA2 GDN regression (§2.2) → ESTIMATE **tens of tok/s at
best**, and on oams the model doesn't fit, so this is hypothetical.

### 3.3 Does VRAM-resident experts help decode? — The crux, answered honestly

**Decode speed depends on RAM bandwidth for the routed experts, not on VRAM
residency of the active set.** Reason (VERIFIED mechanics): on every token, the
router picks **10 of 512 experts per layer**. You cannot know which in advance.
So either (a) all 512×(48 layers) routed experts sit in RAM and you read the
chosen ~1.5–2 GiB/token from RAM (the `--cpu-moe` path — bandwidth-bound on RAM),
or (b) you page the chosen experts from GPU→host every token (PCIe-bound). Putting
the *currently active* set in VRAM does nothing for the *next* token's different
selection, so it does not remove the RAM read. **This is why the "active set fits
in 12 GB" claim is true-but-useless here:** fitting the compute graph in VRAM
saves the dense-path time but the routed-expert read from RAM dominates and stays.

The only way VRAM residency *would* help is if the *entire* routed-expert set fit
in VRAM — i.e. the whole model — which needs ~66–94 GB of VRAM. It does not.

### 3.4 oams vs brys, head-to-head — ESTIMATE

| | brys | oams |
| --- | --- | --- |
| CPU | Ryzen 9 5950X (16C desktop) | Ryzen 9 5900HX (8C mobile) |
| RAM | 128 GB DDR4, **~40 GB/s measured** | 62 GB DDR4-3200, **~32–36 GB/s** |
| GPU | W6600 8 GB (weak) | RX 6800M 12 GB (2.8–3.4× brys's card, measured) |
| Can serve the model (SSD-backed weights)? | **Yes** (54 GiB RSS @1M) | **Yes at 256K**, no at 1M (KV + cache too big) |
| Decode, 1M ctx, alone | 9.3 tok/s | not attempted (1M does not fit RAM headroom) |
| Decode, 1M ctx, competing | **2.36 tok/s** | n/a |
| Decode, 256K ctx | (not measured) | ESTIMATE ~ brys-alone or slower (RAM-bound experts) |

**Would oams be faster at 256K?** No — **about the same or slightly slower than
brys-alone**, because the expert read is RAM-bandwidth bound and the bandwidth is
comparable (oams mobile DDR4 ~32–36 vs brys ~40 GB/s) and the routed-expert read
is the bottleneck on both. The stronger 6800M only helps prefill/dense, not the
RAM-bound expert read. Measured evidence: oams's **CPU-only** decode is *worse*
than brys's (gemma-4-e4b 4.3 vs 13.9 t/s, thermal throttle;
[local-llms.md:653-657](docs/local-llms.md)) — when the work falls on CPU/RAM the
laptop loses. Since the experts live in RAM, oams would be **slower, not faster**,
for this workload. The 3× GPU win only appears when the model fits in VRAM, which
a 177B model never will here.

---

## 4. Verdict

### 4.1 Is running `qwen3.8-flash-next` on oams realistic?

**At 256K: yes, marginally — and worth one experiment. At 1M: no.**

1. **The weights fit on SSD, not in RAM** (corrected, §2.1): 93.7 GB file,
   `--lazy-mode auto` + `mmap`, same as brys does at 54.1 GiB RSS. oams has
   530 GB free and a 9.0 GB/s NVMe, faster than brys's storage.
2. **256K KV fits comfortably**: 3.2 GB (q8_0) / 6.4 GB (F16) plus a small
   prompt cache and compute buffers — ~7-15 GB anonymous against 45-50 GiB
   usable.
3. **1M does not**: 12.9 GB KV plus the 37 GB prompt cache brys sets leaves too
   little headroom; it is possible only with a cut cache and very slow prefill.
4. **Speed will be roughly brys-like, not faster.** Decode reads 10 of 512 routed
   experts per token from RAM; the 12 GB card helps the attention and shared
   path, not the expert traffic. oams is a laptop whose CPU-side decode is
   already measured *worse* than brys's (gemma-4-e4b: 4.3 vs 13.9 t/s CPU).
5. **GDN-hybrid on RDNA2 Vulkan has a known ~45% prefill regression**, so
   first-token latency suffers, and 256K prefill over SSD-backed weights is slow
   even before that.

So the honest answer: it *runs* at 256K, but it is not obviously better than
running it on brys, and the smaller 35B-A3B is far more sensible on this box.

### 4.2 What would be the point? (vs the 35B / 30B-A3B)

| Model | Quant | File | Fits oams (45-50 GiB)? | Notes |
| --- | --- | ---: | --- | --- |
| `qwen3.8-flash-next` | UD-IQ4_XS | 93.7 GB | SSD-backed, 256K yes / 1M no | the 1M quality tier; slow, big |
| `qwen3.5-35b-a3b` | UD-IQ4_XS | **17.5 GB** | **Yes**, + full 256K KV | 256K native, near-frontier, ~30 tok/s class on RDNA2 `--cpu-moe` |
| `qwen3.5-35b-a3b` | UD-Q4_K_XL | 22.2 GB | Yes | better quality, still fits |

`qwen3.5-35b-a3b` at IQ4_XS is the obvious everyday pick: 17.5 GB, 256K, and the
RDNA2 `--cpu-moe` path already shows ~30 tok/s gen on a near-identical RX 6900 XT
— ~13x brys's competing flash-next. **Recommendation: make the 35B-A3B the oams
model; treat flash-next-on-oams as a one-off experiment if the 1M tier is ever
needed closer to the client.**

The only reason to run the big model is the 1M reasoning/agentic tier, and that
already lives on brys (106 GiB).

### 4.3 Disk cost — the real reason not to make it the default

The GGUF is **82–94 GB** (brys ships 93.7 GB IQ4_XS in three shards). oams has
530 GB free, so it is *affordable* here — unlike on a small volume — but it is
1.6x the size of the entire remainder of the surveyed model set and far from
"keep disk low". By contrast `qwen3.5-35b-a3b` IQ4_XS is **17.5 GB** in a single
file. On disk grounds alone, the 35B is the right default for a laptop.

---

## Appendix: fact → source map

| Claim | Class | Source |
| --- | --- | --- |
| 512 experts, 10 routed, 1 shared, 48 layers, 8000-interval full attn 12/48 | VERIFIED | [config.json](https://huggingface.co/Qwen/Qwen3.8-Flash-Next/raw/main/config.json) |
| 125B + 6B active + 51B n-gram + 4B MTP | VERIFIED | [unsloth card](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF) |
| 24 KiB/token F16 KV, 6/12/24 GiB | VERIFIED | repo [done.md:115-119](docs/tasks/2026-10/qwen-flash-next-quant/done.md) + my formula |
| Quant file sizes (66.4 … 192 GB) | VERIFIED | unsloth card quant table |
| brys measured 54.1 GiB @1M, 106 GiB total | VERIFIED | [local-llms.md:504-506,684-694](docs/local-llms.md) |
| brys 9.3 tok/s alone / 2.36 competing | VERIFIED | [done.md:113](docs/tasks/2026-10/qwen-flash-next-quant/done.md), decision doc |
| `--cpu-moe` works on Vulkan, RDNA2 | VERIFIED | [#30697](https://github.com/ggml-org/llama.cpp/issues/30697), [#30039](https://github.com/ggml-org/llama.cpp/issues/30039) |
| RDNA2 ~45% GDN-hybrid prefill regression | VERIFIED | [#30039](https://github.com/ggml-org/llama.cpp/issues/30039) |
| `qwen4exp` `--n-cpu-moe` Vulkan numbers (118 pp/9.7 tg) | VERIFIED | [#28247](https://github.com/ggml-org/llama.cpp/issues/28247) |
| RX 6900 XT 35B-A3B `--cpu-moe` 30.8 t/s | VERIFIED | [#30697](https://github.com/ggml-org/llama.cpp/issues/30697) |
| oams = 5900HX mobile, 62 GiB, 6800M 12 GB | VERIFIED | [hosts/oams/default.nix](hosts/oams/default.nix), hardware.research.md |
| oams CPU-only decode worse than brys | VERIFIED | [local-llms.md:653-657](docs/local-llms.md) |
| Active-param bytes/token (4.3 B), 1.5–2.1 GiB/token | ESTIMATE | arithmetic §1.4 |
| oams decode 12–18 t/s if it fit | ESTIMATE | bandwidth §3.2 |
| oams bandwidth ~32–36 GB/s | ESTIMATE | DDR4-3200 dual-channel, −30% |
