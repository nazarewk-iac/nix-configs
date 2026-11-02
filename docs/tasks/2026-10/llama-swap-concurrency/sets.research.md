---
type: Research
description: Measured model/alias/device map on brys, the VRAM and RAM budget, and a bounded replacement for the matrix sets plus per-model slot counts.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T10:20:00+01:00
---

# llama-swap matrix sets on brys — analysis and proposal

> Read-only study. No model was loaded or unloaded, no unit was restarted, and
> no repository file was changed. Every number carries the command that produced
> it. A value that needs a model load to obtain is marked **not measured**.

## 0. Commands used

| purpose      | command                                                                                                                                                                             |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| live config  | `ssh kdn-brys 'cat /nix/store/vhssi9i9857zg6qkm8dwp66smakvcr1a-config.yaml'`                                                                                                        |
| GGUF sizes   | `ssh kdn-brys 'ls -l <path>'` (sum of all shards)                                                                                                                                   |
| VRAM total   | `ssh kdn-brys 'cat /sys/class/drm/card1/device/mem_info_vram_total'`                                                                                                                |
| host RAM     | `ssh kdn-brys 'free -g'`                                                                                                                                                            |
| resident now | `ssh kdn-brys 'bash -lc "K=\$(sudo -n cat /run/configs/llms/llama-server/api-keys/default); curl --max-time 5 -s -H \"Authorization: Bearer \$K\" http://127.0.0.1:39700/running"'` |
| served ids   | same, path `/v1/models`                                                                                                                                                             |
| source code  | `modules/den/aspects/llm.nix`                                                                                                                                                       |

Measured values:

- VRAM total `8573157376` bytes = **7.98 GiB** (the W6600, PCI `1002:73e3`).
  Note: the brief expected ~8173157376; the card reports 8573157376.
- `free -g`: total **125**, used 23, free 53, buff/cache 52, available **102**.
- `/running`: exactly one model, `qwen3.5-4b` (`grunt`), state `ready`.
- `/v1/models`: 77 ids and aliases over 42 enabled models.

## 1. One row per model

`parallel` and `ctx` are read from the `cmd` line in the live config. `device`
is `Vulkan0` when the child carries `--device Vulkan0` and `--n-gpu-layers 99`,
else CPU (no device flag). Size is the sum of every GGUF shard, in GiB
(`ls -l` bytes / 2^30). GPU = W6600.

### 1a. Persistent frontier (cost 1000)

| id                 | aliases                             | parallel       | ctx-size | device | ngl | GGUF path (under `/var/lib/kdn/llms/models`)                                                           | GiB   |
| ------------------ | ----------------------------------- | -------------- | -------- | ------ | --- | ------------------------------------------------------------------------------------------------------ | ----- |
| deepseek-v4-flash  | frontier, orchestrate-deep-slow-alt | 4 (kv-unified) | 327680   | CPU    | —   | `unsloth/DeepSeek-V4-Flash-GGUF/UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-00001-of-00004.gguf` (+02..04) | 95.93 |
| qwen3.8-flash-next | qwen, orchestrate-deep-slow         | 4 (kv-unified) | 1048576  | CPU    | —   | `unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf` (+02,03)  | 87.25 |

DS4 also loads a draft head `unsloth/DeepSeek-V4-Flash-0731-GGUF/dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf` = **10.15 GiB** (same `ls -l`).

### 1b. GPU grunt/router models (`--device Vulkan0`, `--n-gpu-layers 99`)

| id                       | aliases                                                 | parallel | ctx   | GiB  |
| ------------------------ | ------------------------------------------------------- | -------- | ----- | ---- |
| qwen3.5-4b               | grunt, chat-dumb-fast, code-quick-fast, tiny-quick-fast | 1        | 16384 | 2.55 |
| qwen3.5-0.8b             | tiny-dumb-fast                                          | 1        | 16384 | 0.50 |
| qwen3.5-2b               | tiny-dumb-fast-alt                                      | 1        | 16384 | 1.19 |
| tmax-2b                  | —                                                       | 1        | 16384 | 1.19 |
| ministral-3-3b-instruct  | —                                                       | 1        | 16384 | 2.00 |
| ministral-3-3b-reasoning | reason-quick-fast-alt                                   | 1        | 16384 | 2.00 |
| granite-4.2-3b           | tools-dumb-fast, chat-dumb-fast-alt                     | 1        | 16384 | 2.09 |
| gemma-4-e2b              | —                                                       | 1        | 16384 | 2.89 |
| olmo-3-7b-instruct       | —                                                       | 1        | 16384 | 4.16 |
| gemma-4-e4b              | —                                                       | 1        | 16384 | 4.80 |
| ministral-3-8b-instruct  | —                                                       | 1        | 16384 | 4.84 |
| ministral-3-8b-reasoning | —                                                       | 1        | 16384 | 4.84 |
| granite-4.2-8b           | tools-std-fast-alt                                      | 1        | 16384 | 4.98 |
| tmax-9b                  | —                                                       | 1        | 16384 | 5.24 |
| mimo-v2.6-qwen-9b        | —                                                       | 1        | 16384 | 5.44 |

All 15 paths are `/var/lib/kdn/llms/models/surveyed/<id>.gguf` (except qwen3.5-4b, which is also `surveyed/qwen3.5-4b.gguf`). `ls -l` gives each size.

### 1c. CPU grunt models (no device flag)

| id                            | aliases                                                                             | parallel | ctx   | GiB                  |
| ----------------------------- | ----------------------------------------------------------------------------------- | -------- | ----- | -------------------- |
| qwen3.5-0.8b-cpu              | —                                                                                   | 1        | 8192  | 0.50                 |
| qwen3.5-2b-cpu                | —                                                                                   | 1        | 8192  | 1.19                 |
| tmax-2b-cpu                   | —                                                                                   | 1        | 8192  | 1.19                 |
| gemma-4-12b                   | —                                                                                   | 1        | 16384 | 6.63                 |
| mellum-2.1-12b-a2.5b-thinking | reason-quick-fast, code-std-fast-alt                                                | 1        | 32768 | 7.52                 |
| gemma-4-26b-a4b               | —                                                                                   | 1        | 8192  | 13.45                |
| lfm2.5-24b-a2b                | chat-std-fast, tools-std-fast                                                       | 1        | 32768 | 13.53                |
| qwen3.8-27b                   | chat-deep-slow, code-deep-slow, vision-deep-slow, reason-deep-slow, tools-deep-slow | 1        | 32768 | 15.33                |
| qwen3.6-27b                   | —                                                                                   | 1        | 8192  | 15.66                |
| granite-4.2-30b               | —                                                                                   | 1        | 8192  | 16.50                |
| glm-4.7-flash                 | —                                                                                   | 1        | 8192  | 17.05                |
| gemma-4-31b                   | —                                                                                   | 1        | 8192  | 17.07                |
| qwen3-vl-30b-a3b              | vision-std-fast, vision-std-fast-moe                                                | 1        | 32768 | 17.28 (+1.01 mmproj) |
| qwen3-omni-30b-a3b            | audio-std-mid                                                                       | 1        | 32768 | 17.28 (+1.23 mmproj) |
| north-mini-code-1.0           | code-std-fast, code-std-fast-moe                                                    | 1        | 32768 | 17.32                |
| olmo-3.1-32b                  | —                                                                                   | 1        | 8192  | 18.14                |
| ornith-1.5-35b-a3b            | vision-std-fast-alt                                                                 | 1        | 32768 | 20.22 (+0.84 mmproj) |
| seed-oss-36b                  | —                                                                                   | 1        | 8192  | 20.27                |
| qwen3.5-35b-a3b               | chat-std-mid                                                                        | 1        | 8192  | 20.50                |
| qwen3.6-35b-a3b               | —                                                                                   | 1        | 8192  | 20.61                |
| nemotron-3-nano-30b-a3b       | reason-std-fast, chat-std-mid-long                                                  | 1        | 32768 | 22.89                |
| nemotron-3.5-lightning-30b    | —                                                                                   | 1        | 8192  | 23.53                |
| qwen3-vl-8b-instruct          | vision-quick-fast                                                                   | 1        | 32768 | 4.68 (+1.08 mmproj)  |
| qwen3-embedding-4b            | embed-std-fast                                                                      | 1        | 8192  | 2.33                 |
| qwen3-reranker-4b             | rank-std-fast                                                                       | 1        | 8192  | 2.33                 |

All paths `/var/lib/kdn/llms/models/surveyed/<id>.gguf`. Note that `qwen3-embedding-4b`,
`qwen3-reranker-4b` and `qwen3-vl-8b-instruct` are small enough for the GPU but are
declared CPU by `mkCpu` (see `hosts/brys/llm-routers.nix`).

## 2. The `routing.router.settings.matrix` block, verbatim

From the live config (`matrix:` at the end of the file):

```yaml
routing:
  router:
    settings:
      matrix:
        evict_costs:
          deepseek-v4-flash: 1000
          gemma-4-12b: 1
          gemma-4-26b-a4b: 1
          gemma-4-31b: 1
          gemma-4-e2b: 1
          gemma-4-e4b: 1
          glm-4.7-flash: 1
          granite-4.2-30b: 1
          granite-4.2-3b: 1
          granite-4.2-8b: 1
          lfm2.5-24b-a2b: 1
          mellum-2.1-12b-a2.5b-thinking: 1
          mimo-v2.6-qwen-9b: 1
          ministral-3-3b-instruct: 1
          ministral-3-3b-reasoning: 1
          ministral-3-8b-instruct: 1
          ministral-3-8b-reasoning: 1
          nemotron-3-nano-30b-a3b: 1
          nemotron-3.5-lightning-30b: 1
          north-mini-code-1.0: 1
          olmo-3-7b-instruct: 1
          olmo-3.1-32b: 1
          ornith-1.5-35b-a3b: 1
          qwen3-embedding-4b: 1
          qwen3-omni-30b-a3b: 1
          qwen3-reranker-4b: 1
          qwen3-vl-30b-a3b: 1
          qwen3-vl-8b-instruct: 1
          qwen3.5-0.8b: 1
          qwen3.5-0.8b-cpu: 1
          qwen3.5-2b: 1
          qwen3.5-2b-cpu: 1
          qwen3.5-35b-a3b: 1
          qwen3.5-4b: 1
          qwen3.6-27b: 1
          qwen3.6-35b-a3b: 1
          qwen3.8-27b: 1
          qwen3.8-flash-next: 1000
          seed-oss-36b: 1
          tmax-2b: 1
          tmax-2b-cpu: 1
          tmax-9b: 1
        sets:
          main: (deepseek-v4-flash | qwen3.8-flash-next)
          with_grunt: (qwen3.5-4b) & (deepseek-v4-flash | qwen3.8-flash-next)
          with_surveyed: (gemma-4-12b | gemma-4-26b-a4b | gemma-4-31b |
            gemma-4-e2b | gemma-4-e4b | glm-4.7-flash | granite-4.2-30b |
            granite-4.2-3b | granite-4.2-8b | lfm2.5-24b-a2b |
            mellum-2.1-12b-a2.5b-thinking | mimo-v2.6-qwen-9b |
            ministral-3-3b-instruct | ministral-3-3b-reasoning |
            ministral-3-8b-instruct | ministral-3-8b-reasoning |
            nemotron-3-nano-30b-a3b | nemotron-3.5-lightning-30b |
            north-mini-code-1.0 | olmo-3-7b-instruct | olmo-3.1-32b |
            ornith-1.5-35b-a3b | qwen3-embedding-4b | qwen3-omni-30b-a3b |
            qwen3-reranker-4b | qwen3-vl-30b-a3b | qwen3-vl-8b-instruct |
            qwen3.5-0.8b | qwen3.5-0.8b-cpu | qwen3.5-2b | qwen3.5-2b-cpu |
            qwen3.5-35b-a3b | qwen3.6-27b | qwen3.6-35b-a3b | qwen3.8-27b |
            seed-oss-36b | tmax-2b | tmax-2b-cpu | tmax-9b) & (deepseek-v4-flash
            | qwen3.8-flash-next)
```

## 3. Who can be resident together

The llama-swap matrix engine reads two operators in a set expression:

- `|` — alternatives. At most one member of an alternation is resident. A new
  request from the same alternation evicts the previous one.
- `&` — co-resident permission. A resident model across an `&` boundary is not
  evicted when another branch is requested.

The engine loads only the requested model. It evicts every resident model that
is **not named anywhere in the active set**. `evict_costs` decides the eviction
order when a model must go: a `1000` model is evicted last.

With that reading, the three sets mean:

- **`main`** = `(DS4 | Qwen)`. The two frontier models are alternatives: only one
  is resident. They cannot co-exist (each is ~87–96 GiB of weights).
- **`with_grunt`** = `(qwen3.5-4b) & (DS4 | Qwen)`. `qwen3.5-4b` may sit beside
  one frontier model. A surveyed request does not name `qwen3.5-4b`, so it evicts
  it.
- **`with_surveyed`** = `(all 38 surveyed ids joined by |) & (DS4 | Qwen)`. Every
  surveyed model is an alternative to every other. Only **one** surveyed model
  can be resident at a time. Any of them may sit beside a frontier model.

So the co-resident groups that exist today are:

1. one frontier model **and** `qwen3.5-4b` (grunt) — allowed;
2. one frontier model **and** one surveyed model — allowed;
3. two surveyed models — **not allowed** (`|`);
4. two frontier models — **not allowed** (`|`).

The 15 GPU models and the 23 CPU models share the same single `|` chain, so a
GPU model and an unrelated small GPU model evict each other even though their
weights live in different memories (VRAM vs CPU RAM). That is the defect the
proposal fixes.

## 4. The practical consequence, confirmed

All surveyed models are in the one `with_surveyed` `|` group, so they evict each
other. This follows directly from the expression and matches the observation in
the brief: three sequential surveyed requests left exactly one resident.

Read-only confirmation of the "one resident" state right now:
`/running` returned exactly one entry (`qwen3.5-4b`, state `ready`), produced by
the `/running` command in §0.

A direct check of the eviction rule needs a model load and is **not measured**
here (rule: read-only). The command that would settle it:
`for m in gemma-4-e2b granite-4.2-3b tmax-2b; do curl -s -o /dev/null -m 120 -H "Authorization: Bearer $K" -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" http://127.0.0.1:39700/v1/chat/completions; curl -s -m 5 .../running; done`

## 5. Budget arithmetic

### 5a. KV assumption (stated, because it is not measured)

For every surveyed model, `cache-type-k`/`cache-type-v` are unset, so KV is
**F16**. Per slot the KV size is

```
KV_bytes = 2 (K+V) × n_layers × n_kv_heads × head_dim × 2 bytes × ctx_tokens
```

I do **not** have `n_layers` / `n_kv_heads` / `head_dim` without loading each
GGUF, so I use a labelled estimate for the fit test:

- dense ~3B class at 16K F16: **≈ 0.5–1.0 GiB** KV;
- dense ~8–9B class at 16K F16: **≈ 1.0–1.5 GiB** KV;
- a per-process compute/graph buffer on Vulkan: **≈ 0.3–0.5 GiB**.

These are estimates. The measured KV needs a load (see risk R2).

`--parallel N` **without `--kv-unified`** allocates N separate KV caches, so KV
is multiplied by N. Every surveyed model runs `--parallel 1`, so its KV is a
single slot. The two frontier models run `--parallel 4 --kv-unified`, where the
pool is shared and `ctx-size` is the pool total, not 4×.

### 5b. VRAM: which GPU models fit together

Total VRAM **7.98 GiB** (`mem_info_vram_total`). Leave ~0.5 GiB for the driver.
Usable for weights + KV + buffers: **≈ 7.5 GiB**.

Weight-only sums (GiB, from §1b) versus the 7.5 GiB budget + KV/buffers:

| combination                            | weights | + KV/buffers (est.) | total | fits?            |
| -------------------------------------- | ------- | ------------------- | ----- | ---------------- |
| qwen3.5-0.8b alone                     | 0.50    | ~0.5                | 1.0   | yes              |
| qwen3.5-2b + tmax-2b                   | 2.38    | ~0.9                | 3.3   | yes              |
| qwen3.5-2b + ministral-3-3b            | 3.19    | ~1.2                | 4.4   | yes              |
| qwen3.5-2b + granite-4.2-3b + tmax-2b  | 4.47    | ~1.6                | 6.1   | yes (tight)      |
| ministral-3-3b + qwen3.5-4b            | 4.55    | ~1.3                | 5.9   | yes              |
| gemma-4-e2b + qwen3.5-4b               | 5.44    | ~1.3                | 6.7   | yes (tight)      |
| olmo-3-7b (4.16) + qwen3.5-2b (1.19)   | 5.35    | ~1.6                | 7.0   | yes (very tight) |
| granite-4.2-8b (4.98) + tmax-2b (1.19) | 6.17    | ~1.8                | 8.0   | **no**           |
| mimo-v2.6-qwen-9b (5.44) + qwen3.5-2b  | 6.63    | ~1.7                | 8.3   | **no**           |
| any 8–9B alone (5.24–5.44)             | 5.44    | ~1.5                | 6.9   | yes (alone only) |
| two 8–9B models                        | 10.5+   | —                   | —     | **no**           |

Practical rule:

- models with **≤ ~1.2 GiB** weights co-reside freely (up to 3–4 at once);
- models with **2.0–3.2 GiB** co-reside as a **pair** (sometimes a trio if all tiny);
- models with **≥ 4.1 GiB** weights run **alone** on the W6600, or beside at most
  one ≤1.2 GiB model;
- **8–9B** models run alone at 16K.

The frontier models are on the CPU (no `--device`), so they consume no VRAM and
never compete for it. The VRAM question is only about the 15 GPU grunts.

### 5c. Host RAM: headroom with a frontier resident

`free -g`: total **125 GiB**, available 102 GiB now (23 used). The frontier's
measured resident working set (from
`docs/tasks/2026-10/brys-grunt-colocation/colocation.research.md`):

- Qwen idle, `--lazy-mode auto`: **~65 GiB**;
- Qwen warm, q8_0 KV: **~101 GiB**;
- Qwen worst, 1M F16: **~116 GiB**;
- DS4: **~115 GiB**.

Headroom = 125 minus the frontier footprint:

```
125 − 116 (Qwen worst) = ~9 GiB
125 − 101 (Qwen warm)  = ~24 GiB
125 −  65 (Qwen idle)  = ~60 GiB
125 − 115 (DS4)        = ~10 GiB
```

A GPU grunt still costs host RAM: with Vulkan, llama.cpp mmaps the GGUF and then
copies tensors to VRAM, so the file stays in page cache (`RssFile`). Host cost
per GPU grunt ≈ its file size:

- two small GPU grunts (2.38 GiB of weights) ≈ **3–4 GiB** host → fits in the
  24 GiB warm-Qwen window;
- one 8–9B GPU grunt (5.44 GiB) ≈ **6 GiB** host → fits beside warm Qwen, tight
  beside DS4 (~10 GiB headroom).

CPU grunts are different. Under warm Qwen (~101 GiB) a 23.5 GiB CPU model does
not fit: `101 + 24 = 125`, which leaves no room for KV and buffers. The CPU tiers
fit only beside **idle** Qwen (`65 + 24 = 89`, ~36 GiB left) or beside no
frontier.

### 5d. The ~45 GiB eviction threshold

The research doc states the threshold at two places:
`colocation.research.md:202` ("co-tenant > ~45 GB pushes the frontier's mmap'd
weights out of page cache") and `:233` ("anything ≥ ~45 GB: no — evicts Qwen").

Consequence for this config:

- **No surveyed model is near 45 GiB of weights** (largest is
  `nemotron-3.5-lightning-30b` at 23.53 GiB). No single surveyed request can
  cross the threshold.
- But a **30B-A3B MoE** model becomes large once resident: the doc measured
  `qwen3-30b-a3b` at **44.4 GiB VmRSS** for an 18 GiB file. The surveyed
  `nemotron-3-nano-30b-a3b` (22.89 GiB file) and `qwen3.5-35b-a3b` (20.50 GiB)
  are the same class and will approach 40–45 GiB resident. One of them beside a
  warm frontier is the only realistic way to hit the cliff, and it is a CPU-tier
  event, not a GPU-grunt event.

So: GPU grunts are safe on RAM by two orders of margin. CPU tiers are the RAM
risk, and the fix keeps them exclusive.

## 6. Nix proposal

### 6a. Current code (verbatim, `modules/den/aspects/llm.nix:498-514`)

```nix
      # The `matrix` sets: on a request for a model, llama-swap evicts every running model that is
      # not in the same set. The frontier models may not co-run, so one set groups them with `|`;
      # each extra router gets a set that lets it run ALONGSIDE a frontier model
      # (`<grunt> & (<frontier>)`). The frontier expression runs the frontier models alone (they
      # swap among themselves). A router with no enabled model is skipped.
      routerIds = routerName: builtins.attrNames (routerModels routerName);
      setExpr = ids: "(" + lib.concatStringsSep " | " ids + ")";
      frontierIds = routerIds "main";
      matrixSets =
        (lib.optionalAttrs (frontierIds != [ ]) { main = setExpr frontierIds; })
        // lib.mapAttrs' (
          rname: _:
          let
            gruntIds = routerIds rname;
          in
          lib.optionalAttrs (gruntIds != [ ]) {
            name = "with_${rname}";
            value = setExpr gruntIds + " & " + setExpr frontierIds;
          }
        ) enabledRouters;
```

The defect: it groups by **router**, and `with_surveyed` therefore puts 15 GPU
models and 23 CPU models into one `|` chain. The GPU models evict each other even
though they live in separate memory.

### 6b. Replacement code (drop-in for the block above)

```nix
      # The `matrix` sets: on a request for a model, llama-swap evicts every running model that is
      # not named in the active set. `|` marks alternatives (one at a time), `&` marks co-resident
      # permission (no eviction across the boundary).
      #
      # The frontier models are alternatives that live in ~90-115 GiB of host RAM, so `main` keeps
      # them alone. Grunts are split by where their weights live, not by which router serves them:
      #   * GPU grunts (`perf.device == "Vulkan0"`) keep their weights in the W6600's VRAM. They may
      #     co-reside with each other AND with one frontier model, because they take no host RAM
      #     and no VRAM from the frontier.
      #   * CPU grunts share the 125 GiB host RAM with the frontier. They stay mutually exclusive
      #     (`|`), and at most one may sit beside a frontier model.
      # A router with no enabled model contributes nothing.
      routerIds = routerName: builtins.attrNames (routerModels routerName);
      setExpr = sep: ids: "(" + lib.concatStringsSep " ${sep} " ids + ")";
      frontierIds = routerIds "main";
      frontierExpr = setExpr "|" frontierIds;
      # Every enabled model on an extra router (dedup keeps a model listed once).
      gruntIds = lib.unique (lib.concatMap routerIds (builtins.attrNames enabledRouters));
      isGpu = n: (cfg.models.${n}.perf.device or null) == "Vulkan0";
      gpuGruntIds = builtins.filter isGpu gruntIds;
      cpuGruntIds = builtins.filter (n: !(isGpu n)) gruntIds;
      matrixSets =
        (lib.optionalAttrs (frontierIds != [ ]) { main = frontierExpr; })
        // lib.optionalAttrs (gpuGruntIds != [ ]) {
          # `A & B & ... & (DS4 | Qwen)`: any subset of the GPU grunts may be resident together,
          # beside one frontier model.
          with_gpu = setExpr "&" gpuGruntIds + " & " + frontierExpr;
        }
        // lib.optionalAttrs (cpuGruntIds != [ ]) {
          # `(a | b | ...) & (DS4 | Qwen)`: one CPU tier at a time, beside one frontier model.
          with_cpu = setExpr "|" cpuGruntIds + " & " + frontierExpr;
        };
```

`evict_costs` is **unchanged** and keeps its semantics; the relevant lines
(`modules/den/aspects/llm.nix:491-494`) stay as they are:

```nix
      swapEvictCosts = lib.mapAttrs (
        n: _: if lib.elem n cfg.swap.persistentModels then 1000 else 1
      ) enabledModels;
```

`persistentModels = [ "deepseek-v4-flash" "qwen3.8-flash-next" ]`
(`hosts/brys/llm.nix:484-487`), so both frontier models keep cost 1000 and are
evicted last. That is preserved because the map is unchanged.

Notes on the replacement:

- It reads GPU membership from `perf.device`, so it cannot drift from the actual
  `--device Vulkan0` flag. A model that gains or loses GPU offload automatically
  moves group.
- `setExpr` gains a separator argument. Its only call sites are inside this
  block.
- `gruntIds` now derives from `enabledRouters` (the same routers the group engine
  uses), so a disabled router cannot leak models into a set.
- The `group` engine (`swapGroups`) is unchanged and out of scope.

### 6c. Per-model `parallel` proposal

Current: the two frontier models use `parallel 4` + `kv-unified`; every other
model uses the option default `1`. Proposal, with a reason per model. `→2` always
pairs with `kvUnified = true` so the pool is shared and KV does not multiply.

| id                               | now | proposed       | reason                                                                                                 |
| -------------------------------- | --- | -------------- | ------------------------------------------------------------------------------------------------------ |
| deepseek-v4-flash                | 4   | 4 (kv-unified) | unchanged; one shared pool, four concurrent long requests do not multiply KV                           |
| qwen3.8-flash-next               | 4   | 4 (kv-unified) | unchanged; 1M ctx shared across four slots                                                             |
| qwen3.5-0.8b                     | 1   | 2 (kv-unified) | 0.50 GiB weights; two slots cost <0.3 GiB KV, still leaves VRAM for a sibling                          |
| qwen3.5-2b                       | 1   | 2 (kv-unified) | 1.19 GiB; two slots fit beside one 3B sibling                                                          |
| tmax-2b                          | 1   | 2 (kv-unified) | same as 2b                                                                                             |
| qwen3.5-0.8b-cpu                 | 1   | 2 (kv-unified) | tiny CPU model, KV negligible, no VRAM cost                                                            |
| qwen3.5-2b-cpu                   | 1   | 2 (kv-unified) | same                                                                                                   |
| tmax-2b-cpu                      | 1   | 2 (kv-unified) | same                                                                                                   |
| qwen3.5-4b (grunt)               | 1   | 1              | 2.55 GiB; a second slot would multiply KV and risk the co-resident sibling on an 8 GiB card            |
| ministral-3-3b-instruct          | 1   | 1              | 2.00 GiB; keep VRAM for a co-resident sibling                                                          |
| ministral-3-3b-reasoning         | 1   | 1              | same                                                                                                   |
| granite-4.2-3b                   | 1   | 1              | 2.09 GiB; keep VRAM for a sibling                                                                      |
| gemma-4-e2b                      | 1   | 1              | 2.89 GiB; already consumes a third of the card                                                         |
| olmo-3-7b-instruct               | 1   | 1              | 4.16 GiB; runs alone or beside one tiny model                                                          |
| gemma-4-e4b                      | 1   | 1              | 4.80 GiB; runs alone                                                                                   |
| ministral-3-8b-instruct          | 1   | 1              | 4.84 GiB; runs alone                                                                                   |
| ministral-3-8b-reasoning         | 1   | 1              | 4.84 GiB; runs alone                                                                                   |
| granite-4.2-8b                   | 1   | 1              | 4.98 GiB; runs alone                                                                                   |
| tmax-9b                          | 1   | 1              | 5.24 GiB; runs alone                                                                                   |
| mimo-v2.6-qwen-9b                | 1   | 1              | 5.44 GiB; runs alone                                                                                   |
| all remaining CPU surveyed tiers | 1   | 1              | each extra slot multiplies KV in RAM and adds decode contention on the ~40 GB/s bus the frontier needs |

Rationale in one line: raise `parallel` only where weights are ≤1.5 GiB (KV and
compute buffers stay small), set `kvUnified = true` so KV is one shared pool, and
keep `parallel 1` everywhere else so a second slot cannot push the 8 GiB card (or
the frontier's bus) over budget.

## 7. Risks, each with the measurement that settles it

| #   | risk                                                                                                                                                         | measurement that settles it                                                                                                                                                                                                                   |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R1  | Unbounded GPU `&` lets models accumulate: request 5 small GPU models in turn and the 5th load fails on VRAM. The matrix has no capacity cap.                 | Request the GPU grunts in sequence, then `ssh kdn-brys 'cat /sys/class/drm/card1/device/mem_info_vram_used'` and `curl /running`; count how many load before a failure. If it OOMs, split `with_gpu` into bounded tiers (`\|` between tiers). |
| R2  | The KV estimate is wrong, so "8–9B + tiny" may not fit.                                                                                                      | Load each GPU model alone and read `mem_info_vram_used` before/after; the delta is its true weights + KV + buffers.                                                                                                                           |
| R3  | Vulkan keeps a host copy, so a GPU grunt costs more host RAM than its file size.                                                                             | With idle Qwen resident, load one GPU grunt; compare `free -g` and `grep VmRSS /proc/<pid>/status`.                                                                                                                                           |
| R4  | A CPU tier beside a warm frontier overflows 125 GiB (the ~45 GiB cliff).                                                                                     | Keep Qwen warm (~101 GiB), request `nemotron-3.5-lightning-30b`; watch `free -g` and whether Qwen's `RssFile` drops (re-fault).                                                                                                               |
| R5  | `parallel 2` on a tiny GPU model might tip a pair over 8 GiB.                                                                                                | Measure `mem_info_vram_used` for `qwen3.5-2b` at `parallel 1` vs `2` with one sibling resident.                                                                                                                                               |
| R6  | My reading of `&` (permission, not obligation) may be wrong; if `&` forces both branches resident, every GPU-grunt request would also load a frontier model. | With no frontier resident, request one GPU grunt and read `curl /running`: if a frontier child appears, `&` is an obligation and the sets must use a different shape.                                                                         |
| R7  | `evict_cost 1000` does not protect the frontier under hard memory pressure (no swap).                                                                        | Under R4's load, observe whether llama-swap evicts the frontier or the child OOMs; `dmesg`/journal shows an OOM kill if it happens.                                                                                                           |
| R8  | `perf.device` is not set on a model that is in fact GPU-offloaded, so it lands in `with_cpu`.                                                                | `ssh kdn-brys 'cat .../config.yaml'` and grep `--device Vulkan0`; compare with the `perf.device` values in `hosts/brys/llm-routers.nix`.                                                                                                      |

## 8. Summary

- 42 enabled models; 15 on the W6600 (`--device Vulkan0`), 27 on the CPU.
- Today all 38 surveyed models are one `|` chain, so a surveyed request evicts
  every other surveyed model — measured: one model resident now.
- Proposed sets: `main = (DS4 | Qwen)` (frontier only); `with_gpu =
(gpuA & gpuB & … ) & (DS4 | Qwen)` (GPU grunts co-reside, in VRAM);
  `with_cpu = (cpuA | cpuB | …) & (DS4 | Qwen)` (one CPU tier at a time).
  `evict_costs` and the `1000` persistent cost are unchanged.
- VRAM budget: 7.98 GiB; two 2–3 GiB GPU models fit, an 8–9B model runs alone.
- RAM budget: 125 GiB; warm Qwen leaves ~24 GiB, DS4 ~10 GiB; GPU grunts are
  safe, CPU tiers are the only path to the ~45 GiB cliff.
- Parallel: keep 4 (unified) on the frontier, raise to 2 (unified) on the
  ≤1.5 GiB models, keep 1 everywhere else.
