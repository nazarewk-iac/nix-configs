---
type: Research
description: Survey of advanced local-LLM routers/schedulers (priority/pinning eviction, active-request protection, live resource awareness) as an alternative or upgrade to llama-server router mode, and the smallest change that reaches the goal on brys.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T01:00:00+02:00
---

# Advanced local-LLM routers/schedulers — research

Survey of alternatives or upgrades to `llama-server --models-max N` router mode for
a single CPU-only box (brys). The pain point: `--models-max` uses naive idle-LRU
eviction, has no priority/pinning, and (per upstream bugs) can evict models with
in-flight requests. The user wants a router/scheduler that:

- (a) supports **priority / pinning** for eviction (never evict the frontier/orchestrator),
- (b) is **active-request aware** (never swap a model with a request in flight),
- (c) is **live-resource aware** (reads RAM/VRAM/CPU; refuses/queues a load that would OOM),
- (d) keeps an **OpenAI-compatible** API (OpenCode etc. work unchanged),
- (e) runs **llama.cpp GGUF** backends,
- (f) serves **multiple models on one box**,
- (g) is **NixOS-packageable**.

**Verification legend:** `[V]` verified against a URL; `[I]` inferred from documented
mechanisms.

## 1. What the current setup does, and what is missing

Each router is `llama-server --models-preset ... --models-max N
--sleep-idle-seconds -1` (`modules/den/aspects/llm.nix`). Eviction inside a router is
**idle LRU** and nothing else: the router logs `tick: evicting idle LRU name=... for a
queued request` `[V, llama.cpp issue #28698]`. The workaround splits the box into
routers so the frontier's page cache is not thrashed, plus a `compat-proxy` that routes
each request's `model=` to the owning router.

The four gaps:

| Gap | What `--models-max`+LRU does today |
|---|---|
| Resource awareness | none — counts models, not bytes; never reads RAM/VRAM |
| Priority / pinning | none — pure idle-LRU; a warm frontier model is a candidate victim |
| Active-vs-idle | **buggy** — it evicts models with in-flight requests (llama.cpp #28698, #28443) `[V]` |
| "main resident + grunts swap" | only approximated by physically separate processes/routers |

## 2. Comparison table

Stars/last-commit as of the research date (2026-10-17/18).

| Candidate | (a) Pin/prio | (b) Active req | (c) Resource aware | (d) OpenAI | (e) GGUF | (f) Multi 1 box | (g) NixOS | License | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| llama.cpp router mode | ✗ | ✗ (evicts in-flight #28698) | ✗ | ✓ | ✓ | ✓ | ✓ | MIT | **No fit** (the thing replaced) |
| **llama-swap** (mostlygeek) | ✓✓ (`matrix.evict_costs`, `groups.persistent`, `selectors.pin`) | ✓ (queues; ttl resets on request; never interrupts a reply) `[V]` | ~ (monitors CPU/RAM/GPU; **no admission gate**) `[V]` | ✓✓ | ✓✓ | ✓✓ | ✓ Go binary `[I]` | MIT `[V]` | **FIT (best)** |
| Turbohaul-Manager | ✓ (IDLE_HOT, Fast Lane) | ✓ `[V]` | ✓✓✓ (7-gate: RAM/VRAM/CPU/iowait) `[V]` | ✓ | ✓ (vendored fork) | ✓ | ~ (C++ build) `[I]` | MIT | **Partial** — feature-perfect, NVIDIA-centric, tiny (40 stars) |
| LiteLLM proxy | ✓ (prio queue) | ✓ | ✗ (no process/mem lifecycle) | ✓✓ | ✗ (proxies, does not spawn) | ✓ | ✓ | MIT | **No fit** — routing only |
| Ollama | ~ (`keep_alive -1`; no eviction prio) | ✓ | ✓ (VRAM fit + queues) | ✓ | ✗ (own engine) | ✓ | ✓ | MIT | **Partial** — GGUF/100 GB MoE not its target |
| vLLM / SGLang router | ✗ | ✓ | ✓ (GPU) | ✓ | ✗ (HF weights) | ✓ | ~ | Apache-2.0 | **No fit** — GPU-only, no GGUF |
| Ray Serve / KServe / Triton / ModelMesh | ✗/~ | ✓ | ~ | ~ | ~ | ✓ | ~ | various | **No fit** — cluster/GPU, no priority evict |
| LM Studio headless | ✗ | ~ | ~ | ✓ | ✓ | ~ | ✗ (proprietary) | closed | **No fit** |
| KoboldCpp / Jan / text-gen-webui / Aphrodite / MLX | ✗/~ | ~ | ~ | ~ | ✓/~ | ~ | ~/✗ | various | **No fit** |

Only **llama-swap** satisfies (a)–(f) with easy Nix packaging. **Turbohaul-Manager**
satisfies (a)–(c) more strongly but is GPU-centric and immature.

## 3. llama-swap — the realistic fit

A single Go binary (MIT) that fronts any OpenAI/Anthropic server, extracts `model`, and
spawns/kills the upstream process on demand `[V]`.

- **(a) Priority/pinning — three mechanisms `[V]`:** `matrix.evict_costs` (integer cost
  per model; the solver minimizes eviction cost); `groups.<name>.persistent: true`
  ("other groups can never unload this group's members"); `selectors.<name>.strategy:
  pin`. Plus `scheduler.settings.fifo.priority` (per-model request priority).
- **(b) Active-request aware `[V]`:** the `ttl` idle timer "resets on every request";
  a swap only happens between turns and never interrupts a reply.
- **(c) Resource awareness — monitoring only `[V]`:** a Performance Monitor reports
  CPU/RAM/network (all platforms) and GPU (LACT/nvidia-smi/rocm-smi), `/metrics`.
  **No admission gate** — it does not refuse a spawn on low free RAM.
- **(d/e/f)** OpenAI/Anthropic endpoints; native llama-server `cmd` with `${PORT}`;
  `groups`/`matrix` for multi-model.

### Config that implements "never evict Qwen while a grunt swaps"

```yaml
routing:
  router:
    use: matrix
    settings:
      matrix:
        vars: { ds4: deepseek-v4-flash, qw: qwen3.8-flash-next, g4: qwen3.5-4b }
        evict_costs: { ds4: 1000, qw: 1000, g4: 1 }
        sets:
          main:  "ds4 & g4"
          qmain: "qw & g4"
          scratch: "g4 | +auto:orphans"
```

Because `ds4`/`qw` cost 1000, any set that keeps the frontier beats any set that drops
it: a request for a grunt evicts the other grunt, never the frontier `[V]`.

## 4. The gap none of them closes: measured, live resource admission

No mature packaged tool combines (1) priority/pinning, (2) active-request protection,
and (3) **measured** resource admission, on a GGUF/CPU/NixOS box. The user's insight —
**"a measured real-world resource-usage and performance profile, filled in once the
model starts, as the basis for scheduling/eviction"** — is exactly the missing piece.

### 4a. The proposed mechanism (measured profile → scheduling)

Build a small **model lifecycle/profile table** on brys, measured at real start:

| field | how to measure | use |
|---|---|---|
| `rss_file` (mmap weights) | `VmRSS`/`RssFile` of the child at idle | RAM budget; reclaimable |
| `rss_anon` (KV + buffers) | `RssAnon` at served context | RAM budget; not reclaimable |
| `vram_used` | `rocm-smi`/Vulkan query while served | GPU fit |
| `decode_tok_s`, `prefill_tok_s` | `llama-bench`/server timings, warm | expected latency; grunt eligibility |
| `load_time_s` | time from spawn to "listening", cold page cache | swap cost; pin if expensive |
| `major_faults/s` at idle | `/proc/<pid>/stat` over 10 s | detect page-cache eviction thrash |
| `coexist_penalty` | frontier tok/s with vs without this model resident | decide co-tenancy |

The scheduler then makes decisions from **measured** numbers, not from model names:

- pin a model whose `load_time_s` is large and whose `coexist_penalty` is high (e.g. the
  orchestrator),
- admit a load only if `measured_free_ram − model.rss_file − model.rss_anon ≥ headroom`
  (the Turbohaul Gate-1 idea, applied with measured per-model numbers),
- evict the model with the lowest `decode_tok_s × priority / rss_total` among idle ones,
- refuse/queue a load whose measured footprint cannot fit beside the pinned set.

### 4b. Smallest concrete implementation

1. **A spawn-gate wrapper** around each model's `cmd`: read `/proc/meminfo`
   `MemAvailable`, compare against a per-model `min_free_ram_mib`, exit non-zero when
   too tight (llama-swap then marks the load failed). ~20 lines of shell.
2. **A measured profile file** per model (JSON), produced by a one-off `llama-bench` +
   start/observe run (the "fill it in once we start the model" step), consumed by the
   gate and by the eviction policy.
3. **A systemd memory-capped slice** for the grunts (`MemoryHigh`/`MemoryMax`), so the
   kernel reclaims/kills a grunt before the pinned frontier. **Already proven on brys:**
   `docs/local-llms.md` EXPERIMENT B (2026-09-06) — a competitor under `MemoryMax=4G`
   was OOM-killed in its own scope while DS4's weights stayed resident: *"cgroup cap IS
   the robustness mechanism"* `[V]`.
4. Keep `zfs_arc_max=8GiB` and `mmap` + `--lazy-mode auto` so the frontier's weight pages
   are reclaimable rather than OOM `[V]`.

## 5. Recommendation

Adopt **llama-swap** with a `groups`/`matrix` config for priority + pinning +
active-request safety, and bolt on **one memory-capped slice + a ~20-line spawn-gate
wrapper driven by a measured per-model profile**. That is the smallest change that
satisfies (a)–(g) on this CPU-only box, and it makes the user's "measured real-world
usage as the basis for scheduling" the actual policy input.

## 6. Verification ledger

**`[V]`:** llama-swap features (matrix/evict_costs, groups/persistent, selectors/pin,
ttl, priority queue, aliases, apiKeys), OpenAI/Anthropic endpoints, process-spawn model,
Performance Monitor CPU/RAM/GPU (monitoring only), MIT — from
`github.com/mostlygeek/llama-swap` README, `config-schema.json`,
`docs/kb/guides/routing/groups-and-matrix.md`, `.../ttl-and-unloading.md`, `.../capacity-and-queues.md`.
llama.cpp router-mode bug: evict-in-flight #28698, hang #28443. Turbohaul-Manager: 7-gate
battery (`docs/SAFETY_GATE_VRAM_MATH.md`), NVIDIA-centric (`SYSTEM_REQUIREMENTS.md`).
Ollama `keep_alive`/`OLLAMA_MAX_LOADED_MODELS` (docs.ollama.com). LiteLLM routing
(docs.litellm.ai). cgroup-memory mechanism: `docs/local-llms.md` EXPERIMENT B.

**`[I]`:** llama-swap NixOS derivation effort (Go + UI build); that matrix/groups do not
read measured bytes (schema lists no memory field); the exact shell gate and cgroup
sizing numbers for brys.
