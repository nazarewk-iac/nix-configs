---
type: Reference
description: Local LLM serving via the kdn.llm.local slot (llama-server router mode + Caddy TLS reverse proxy) — full option synopsis, architecture, and the brys host as a concrete deployment example.
timestamp: 2026-08-31T00:00:00+02:00
---

# Local LLM serving

How the `kdn.llm.local` standalone slot serves local LLMs on a NixOS host.
This document covers the concept, the global download behaviour, and a
concrete example single-host deployment on **brys**.

Reference docs: [slot README](../modules/slots/llm/README.md).

## Concept

`kdn.llm.local` runs one or more llama-server processes (from llama.cpp) in
**router mode**: each owns an OpenAI-compatible HTTP API on loopback that
loads/unloads individual GGUFs on demand (`--models-max 1`, exactly one model
resident at a time in that router). The primary **frontier** router
(`services.llama-cpp`, `:39703`) holds the default "main" model set; any number
of optional extra routers (`kdn.llm.local.routers.<name>`) host smaller
freely-swapping sets. A self-signed-certificate **Caddy** reverse proxy exposes
the endpoint on the LAN over HTTPS. Between Caddy and the servers sits one
OpenCode DSML compat-proxy that both translates DSML/XML tool calls and routes
each request's `model=` field to the router that owns it (unknown models fall
back to the frontier), merging all routers' `/v1/models`. A single instance
fronts the whole N-router topology.

```
LAN client ──HTTPS──▶ Caddy (:80/:443) ──▶ compat-proxy (:9530) ─┬─▶ llama-server "main" (:39703, --api-key-file)
                                                                  └─▶ llama-server "small" (:39704, --api-key-file)
                                                                  └─▶ ... any further `routers.<name>` ...
```

### N-router topology and routing

The compat-proxy maps each request's `model` (a name or an alias) through its
`ROUTE` table to the owning router's base URL; anything unrouted (including
`None`) goes to the frontier `UPSTREAM_URL`. `GET /v1/models` walks every
configured router and merges the listings, deduped by model id. Each router
runs `--models-max 1`, so model load/unload on that router is an on-demand swap
within the router only — the frontier's resident model is untouched.

Why split at all? A single `models-max=1` router thrashes DeepSeek V4 Flash's
(DS4) ~77 GB weight page-cache whenever a second model loads (see the measured
per-model table below: any 45 G+ MoE fully evicts DS4's resident weights, see
`qwen3-coder-next` 65.6 G, `qwen3-next-80b` 80 G, `gpt-oss-120b` ~100 G,
`qwen3-235b` ~100 G). Splitting lets DS4 stay resident/hot on the frontier
router (its ~92 GB working set held against page-cache pressure) while the
small set swaps freely on its own router; only `phi-4` (17.7 G) or
`qwen3-30b-a3b` (44.4 G but evicting ~45 G of DS4 cache) ever risk touching
the frontier's cache in a single-router layout. Facts only — no extrapolation
beyond the measured footprints in the table below.

### Option contract

All of this is configured through `kdn.llm.local` in a host's `mkSlots` block:

- `kdn.llm.local.routers.<name>` (`attrsOf`) — each entry enables an extra
  llama-server router with `enable`, `port`, `threads`, `apiKeyDir`. Router
  **names must be lowercase alphanumeric** (e.g. `small`, `coder`) so the
  proxy's env key `ROUTER_<NAME>_*` round-trips through its hyphenated slug
  back to the on-disk section name.
- `kdn.llm.local.models.<name>.mainRouter` — which router owns the model
  (`"main"` = the frontier/default server; any other value the equally-named
  `routers.<name>`). A model lands in exactly one router's preset INI.
- `kdn.llm.local.models.<name>.aliases` — extra names routed to that model's
  router too.

The compat-proxy honors, per router: `ROUTER_<NAME>_URL`
(`http://127.0.0.1:<port>`) + `ROUTER_<NAME>_MODELS` (`m1,m2,...`, names +
aliases). The legacy `SMALL_UPSTREAM_URL` + `SMALL_MODELS` pair is sugar for a
router named `small`; the slot now emits the general `ROUTER_<NAME>_*` form for
every enabled router (including `small`). A future host adds a third router by
declaring `routers.<name>` + pointing the relevant models' `mainRouter` at it —
the slot generates its env vars automatically. See
[`packages/opencode-compat-proxy/patches/router.patch`](../packages/opencode-compat-proxy/patches/router.patch)
for the proxy contract.

To enable on any NixOS host, inside its `mkSlots` block:

```nix
kdn.llm.local.enable = true;
kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models";    # required, no default
kdn.llm.local.domain = "brys.lan.etra.net.int.kdn.im";     # required, LAN hostname
kdn.llm.local.certs.certFile = "/run/configs/.../public.key";   # required
kdn.llm.local.certs.keyFile = "/run/configs/.../private.key";   # required
kdn.llm.local.apiKeyDir = "/run/configs/llms/llama-server/api-keys";   # optional
kdn.llm.local.download.mode = "slow";                    # global: slow | fast-polite
# ... per-model `kdn.llm.local.models.<name>` entries ...
```

Full option reference: [slot README](../modules/slots/llm/README.md).

## Global download behaviour

Applies to all models equally (not per model):

- **`download.mode`** — how aggressively to transfer:
  - `"slow"` (default): Xet disabled, regular HTTP. Gentlest.
  - `"fast-polite"`: Xet enabled, low pinned concurrency (Tier 1 mitigation).
    Faster than `"slow"` while staying gentle on a shared link.
  how aggressive Xet is.
- **`download.tokenFile`** — optional HF token path, loaded via systemd
  `LoadCredential`.

The download service (`kdn-llm-download`) walks all enabled models one at a
time, logs a status line after each, and skips files already present.

## Example deployment: brys

The **brys** host (Ryzen 5950X, 128 GB DDR4, CPU-only with an effectively
unusable 8 GB AMD GPU for this workload) is the primary deployment of this
slot.

### Serving endpoint

- The standard boot (main host and the `llm-minimal` specialisation) serves
  **DeepSeek V4 Flash only**, from one llama-server router on loopback:
  - **`main`** (frontier): `127.0.0.1:39703`, threads 16. Holds
    `deepseek-v4-flash` (alias `frontier`); `--models-max 1` keeps it resident
    and alone. **Four slots share one unified KV pool** (`parallel=4`,
    `kv-unified=on`, `ctx-size=327680`), so a second request no longer queues
    behind the first request's full prefill. There is no per-slot cap.
- One loopback compat-proxy `:9530` in front of it, with `routerProxyEnv`
  emitting `ROUTER_SMALL_URL` + `ROUTER_SMALL_MODELS` only on the `llm-small`
  boot entry.
- LAN endpoint over HTTPS: `https://brys.lan.etra.net.int.kdn.im/v1`, pinned to
  a self-signed cert and API-key protected. `POST /v1/chat/completions` with the
  `model` field set to a model name or alias; the compat-proxy routes it to the
  owning router (unknown → frontier), which loads/swaps the GGUF automatically.
  Auth: `Authorization: Bearer <key>`
  (`llama-server/api-keys/default` in the sops tree).

### Boot specialisations: frontier or small, never both

The frontier and the small set no longer share a boot. Both entries are
`inheritParentConfig = false` boot specialisations, selected from the bootloader
(never activated in place), and both share the appliance body in
`hosts/brys/llm-appliance.nix`:

- **`llm-minimal`** (`hosts/brys/llm-minimal.nix`) — DeepSeek V4 Flash alone.
  `withFrontier = true; withSmall = false`. 320K shared KV pool, 4 slots,
  DSpark draft. The main `brys` profile matches it (at 128K, unpinned).
- **`llm-small`** (`hosts/brys/llm-small.nix`) — the small-model set alone.
  `withFrontier = false; withSmall = true`. `kdn.llm.local.routers.small`
  (`:39704`, threads 8) is a **set router**: `--models-max 2` keeps up to two
  confirmed-coexistable small models resident together, and the primary
  `:39703` router holds no model.

The choice lives in `hosts/brys/llm.nix`'s `withFrontier` / `withSmall`
arguments, so a frontier host never even pulls the small-model definitions in.

**Why the split (measured, Phase 3):** on the ~40 GB/s bandwidth-bound box any
resident small model contends for the same memory bandwidth. Even an
*idle-but-resident* small model (phi-4, 8 GB) halves DS4 (~6.7 → ~3 t/s); an
*actively generating* small model drops DS4 to ~1.75–2.2 t/s (67–74% hit) and a
65 GB+ MoE (qwen3-coder-next) crushes it to ~0.9–1.1 t/s and evicts DS4's weight
cache (RSS 67→15 GB). Best co-tenant by far is `qwen3-30b-a3b` (fast, low
bandwidth, ~2.2 t/s DS4 hit, cache intact), but a router's
`--sleep-idle-seconds -1` pins its last resident model, so DS4 is never truly
"alone" once the small set has been touched. The only robust answer is a
separate boot entry.

### Models (all enabled on brys)

| Name | Alias | hfRepo / file | Size |
|---|---|---|---|
| `qwen3-30b-a3b` | `fast` | `Qwen/Qwen3-30B-A3B-GGUF` / `Qwen3-30B-A3B-Q4_K_M.gguf` | ~18 GB |
| `qwen3-next-80b` | `balanced` | `unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF` / `...-Q4_K_M.gguf` | ~48 GB |
| `deepseek-v4-flash` | `frontier` | `unsloth/DeepSeek-V4-Flash-GGUF` / `UD-IQ3_XXS/...-00001-of-00004.gguf` | ~103 GB (multi-shard) |
| `qwen3-235b` | — | `mradermacher/Qwen3-235B-A22B-i1-GGUF` / `...IQ2_M.gguf.part1of2` | ~77 GB |
| `qwen3-coder-next` | — | `Qwen/Qwen3-Coder-Next-GGUF` / `...-Q4_K_M-00001-of-00004.gguf` | ~48 GB |
| `gpt-oss-120b` | — | `unsloth/gpt-oss-120b-GGUF` / `gpt-oss-120b-F16.gguf` | ~65 GB |
| `phi-4` | — | `microsoft/phi-4-gguf` / `phi-4-Q4_K.gguf` | ~9 GB |

Serving is CPU-only (the Radeon Pro W6600 is unusable for this model family).
Per-model serving knobs on brys: `threads=16` (physical cores, SMT is counter
productive for memory-bound inference), `flash-attn=on`, `mmap=on`,
`reasoning=off`. DeepSeek V4 Flash adds `parallel=4` + `kv-unified=on`; every
other model keeps `parallel=1`. Context sizes:

| Model | ctx-size | Notes |
|---|---|---|
| `deepseek-v4-flash` | 327680 (320K) | MLA; the specialisation runs 320K. See "ZFS ARC quirk" below — the old ">192K oscillates" rule was ARC churn, not the context |
| `qwen3-30b-a3b` | 131072 | |
| `qwen3-next-80b` | 131072 | |
| `qwen3-coder-next` | 131072 | |
| `qwen3-235b` | 65536 | 128K KV would exceed RAM (141 GB) |
| `phi-4` | 16384 | hard architectural ceiling |

The **main `brys` profile** uses a smaller DeepSeek context (131072) and leaves
its threads unpinned: it shares the box with the desktop. The specialisation
gets the whole machine, so it takes 320K. Both draw the rest of their config
from the shared `hosts/brys/llm.nix` (which deliberately sets no CPU affinity —
see "Prefill tuning" below).

### Client context tiers (oams)

The DS4 endpoint is tiered **on the client side only**. Unified KV makes the
server pool usage-proportional, so a small request is already cheap without any
server flag; there is deliberately no `--kv-unified-per-slot` cap. Instead
`hosts/oams/devenv.nix` declares the same `deepseek-v4-flash` at several
practical context budgets, plus one opencode subagent per tier:

| provider model id | context | opencode agent |
|---|---|---|
| `deepseek-v4-flash` | 327680 (320K, the full shared pool) | `ds4-320k` |
| `deepseek-v4-flash-256k` | 262144 | `ds4-256k` |
| `deepseek-v4-flash-192k` | 196608 | `ds4-192k` |
| `deepseek-v4-flash-128k` | 131072 | `ds4-128k` |
| `deepseek-v4-flash-96k` | 98304 | `ds4-96k` |
| `deepseek-v4-flash-64k` | 65536 | `ds4-64k` |
| `deepseek-v4-flash-32k` | 32768 | `ds4-32k` |
| `deepseek-v4-flash-16k` | 16384 | `ds4-16k` |

`output` scales with the tier (`min(8192, context/4)`) so input + output fit the
window. **16K is the smallest useful subagent tier:** opencode sends a
~5K-token system prompt plus tool schemas, so an 8K window overflows and the
request stalls. Verified 2026-10-06: a 16K subagent read a file and returned the
right answer.

Every tier id hits the same DS4 model and the same shared 320K pool; the tier
only bounds what the client sends, which is what lets a sub-agent stay cheap.
`deepseek-v4-flash` (320K) and the `frontier` alias stay the default choice for
a main agent.

> **The tier ids are server aliases, not a proxy fallback.** The compat-proxy
> routes an id it does not know to the frontier *upstream*, but it does not
> rewrite the id, and llama-server then rejects an unknown id with HTTP 400
> (`model '...' not found`). So a purely client-side tier cannot be routed: the
> `deepseek-v4-flash-<n>k` ids must be listed in `hosts/brys/llm.nix` as
> aliases of `deepseek-v4-flash`. They add no KV cap and no memory; `--parallel
> 4` shares the one unified pool whatever alias a request names.

### ZFS ARC quirk (required for large contexts)

The model GGUFs live on ZFS (`usr/data`). ZFS's ARC is a *second* cache beside
the Linux page cache that backs the `mmap`'d weights, and its default `c_max`
is about half of RAM. On brys it grew to ~65 GB and the kernel then evicted the
mmap'd ~103 GB DeepSeek weights to make room — every request re-read them from
disk. Measured before the cap: prefill **0.18 tok/s**, 6.3M major faults,
271 GB read, and the single server slot blocked all queued requests.

`hosts/brys/llm.nix` therefore caps it, shared by both boot entries:

```nix
boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];  # 8 GiB
```

The cap is a kernel module parameter, so it only applies on a **cold boot**
(reboot into the entry; a `switch` does not apply it). To apply it live without
a reboot: `echo 8589934592 | sudo tee /sys/module/zfs/parameters/zfs_arc_max`.

With the cap the weights stay fully resident and the context is no longer the
constraint. Measured on brys, 8 GiB ARC, warm (DSpark acceptance in parens):

| ctx | DS4 RSS | RssAnon (KV) | idle major faults |
|---|---|---|---|
| 192K (old, uncapped) | ~92 GB | ~14 GB | 138/s (ARC thrash) |
| 256K | 115.7 GB | 14.6 GB | 0/s |
| 320K | 110.6 GB | 15.0 GB | 0/s |

KV is cheap for this MLA model (~0.4–1.4 GB per 64K), so RSS is dominated by
the ~101 GB of weights. Decode throughput is draft-acceptance bound: ~4.8 tok/s
at ~48% acceptance, ~8.6 tok/s at ~70%. Headroom stays ~1 GB free / ~101 GB
reclaimable, so a co-resident small-router model or a build can still evict the
weights.

#### Prefill (prompt processing) tuning

Two faults made long prompts appear hung. Both are now fixed in
`hosts/brys/llm.nix` + the slot.

1. **`--cpu-range`/`--cpu-strict` stall prefill on llama-cpp 0.4.0 (build
   10809).** In this build the affinity applies with the wrong scope: a server
   started with `--cpu-range 1-12` (pinned or not strict) never emits a prompt
   timing line at any context — decode is pinned, the prompt threadpool is not
   placed correctly and spins. Unpinned, prefill runs. So the DeepSeek perf sets
   **no** `cpuRange`/`cpuStrict`; the scheduler places the threads on the
   isolated cores itself. (Decode was unaffected, which is why only long prompts
   exposed it.)
2. **The llama default `ubatch` is 512.** Prompt processing is bandwidth-bound
   on the activated MoE expert weights; a small physical batch reuses them over
   too few tokens. `--ubatch-size`/`--batch-size` of 4096 is the single biggest
   prefill lever. Measured on brys at 320K with the DSpark draft, warm,
   cache-miss prompt (1385 tokens):

   | ubatch | prefill | wall |
   |---|---|---|
   | 512 (default) | 7.2 tok/s | 194 s |
   | 1024 | 10.2 | 137 s |
   | 2048 | 13.8 | 103 s |
   | **4096** | **15.8** | 89 s |
   | 8192 | 17.1 @128K / regresses memory | — |

   Live through the router (threads 16, ctx 320K): **15.2–16.5 tok/s**. Threads
   above 12 did not help (15 threads: 13.2). The knobs live in the slot as
   `perf.batchSize`/`perf.ubatchSize` (asserted `ubatchSize <= batchSize`) and
   are set on `deepseek-v4-flash` only.

Identical repeat prompts hit llama's prefix cache and return in ~1–2 s, so
always benchmark with a fresh, cache-missing prompt.

### Download configuration on brys

- **Service:** `kdn-llm-download` — sequential, one model at a time.
- **Mode:** `fast-polite` — Xet enabled with low pinned concurrency (Tier 1
  mitigation), so downloads are faster than `"slow"` while staying gentle on
  the shared link. Runs directly in the host network namespace.
- **Token:** `HF_TOKEN` via systemd `LoadCredential` from
  `/run/configs/llms/huggingface/token` (wired through sops-nix).

### Persistence

Model files live at `/var/lib/kdn/llms/models`, registered under
`kdn.disks.persist."usr/data"` (ZFS `usr/data` dataset) so they survive
reboots.

### Secrets

All LLM secrets live in one shared sops file (`llms.nonsensitive.sops.yaml`) and
are mounted at `/run/configs/llms` on both **brys** and **oams** via the same
`kdn.security.secrets.sops.files."llms"` entry (basePath `/run/configs/llms`,
no keyPrefix). The sops tree maps to files directly:

- `huggingface.token` → `/run/configs/llms/huggingface/token` (HF download token)
- `certs/public.key` → `/run/configs/llms/certs/public.key` (self-signed Caddy cert)
- `certs/private.key` → `/run/configs/llms/certs/private.key`
- `llama-server/api-keys/default` → `/run/configs/llms/llama-server/api-keys/default`
  (one API key; further keys are added the same way, each its own file)

The certificate is pre-generated once (openssl EC P-256, SAN
`brys.lan.etra.net.int.kdn.im`, 10 years) and stored in the sops file — there
is no cert-generation logic in the module system.

### Status / known state

- `qwen3-30b-a3b` and `qwen3-next-80b` were fully downloaded and verified on
  the 2026-08-29 smoke test.
- `deepseek-v4-flash` is fully downloaded (all four `UD-IQ3_XXS` shards
  present; `00001-of-00004` is legitimately ~5 MB — it is the split descriptor
  that llama mmap-links to the large shards `02/03/04` for the full ~103 GB
  weights). The model also uses the DSpark drafter
  (`dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf`, ~10.9 GB) for speculative
  decoding; both fetch through `kdn-llm-download`.
- Go-to status command: `kdn-llm-status`.

### Measured memory bandwidth (brys)

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
**~8 tok/s** (was ~9–10 from the assumed 50 GB/s). The 6.25 tok/s best reachis
~78% of the real hardware ceiling.

### Measured per-model hardware constraints (brys, 2026-09-06)

Each model loaded via a manual `llama-server` (llama.cpp 10408, `mmap`, threads 12) one at a time on
the 128 GB box (DeepSeek router also resident for the small models). Resident working set = `VmRSS`
= `RssAnon` (compute/KV buffers) + `RssFile` (mmap'd weights). `warm t/s` = 128-token generation.

| model | file | VmRSS | RssAnon | RssFile | VmPeak | load | warm t/s | coexist w/ DS4? |
|---|---|---|---|---|---|---|---|---|
| `phi-4` | 8.5 G | 17.7 G | 8.9 G | 8.7 G | 23 G | ~18 s | 2.86 | yes (fits; evicts little) |
| `qwen3-30b-a3b` | 18 G | 44.4 G | 26.4 G | 18.0 G | 50 G | ~42 s | 11.41 | partial (evicts ~45 G of DS4 cache) |
| `qwen3-coder-next` | 45 G | 65.6 G | 39.6 G | 25.9 G | 91 G | ~105 s | 5.34 | no (fully evicts DS4) |
| `qwen3-next-80b` | 46 G | 80.0 G | 39.2 G | 40.8 G | 94 G | ~99 s | 3.29 | no (fully evicts DS4) |
| `qwen3-235b` | 72 G | (fail) ~100 G est | — | — | — | fail @65 G avail | — | no (needs box alone) |
| `gpt-oss-120b` (Q4_K_M) | 58.5 G | 72.2 G | 60.2 G | 11.8 G | 128 G | ~129 s | **12.7** | yes (fits; DS4 file-cache evicted, re-faults) |

Multi-model implication: `models-max=1` (one resident at a time) is the right policy on 128 GB. Only
`phi-4` (17.7 G) fits comfortably alongside DeepSeek; `qwen3-30b` (44.4 G) fits but evicts ~45 G of
DS4's weight cache (DS4 re-reads from disk on next use). Every 45 G+ MoE fully evicts DS4 and needs
the box to itself. **This is exactly why the topology splits into two routers** (see "Router split on
brys"): the frontier router keeps DS4 hot while the `small` router owns the 45 G+ swapping set, so it
never touches DS4's cache — only `qwen3-30b-a3b` on the small side is a partial-eviction risk inside
its own router's resident cache, not DS4's.

### Benchmark result log (append-only)

Each row records a config tweak, the resulting server-side `print_timing`
eval tok/s on DS4 (warm), and the model load time. New results are appended
at the bottom.

| timestamp | tweak | server eval tok/s | ms/tok | vs prev | client tok/s | load time | note |
|---|---|---|---|---|---|---|---|
| 2026-09-05 19:41 | baseline (isolcpus=1-15, threads=16, no cpu-range) | 2.28 | 439 | — | 0.30 | ~1:40 | page-cache cold/churned |
| 2026-09-05 20:03 | `cpu-range=1-15` + `cpu-strict=1` + `threads=15` | 2.33 | 428 | 0.05 (==) | 0.31 | 1:45 (19:53:20 → 19:55:05) | still cold |
| 2026-09-05 20:07 | cpu-range same config, run 1 | 3.92 | 255 | ↑ | 0.53 | warm | page cache recovering |
| 2026-09-05 20:08 | cpu-range same config, run 2 | **5.75** | 174 | ↑ | 0.78 | warm | fully warm → matches 6.5-6.7 baseline |
| 2026-09-05 20:21 | `transparent_hugepage=always` (reboot), run 1 | 5.03 | 199 | — | 0.34 | cold | still warming |
| 2026-09-05 20:22 | `transparent_hugepage=always`, run 2 (warm) | 6.37 | 157 | ≈ | 0.82 | warm | no change vs madvise (THP no-op on file mmaps) |
| 2026-09-05 20:39 | `cpu-range` + `specDraftNMax=4` + `specDraftPrio=2`, run 1 | 3.21 | 312 | ↓ | 0.44 | warm | mean len↑3.95 but still warming |
| 2026-09-05 20:41 | cpu-range + n_max=4 + prio=2, run 2 (warm) | **4.39** | 228 | **↓ regression** | 0.58 | warm | draft mean len 3.62, acceptance 0.66; HIGHER n_max slower on CPU (matches rohitraj) → REVERT |
| 2026-09-05 20:50 | revert: cpu-range, DSpark defaults + madvise (reboot), run 1 | 6.21 | 161 | ↑ | 0.41 | cold→warm | confirms revert |
| 2026-09-05 20:51 | revert confirmed, run 2 (warm) | **6.91** | 145 | ↑↑ NEW BEST | 0.89 | warm | ~86% of ~8 t/s ceiling; DSpark n_max+prio was the regression |
| 2026-09-06 00:15 | session control (loopback router, threads=15, re-warm) | 6.41 | 156 | ≈ | 6.39 | warm | harness validated; client==server tok/s |
| 2026-09-06 00:2x | EXPERIMENT 1: `load-mode=mlock` + LimitMEMLOCK=inf (reboot) run a | 7.20 | 139 | ≈ NEW warm peak | 7.17 | warm | mlock DID NOT materialize: 0 bytes locked (ENOMEM on 101 GB; mmap conflict) → effectively control |
| 2026-09-06 00:2x | EXPERIMENT 1 (mlock), run b | 7.04 | 142 | ≈ | 7.01 | warm | confirms mlock null; \~90% of \~8 t/s ceiling |
| 2026-09-06 01:0x | EXPERIMENT 2: threads 15→12, cpu-range 1-12 (reboot) r1/2/3 | 6.89/6.88/6.91 | 145 | == | 6.86/6.84/6.88 | warm | dead-flat; bandwidth already saturated at ≤12 cores → no change |
| 2026-09-06 01:1x | EXPERIMENT 3: `--poll 100` + `--spec-draft-prio 2` (manual server) | (5.79-5.93 client) | — | — | 5.79/5.93 | warm | INCONCLUSIVE: manual harness unreliable/thrashing on loaded box; not attributed |
| 2026-09-06 01:3x | EXPERIMENT 4: `vm.vfs_cache_pressure` 50→10 (runtime) | 3.11 | 319 | ↓/worse | 3.11 | warm-ish | cache stayed ~50 GB → weights NOT resident; physical RAM capacity is the binding constraint, not reclaim policy |
| 2026-09-06 02:0x | EXPERIMENT A: ctx 262144→131072 (reboot), warm runs 1-4 / converged | 6.65/6.61/6.68/6.85 → **6.78** | 147 | ≈ (stable) | 7.05/6.62/6.58/6.85 | warm | weights resident throughout (buff/cache ~103-104 GB stable, no 2-4 collapse); halving KV freed headroom → ROBUSTNESS, not higher peak |
| 2026-09-06 02:3x | EXPERIMENT B: memcg-v2 cap (runtime, competing allocator) — unprotected | 5.28 | 189 | ↓ | 5.27 | warm | default-cgroup `stress-ng --vm-bytes 18G` evicted ~18 GB weights (buff/cache 103→85) → collapse |
| 2026-09-06 02:3x | EXPERIMENT B: memcg-v2 cap (runtime) — same allocator under `MemoryMax=4G` scope | **6.49** | 154 | ↑ PROTECTED | 6.49 | warm | competitor memcg-OOM-killed in its own scope; weights stayed resident; serving stayed fast → cgroup cap IS the robustness mechanism |
| 2026-09-06 03:0x | EXPERIMENT C: ik_llama.cpp fork swap | — | — | SKIP | — | — | not drop-in (no router mode, no `--cpu-range`); bandwidth-bound → no peak upside; DSpark syntax differs. Packaging easy (own flake) but moot. Kept upstream llama.cpp |
| 2026-10-06 12:4x | unified KV: `parallel 4` + `kv-unified on`, ctx 327680 (cold boot `llm-minimal` gen 652) | 2.22 | 451 | — | — | ~3:16 (first load) | **concurrency confirmed**: a short request (8 tok) returned in **3.7 s** while a 256-token request was in flight (121.8 s) — no head-of-line blocking; server logged `n_slots = 4, n_ctx_slot = 327680, kv_unified = 'true'`; DS4 `RssFile` 92.6 GB, **0 idle major faults**, no OOM; DSpark acceptance 0.44 at `parallel 4` (draft still works) |

**Key mechanism finding (2026-09-05 ~20:10):** the DS4 weights are `mmap`-backed and go
fully resident as **file-backed page cache** (~77 GB `RssFile` on the worker), plus ~14 GB
anonymous (`RssAnon`) → ~92 GB RSS on a 128 GB host. It does NOT re-read on demand *after the
first warm pass*, BUT if anything pressures page cache (a nix build/copy, a stream bench, erm:
essentially any large alloc), the kernel evicts those file pages and llama re-reads them from
disk on next decode → throughput collapses to disk-bound (~2-3 t/s, even 0.9). Once warm and
undisturbed it holds ~5.75-6.7 t/s. **Thus the 2.28/0.9 "regressions" were page-cache churn,
not isolation or cpu affinity.** Always: warm fully, keep the box otherwise idle, then bench;
record RSS/residency with the result. A big lever is keeping the ~92 GB resident without churn.

**Caveat (2026-09-05 ~20:06):** the 19:41 "baseline" (and the handover 0.9) were likely
artefacts of page-cache churn, not isolation. The SAME process (3064, isolation unchanged)
read 6.51 and 6.69 t/s at 19:14/19:16, then 2.28 at 19:41 right after nix-daemon build/copy
disk reads began. The mmap'd ~103 GB GGUF re-reads from disk if page cache is evicted
→ disk-bound. Treat any single bench that follows a build/copy as invalid; re-warm and re-run.

**Root cause refined (2026-09-06, follow-up session):** the recurring *active-serving* oscillation
(2.9→4.5→4.8→6.9 t/s on the router as `buff/cache` cycles 48→75→62→50 GB) is a **physical RAM
capacity** problem, not a VM-policy one. The ~90 GB working set (77 GB file weights + ~14 GB KV/anon
+ OS) on 128 GB leaves only ~1-3 GB free; during generation the KV/anon allocations force the kernel
to reclaim weight file pages because there is no headroom. Verified NULL levers: `--load-mode mlock`
(ENOMEM locking ~101 GB + `mmap` conflict), `vm.vfs_cache_pressure` 50→10 (no help, weights still
not resident), threads 15→12 (identical), `--poll`/`--spec-draft-prio` (inconclusive / unreliable
manual harness). Practical warm peak is **~6.9-7.2 t/s ≈ 87-90 % of the ~8 t/s bandwidth ceiling**;
the only remaining lever flagged for a future session is **memory cgroup v2 isolation** of the
serving unit (so spiky allocs fail in their own cgroup and cannot reclaim the weights), or shrinking
the working set via a smaller `contextSize`.

**Resolved (2026-10-02):** the "physical RAM capacity" framing above was incomplete. The missing
allocator was the **ZFS ARC** (default `c_max` ≈ half of RAM), which grew to ~65 GB and competed for
the same physical RAM as the `mmap`'d weights. Capping it (`zfs_arc_max=8589934592`, 8 GiB) keeps
the weights resident with **zero idle major faults**, and the 192K ceiling disappears — 256K and
320K both hold. `contextSize` was never the binding constraint; the ARC was. See "ZFS ARC quirk"
above for the figures. The mlock/cgroup ideas above are moot for this cause.
