---
type: Design
description: Migrate brys from llama.cpp router mode (llama-server --models-preset per router) to llama-swap as the single model-lifecycle owner and router, keeping the OpenCode compat-proxy in front. Target topology, config mapping, aliases, GPU wiring, session store, hot reload, Nix integration and risks.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T08:00:00+02:00
---

# Design — migrate brys to llama-swap

Replace the per-router llama.cpp router mode with **one llama-swap process** that owns
every model child and does the `model=` routing. The OpenCode compat-proxy stays in
front. This document gives the target topology, the per-model config mapping, the
aliases and tiers, the GPU/CPU wiring, the session store, the hot-reload rule, the Nix
integration plan and the risks.

The concrete model data is the current brys wiring in
[hosts/brys/llm.nix](../../../../hosts/brys/llm.nix), the router sets in
[hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) and the aspect in
[modules/den/aspects/llm.nix](../../../../modules/den/aspects/llm.nix). The survey that
chose llama-swap is
[llama-router-scheduler.research.md](llama-router-scheduler.research.md); the reload
survey is [router-hot-reload.research.md](router-hot-reload.research.md).

## 1. Target topology

### Old topology (today)

Each router is a separate `llama-server` process in **router mode**. It loads a model
child inside its own process on demand (`--models-max N`). The compat-proxy routes by
`model=` to one router; Caddy terminates TLS. There are up to three llama-server
processes: `main` (`:39703`), `small` (`:39704`) and `grunt` (`:39705`).

```
LAN client ──HTTPS──▶ Caddy (:80/:443) ──▶ compat-proxy (:9530)
                                           ├─▶ llama-server "main"  :39703 (--models-preset models-preset.ini  --models-max 1) ── loads model in-process
                                           ├─▶ llama-server "small" :39704 (--models-preset models-router-small.ini --models-max 2) ── loads model in-process
                                           └─▶ llama-server "grunt" :39705 (--models-preset models-router-grunt.ini --models-max 1) ── loads model in-process
        ROUTER_<NAME>_URL + ROUTER_<NAME>_MODELS choose the router; unknown id → UPSTREAM_URL
```

Sources: `routerUnits` at
[modules/den/aspects/llm.nix:297](../../../../modules/den/aspects/llm.nix#L297), the primary
`services.llama-cpp` at
[modules/den/aspects/llm.nix:1296](../../../../modules/den/aspects/llm.nix#L1296), the
compat-proxy environment at
[modules/den/aspects/llm.nix:1348](../../../../modules/den/aspects/llm.nix#L1348), and the
Caddy vhost at
[modules/den/aspects/llm.nix:1464](../../../../modules/den/aspects/llm.nix#L1464).

### New topology (target)

**One** llama-swap process owns every model child. llama-swap extracts `model=` from
each request and starts/kills the matching `llama-server` child. The compat-proxy stays
in front, so tool-call translation (DSML/XML → OpenAI JSON) and the token-usage
passthrough are unchanged. The compat-proxy no longer needs a `ROUTER_<NAME>_*` table:
llama-swap answers to every model id and alias itself, and the proxy forwards everything
to one upstream.

```
LAN client ──HTTPS──▶ Caddy (:80/:443) ──▶ compat-proxy (:9530)
                                           │   translates DSML/XML tool calls + passes usage
                                           ▼
                                    llama-swap (:39700, single process)
                                      ├─ spawns llama-server child "deepseek-v4-flash"  (${PORT}, frontier, ttl:0, group persistent)
                                      ├─ spawns llama-server child "qwen3.8-flash-next" (${PORT}, orchestrator, ttl:0)
                                      └─ spawns llama-server child "qwen3.5-4b"          (${PORT}, grunt, matrix evict_cost 1)
                                    sidecar: one memory-capped systemd slice for macrunts
```

The one-process design removes the three-way router split. The "never evict the
orchestrator" rule moves from *separate processes* (the current `routers.grunt`) to
*llama-swap routing policy* — `groups.persistent` or `matrix.evict_costs` (§2.4). That is
the whole point of the migration: [llama-router-scheduler.research.md §3](llama-router-scheduler.research.md)
records that `--models-max` is naive idle-LRU and can even evict a model with an
in-flight request (llama.cpp #28698), while llama-swap offers `matrix.evict_costs`,
`groups.persistent` and `selectors.pin`.

### Where each process listens

| Process | Port | Owner |
|---|---|---|
| Caddy | 80, 443 | the aspect (LAN gate), unchanged |
| compat-proxy | 9530 | the aspect, unchanged ([llm.nix:1199](../../../../modules/den/aspects/llm.nix#L1199)) |
| llama-swap | 39700 (proposed) | new; loopback only |
| llama-server children | `startPort: 10001` and up | llama-swap assigns `${PORT}` per model |
| old `main`/`small`/`grunt` routers | 39703/39704/39705 | **removed** |

## 2. Config mapping

llama-swap's `models.<id>.cmd` is a plain `llama-server ...` argv string with the
`${PORT}` macro. Every field the aspect writes into a preset INI today
(`presetSection` at [llm.nix:133](../../../../modules/den/aspects/llm.nix#L133)) becomes one
flag in that argv. The mapping is mechanical.

### 2.1 Field-by-field mapping

| Aspect field (`perf.*` unless noted) | Preset key (today) | llama-swap `cmd` flag | Notes |
|---|---|---|---|
| `model` (from `hfRepo`/`hfFile`) | `model = <path>` (INI key, `-m`) | `--model <path>` | path is `modelsDir/hfRepo/hfFile` ([llm.nix:106](../../../../modules/den/aspects/llm.nix#L106)) |
| `mmproj.enable` | `mmproj = <path>` | `--mmproj <path>` | vision projector |
| `threads` / `defaultThreads` | `threads` | `--threads N` | `-t` |
| `flashAttention` | `flash-attn` | `--flash-attn {on,off,auto}` | `-fa` |
| `cpuRange` / `cpuStrict` | `cpu-range` / `cpu-strict` | `--cpu-range` / `--cpu-strict` | off on brys, see §2.5 |
| `loadMode` | `load-mode` | `--load-mode` | |
| `contextSize` | `ctx-size` | `--ctx-size N` | `-c` |
| `ropeScaling`/`ropeScale`/`ropeFreqBase`/`yarnOrigCtx` | same | `--rope-scaling`/`--rope-scale`/`--rope-freq-base`/`--yarn-orig-ctx` | |
| `cacheTypeK`/`cacheTypeV` | same | `--cache-type-k`/`--cache-type-v` | `-ctk`/`-ctv` |
| `cacheRam` | `cache-ram` | `--cache-ram N` | `-cram` |
| `ctxCheckpoints` / `checkpointMinStep` | same | `--ctx-checkpoints` / `--checkpoint-min-step` | needs the sessions build |
| `sessionHeaders` | `slot-save-path` + `slot-save-sessions` | `--slot-save-path D` + `--slot-save-sessions H` | see §5 |
| `sessionMaxSessions` | `slot-save-sessions-max` | `--slot-save-sessions-max N` | |
| `batchSize` / `ubatchSize` | same | `--batch-size` / `--ubatch-size` | `-b`/`-ub` |
| `nGpuLayers` | `n-gpu-layers` | `--n-gpu-layers N` | `-ngl` |
| `cpuMoe` | `cpu-moe = on` | `--cpu-moe` | |
| `noKvOffload` | `no-kv-offload = on` | `--no-kv-offload` | |
| `draftNGpuLayers` | `n-gpu-layers-draft` | `--n-gpu-layers-draft N` | |
| `device` | `device` | `--device <name>` | `Vulkan0` for the grunt |
| `mmap` | `mmap = on/off` | `--mmap` / `--no-mmap` | `null` omits it (v0.6.0 dropped it) |
| `parallel` | `parallel` | `--parallel N` | `-np` |
| `kvUnified` | `kv-unified = on/off` | `--kv-unified` / `--no-kv-unified` | |
| `reasoning` | `reasoning` | `--reasoning {on,off,auto}` | `-rea` |
| `reasoningEffort` | `reasoning-effort` | `--reasoning-effort` | |
| `draft.enable` → `specType` | `spec-type` | `--spec-type` | |
| `draft.enable` → draft file | `model-draft` | `--model-draft <path>` | |
| `specDraftNMax`/`PMin`/`Prio` | same | `--spec-draft-n-max`/`-p-min`/`-prio` | |
| `models.<name>.aliases` | `alias = a,b` | llama-swap top-level `aliases:` list | **not** a `llama-server` flag (§3) |
| router `modelsMax` | `--models-max N` | llama-swap `routing` policy (groups/matrix) | the router concept disappears |
| router `threads` | `--threads N` | drop or fold into the child `--threads` | llama-swap itself is not a compute process |

The aspect's `presetSection` renderer
([llm.nix:133-250](../../../../modules/den/aspects/llm.nix#L133)) becomes a `cmdLines`
renderer that emits the same flags as argv words. The `alias` line
([llm.nix:216](../../../../modules/den/aspects/llm.nix#L216)) moves out of the argv into the
model's `aliases:` list.

### 2.2 Concrete llama-swap YAML

The `frontier` DS4 model, the Qwen3.8-Flash-Next orchestrator and the Qwen3.5-4B GPU
grunt. Paths use the brys values from [hosts/brys/llm.nix:444](../../../../hosts/brys/llm.nix#L444)
and the model blocks at [llm.nix:381](../../../../hosts/brys/llm.nix#L381), [llm.nix:404](../../../../hosts/brys/llm.nix#L404),
[llm-routers.nix:105](../../../../hosts/brys/llm-routers.nix#L105). The `${...}` macros are
llama-swap's (`${PORT}`, `${MODEL_ID}`); the Nix-rendered values are inlined by the
generator.

```yaml
# healthCheckTimeout must cover a cold DS4/Qwen load (minutes); the routing research
# measured ~90-120 s for a frontier swap, so give it generous headroom.
healthCheckTimeout: 900
logLevel: info
includeAliasesInList: true          # /v1/models lists every tier alias (§3)
startPort: 10001
globalTTL: 0                        # never auto-unload; see §5
unloadTimeout: 30

routing:
  router:
    use: matrix
    settings:
      matrix:
        vars: { ds4: deepseek-v4-flash, qw: qwen3.8-flash-next, g4: qwen3.5-4b }
        evict_costs:
          ds4: 1000                 # frontier: never evict for a grunt
          qw: 1000                  # orchestrator: never evict for a grunt
          g4: 1                     # grunt: cheap to reload
        sets:
          main:  "ds4 & g4"         # DS4 frontier + grunt coexist
          qmain: "qw & g4"          # Qwen orchestrator + grunt coexist
          lone:  "(ds4 | qw)"       # a frontier alone (grunt not preloaded)
  scheduler:
    use: fifo
    settings:
      fifo:
        priority: { deepseek-v4-flash: 10, "qwen3.8-flash-next": 10, qwen3.5-4b: 5 }

models:
  deepseek-v4-flash:
    name: "DeepSeek V4 Flash"
    aliases:
      - frontier
      - deepseek-v4-flash-256k
      - deepseek-v4-flash-192k
      - deepseek-v4-flash-128k
      - deepseek-v4-flash-96k
      - deepseek-v4-flash-64k
      - deepseek-v4-flash-32k
      - deepseek-v4-flash-16k
      - deepseek-v4-flash-think
      - deepseek-v4-flash-256k-think
      # ... the full ds4Aliases list, see hosts/brys/llm.nix:149
    ttl: 0                          # stay resident once warm
    cmd: |
      llama-server --port ${PORT}
      --model /var/lib/kdn/llms/models/unsloth/DeepSeek-V4-Flash-GGUF/UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-00001-of-00004.gguf
      --threads 16
      --flash-attn on
      --ctx-size 327680
      --reasoning auto
      --reasoning-effort low
      --batch-size 4096
      --ubatch-size 4096
      --parallel 4
      --kv-unified
      --spec-type draft-dspark
      --spec-draft-n-max 5
      --model-draft /var/lib/kdn/llms/models/unsloth/DeepSeek-V4-Flash-0731-GGUF/dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf
      --mmap
      --host 127.0.0.1

  qwen3.8-flash-next:
    name: "Qwen3.8-Flash-Next"
    aliases:
      - qwen
      - qwen3.8-flash-next-768k
      - qwen3.8-flash-next-512k
      # ... the full qwenTierSuffixes list, see hosts/brys/llm.nix:165
    ttl: 0                          # the orchestrator stays warm
    cmd: |
      llama-server --port ${PORT}
      --model /var/lib/kdn/llms/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf
      --mmproj /var/lib/kdn/llms/models/unsloth/Qwen3.8-Flash-Next-GGUF/mmproj-F16.gguf
      --threads 16
      --flash-attn on
      --ctx-size 1048576
      --rope-scaling yarn --rope-scale 4.0 --rope-freq-base 10000000 --yarn-orig-ctx 262144
      --cache-type-k q8_0 --cache-type-v q8_0
      --cache-ram 8192
      --reasoning auto --reasoning-effort low
      --batch-size 4096 --ubatch-size 4096
      --parallel 4 --kv-unified
      # session store (needs the sessions build; see §5). Kept off while the
      # grunt forces the Vulkan no-BLAS build — see the trade-off in §2.6.
      --slot-save-path /var/lib/kdn/llms/sessions
      --slot-save-sessions x-session-id
      --slot-save-sessions-max 64
      --ctx-checkpoints 32
      --checkpoint-min-step 900
      --host 127.0.0.1

  qwen3.5-4b:
    name: "Qwen3.5-4B (grunt)"
    aliases: [ grunt ]
    ttl: 300                        # a grunt may idle-unload; cheap to reload
    cmd: |
      llama-server --port ${PORT}
      --model /var/lib/kdn/llms/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-Q4_K_M.gguf
      --device Vulkan0
      --n-gpu-layers 99
      --ctx-size 16384
      --parallel 1
      --host 127.0.0.1
```

### 2.3 Which routing engine — `group` or `matrix`

The "never evict the orchestrator" rule has two equivalent expressions.

**Group engine** (simpler, and enough for the current roster):

```yaml
routing:
  router:
    use: group
    settings:
      groups:
        frontier:
          persistent: true          # other groups can never unload these
          swap: true                # DS4 and Qwen swap among themselves
          members: [ deepseek-v4-flash, qwen3.8-flash-next ]
        grunts:
          swap: false               # grunts coexist with each other
          exclusive: false          # loading a grunt does not unload `frontier`
          members: [ qwen3.5-4b, qwen3.5-9b ]
```

`groups.<name>.persistent: true` means "other groups can never unload this group's
members" — exactly the current separate-router guarantee, now inside one process. When
the grunt loads it does not touch the `frontier` group; when DS4 and Qwen swap, they swap
only among themselves. This matches the aspect's current split most directly, and it is
the smaller YAML.

**Matrix engine** (chosen for the design): it expresses the same rule with a cost model
and it generalises to the future roster (a second frontier candidate, a vision model
that only coexists with one family). `evict_costs: { ds4: 1000, qw: 1000, g4: 1 }` on
the sets in §2.2 gives: any set keeping a frontier (`main`, `qmain`) beats any set that
drops it, so a grunt request evicts the *other grunt*, never the frontier. This is the
config the scheduler research already worked out
([llama-router-scheduler.research.md §3](llama-router-scheduler.research.md)).

**Recommendation:** ship the **group** engine first (smallest change, same guarantee),
and switch to **matrix** only when the roster outgrows it. Both render from the same Nix
data; the generator picks one.

### 2.4 "Never evict the orchestrator" — why either engine is enough

| Rule | Group engine | Matrix engine |
|---|---|---|
| A grunt request never evicts Qwen/DS4 | `frontier.persistent: true` | `evict_costs: 1000` |
| Qwen and DS4 swap only among themselves | `frontier.swap: true` | sets `main`/`qmain`/`lone` |
| Grunts coexist | `grunts.swap: false` | set `main` = `ds4 & g4` |
| Active-request protection | ttl resets on each request; a swap happens only between turns | same |
| Priority | `scheduler.fifo.priority` | same |

### 2.5 Fields that must NOT appear on brys

- `--cpu-range` / `--cpu-strict`: brys deliberately omits them. The DS4 `deepseekPerf`
  sets no affinity ([llm.nix:244](../../../../hosts/brys/llm.nix#L244)); a pinned build
  stalls prefill on llama-cpp 0.4.0. Keep omitting them.
- `--mmap` on the v0.6.0 / Unsloth / Vulkan builds: the MTP builds dropped `--mmap`, so
  `perf.mmap = null` and the generator must emit **no** `--mmap`/`--no-mmap` for Qwen
  ([llm.nix:311](../../../../hosts/brys/llm.nix#L311), [llm.nix:266](../../../../hosts/brys/llm.nix#L266)).
- `--api-key-file`: today the router validates `--api-key-file`. In the new topology the
  **compat-proxy** already forwards `Authorization` and llama-swap itself carries
  `apiKeys:` (top-level) if key checking is wanted. Decide the owner in §7; do not set
  both.

### 2.6 The one-package constraint (unchanged by the migration)

The aspect has **one** `kdn.llm.local.package` for every child
([llm.nix:207-217](../../../../hosts/brys/llm.nix#L207)). The GPU grunt needs a Vulkan
build; the Qwen session cache needs the CPU-only `llama-cpp-sessions` build. `withGrunt`
today forces `pkgs.kdn.llama-cpp-v0_6_0-vulkan-noblas` and the session options become
inert. **llama-swap does not remove this constraint**: each child is still one
`llama-server` binary. However, llama-swap makes a **per-model `package`** trivial — the
generator can render a different absolute `llama-server` path into each model's `cmd`.
That is a genuine improvement: with llama-swap, the Qwen child can run
`llama-cpp-sessions` (CPU + session cache) while the grunt child runs the Vulkan build,
both under one router. This is called out in §7 as the primary reason to prefer llama-swap
over the current single-package router.

## 3. Aliases and tiers

Today each tier id (`deepseek-v4-flash-256k`, `qwen3.8-flash-next-512k`, …) must be a
real `llama-server` alias in the preset, because the compat-proxy does not rewrite an
unknown id and llama-server then rejects it with HTTP 400
([docs/local-llms.md:307](../../../local-llms.md) / [hosts/brys/llm.nix:134](../../../../hosts/brys/llm.nix#L134)).
The alias list is built in [hosts/brys/llm.nix:140-178](../../../../hosts/brys/llm.nix#L140).

llama-swap has first-class `aliases:` on each model. Its `/v1/models` listing includes
the aliases when `includeAliasesInList: true` (see the config example). So the mapping
is:

| Source (aspect / brys) | llama-swap |
|---|---|
| `models.<name>.aliases` ([llm.nix:557](../../../../modules/den/aspects/llm.nix#L557)) | `models.<id>.aliases:` |
| `alias = a,b` preset line ([llm.nix:216](../../../../modules/den/aspects/llm.nix#L216)) | the same `aliases:` list (remove from argv) |
| `routerProxyEnv` `ROUTER_<NAME>_MODELS` ([llm.nix:280](../../../../modules/den/aspects/llm.nix#L280)) | **not needed** — llama-swap answers to all ids itself |
| `ds4Aliases` ([llm.nix:149](../../../../hosts/brys/llm.nix#L149)) | `deepseek-v4-flash.aliases` |
| `qwenAliases` ([llm.nix:174](../../../../hosts/brys/llm.nix#L174)) | `qwen3.8-flash-next.aliases` |
| `grunt` alias ([llm-routers.nix:110](../../../../hosts/brys/llm-routers.nix#L110)) | `qwen3.5-4b.aliases: [ grunt ]` |

Two behaviours to confirm and encode:

1. Aliases must be **globally unique** across models (llama-swap rejects a duplicate).
   The brys `frontier` alias is deliberately owned by **one** model only — the current
   code already gives `frontier` to Qwen only when DS4 is absent
   ([llm.nix:177](../../../../hosts/brys/llm.nix#L177)). The generator must assert global
   uniqueness before render, replacing the aspect's current per-router rule.
2. `includeAliasesInList: true` makes `/v1/models` list each alias as a duplicate entry.
   The compat-proxy merges `/v1/models` from every upstream; with one upstream there is
   nothing to merge, and the alias list surfaces directly to OpenCode. The client tiers
   in `hosts/oams/devenv.nix` keep working unchanged.

### Tool-call translation and thinking

The compat-proxy keeps DSML/XML → OpenAI JSON translation regardless of who owns model
lifecycle. llama-swap's own `setParamsByID` could in principle carry the per-tier
`chat_template_kwargs`, but thinking is already selected **per request** by the client
([docs/local-llms.md:256-282](../../../local-llms.md)); no llama-swap filter is
needed. Keep the proxy as the single translation owner (§8, risk 1).

## 4. Process and GPU wiring

llama-swap spawns each child as a **subprocess**. The child inherits the **systemd unit
environment** of the llama-swap service. So the W6600 Vulkan variables must be set on the
llama-swap unit, not on a per-router unit.

### CPU children (DS4, Qwen)

No change: no `--device`, no `--n-gpu-layers`. They run on the CPU as today.

### GPU grunt child (Qwen3.5-4B)

The grunt needs the Mesa RADV ICD and the W6600 pin. Today these come from
`hardware.graphics.enable` + `extraPackages = [ pkgs.mesa ]` + the
`systemd.services.llama-cpp.environment.MESA_VK_DEVICE_SELECT` line
([hosts/brys/llm.nix:496-500](../../../../hosts/brys/llm.nix#L496)). In the new topology:

- `hardware.graphics.enable = true` (`extraPackages = [ pkgs.mesa ]`) makes the ICD
  discoverable — **unchanged**.
- The device-selection variables move from `services.llama-cpp` to the **llama-swap**
  unit:
  ```nix
  systemd.services.llama-swap.environment.MESA_VK_DEVICE_SELECT = "1002:73e3!";
  # VK_ICD_FILENAMES is supplied by hardware.graphics; keep it inherited.
  ```
- The child keeps `--device Vulkan0 --n-gpu-layers 99` in its `cmd`
  ([llm-routers.nix:113-114](../../../../hosts/brys/llm-routers.nix#L113)). The env var is
  the suspenders and `--device Vulkan0` is the belt, exactly as the comment at
  [hosts/brys/llm.nix:494](../../../../hosts/brys/llm.nix#L494) states.

Because llama-swap runs all children in one unit, the grunt and the CPU children share
the same environment. `MESA_VK_DEVICE_SELECT` only affects Vulkan device selection, so it
is harmless to the CPU children. If a CPU child ever misbehaves under it, use llama-swap's
per-model `env:` list (config example) to set the variable only on the grunt model:

```yaml
models:
  qwen3.5-4b:
    env:
      - "MESA_VK_DEVICE_SELECT=1002:73e3!"
```

### systemd hardening

llama-swap spawns children, so the unit needs the permissions the children need today:
`ReadWritePaths = [ modelsDir ] ++ sessionStore.path`, `LimitMEMLOCK = infinity` (for a
future `load-mode mlock`), `SupplementaryGroups = [ sessionStore.group ]`, and
`PrivateDevices = false` (the nixpkgs module already sets this for GPU access — see
[.flake.patches/.../llama-swap.nix:141](../../../../.flake.patches/nixpkgs/repo/nixos/modules/services/networking/llama-swap.nix#L141)).
The nixpkgs module's default `ProtectHome`/`ProtectSystem = "strict"` is stricter than
the aspect's raw router units; verify the grunt still reaches `/dev/dri` (grant
`DeviceAllow` or `PrivateDevices = false`).

## 5. Session store and warm start

The Qwen session cache uses `--slot-save-path` + `--slot-save-sessions x-session-id` +
`--ctx-checkpoints` + `--checkpoint-min-step`
([llm.nix:337-340](../../../../hosts/brys/llm.nix#L337)). These are **child** flags and pass
to the Qwen child unchanged in §2.2. The store directory, group and prune timer
([llm.nix:1415](../../../../modules/den/aspects/llm.nix#L1415)) are unchanged.

### Does llama-swap's lifecycle help or hurt warm start?

- **Helps.** llama-swap's `ttl` is an *inactivity* timer that resets on every request
  (ttl-and-unloading). Setting `ttl: 0` on the Qwen model means **never auto-unload** —
  the orchestrator stays warm indefinitely, which is exactly what the current
  `--sleep-idle-seconds -1` gives. A `persistent`/high-cost frontier keeps the model
  loaded while a grunt swaps. So llama-swap's lifecycle **preserves** warm start.
- **Risk (the subtle part).** A restart of llama-swap **kills every child**. The child
  then reloads from disk (~90-120 s for Qwen/DS4). The disk session store survives that
  restart (the files are on disk and keyed by `x-session-id`), so a client that carries
  its session id resumes from the saved state instead of re-prefilling — the session KV
  is warm even when the process is cold. This is why the session store and llama-swap
  lifecycle are complementary, not redundant: the store covers the *restart* case, the
  `ttl: 0`/persistent covers the *idle* case.
- **Constraint.** The session cache needs the `llama-cpp-sessions` build. While the grunt
  is colocated it forces the Vulkan no-BLAS build on the whole aspect, so the session
  options are inert ([llm.nix:192-206](../../../../hosts/brys/llm.nix#L192)). With llama-swap
  the Qwen child can name the sessions build directly (§2.6, §7), which **restores** the
  session cache that the current single-package design loses.

## 6. Hot reload

llama-swap's config watch (`-watch-config`, a 2 s `os.Stat` poll; also `SIGHUP`) is
**stop-the-world**: it rebuilds the proxy, calls `old.Shutdown`, stops every upstream
child, cuts in-flight requests, fails queued requests, and reloads unrelated models from
disk. There is no differential reload and no `/api/config/reload`
([router-hot-reload.research.md §2](router-hot-reload.research.md)).

**Chosen mitigation — never reload llama-swap in place.** Rule set:

1. **Run llama-swap with `-watch-config=false`** (or `LLAMA_SWAP_WATCH_CONFIG=false`) so
   a config edit on disk never triggers the stop-the-world path by accident.
2. **Regenerate the config at activation.** Nix renders the YAML into the store; the
   service restarts only on an explicit activation that changed it. A model edit is a
   deploy, not a live reload.
3. **Keep the model→port route table in a hitless layer.** The compat-proxy already
   proxies to a single upstream; it (or Caddy, already deployed and hitless — SSE is not
   closed, [router-hot-reload.research.md §4](router-hot-reload.research.md)) is the
   layer that changes routes without a restart. With llama-swap owning the children, the
   `model=` id is the only route key; a *rename* of a served id is handled by adding the
   new id as an **alias** (llama-swap picks up aliases only via reload, so a rename still
   needs a restart — but an alias **addition** to a new model id can be an additive
   config, restarted at a quiet moment).
4. **If a live edit is unavoidable**, use the ~250-line atomic-pointer proxy sketch from
   [router-hot-reload.research.md §7](router-hot-reload.research.md) — but only after the
   simple "regenerate at activation" rule is in place; it is not needed for the initial
   migration.

The old per-router behaviour is actually *better* for a single-router edit: llama-server
router mode reloads one preset hitlessly via `GET /models?reload=1`, evicting only the
edited model ([router-hot-reload.research.md §3](router-hot-reload.research.md)). The
migration **gives that up** in exchange for the routing/priority features; the mitigation
above pays it back by making config edits a deploy event and keeping the hitless layer in
front.

## 7. Nix integration plan

Add one switch to the den `llm` aspect and render the llama-swap YAML from the existing
`kdn.llm.local.models` data. The models, aliases, perf fields, download service, session
store, Caddy wiring and LAN gate **do not change** — only the process that owns the
children changes.

### 7.1 New option set (aspect)

```nix
options.kdn.llm.local.swap = {
  enable = lib.mkEnableOption "llama-swap as the single model-lifecycle owner (replaces the routers)";
  port = lib.mkOption { type = lib.types.port; default = 39700; };
  healthCheckTimeout = lib.mkOption { type = lib.types.int; default = 900; };
  # "group" (default) or "matrix"; see §2.3.
  routerEngine = lib.mkOption { type = lib.types.enum [ "group" "matrix" ]; default = "group"; };
  # Per-model package override, so the Qwen child can run the sessions build while the
  # grunt child runs the Vulkan build (fixes the one-package constraint, §2.6).
  packageOverrides = lib.mkOption { type = lib.types.attrsOf lib.types.package; default = { }; };
  # The persistent/never-evict set: the frontier model ids. Rendered as the `persistent`
  # group or the high evict_costs in matrix.
  persistentModels = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
  ttl = { /* globalTTL + per-model override map */ };
};
```

### 7.2 What changes in the aspect

| Today | After |
|---|---|
| `presetSection` → INI text ([llm.nix:133](../../../../modules/den/aspects/llm.nix#L133)) | `cmdLines` → argv words per model; render one `models.<id>.cmd` YAML block |
| `presetIni` ([llm.nix:258](../../../../modules/den/aspects/llm.nix#L258)) | `swapConfig` = `pkgs.formats.yaml`-generated `config.yaml` (or the nixpkgs `services.llama-swap.settings` freeform — see [.flake.patches/.../llama-swap.nix:69](../../../../.flake.patches/nixpkgs/repo/nixos/modules/services/networking/llama-swap.nix#L69)) |
| `services.llama-cpp` ([llm.nix:1296](../../../../modules/den/aspects/llm.nix#L1296)) | `services.llama-swap = { enable = cfg.swap.enable; settings = swapConfig; ... }` |
| `routerUnits` + `routers` ([llm.nix:270-354](../../../../modules/den/aspects/llm.nix#L270)) | **removed** when `swap.enable` — the routing policy replaces them |
| `routerProxyEnv` ([llm.nix:280](../../../../modules/den/aspects/llm.nix#L280)) | **removed** — the proxy points at one upstream (llama-swap), no `ROUTER_*` table |
| `compatProxy.UPSTREAM_URL = http://127.0.0.1:<server.port>` ([llm.nix:1355](../../../../modules/den/aspects/llm.nix#L1355)) | points at `http://127.0.0.1:<swap.port>` when `swap.enable` |
| `alias = …` preset line ([llm.nix:216](../../../../modules/den/aspects/llm.nix#L216)) | model `aliases:` list |
| router `modelsMax` ([llm.nix:521](../../../../modules/den/aspects/llm.nix#L521)) | the `routing` engine (§2.3); the `routers.<name>` option is deprecated |
| `models.<name>.mainRouter` ([llm.nix:547](../../../../modules/den/aspects/llm.nix#L547)) | no longer needed; kept as a no-op alias for the small-set transition, or dropped |

The download service ([llm.nix:1379](../../../../modules/den/aspects/llm.nix#L1379)), the
session store ([llm.nix:1415](../../../../modules/den/aspects/llm.nix#L1415)), the Caddy
vhost ([llm.nix:1464](../../../../modules/den/aspects/llm.nix#L1464)) and the LAN gate all
stay as-is.

### 7.3 Two ways to render the YAML

1. **Freeform `settings`** into the nixpkgs `services.llama-swap` module (present in the
   pinned nixpkgs — [.flake.patches/.../llama-swap.nix](../../../../.flake.patches/nixpkgs/repo/nixos/modules/services/networking/llama-swap.nix)).
   Cleanest: the module writes `config.yaml`, sets the listen address, `CacheDirectory`
   and hardening. The aspect only builds `settings`.
2. **A raw `writeText` + hand-rolled unit**, mirroring today's `routerUnits`. More
   control (the per-model `env`, the memory slice), more code. Use this only if the
   module's hardening blocks the GPU grunt (`PrivateDevices = false` is already set in
   the module, so it likely does not).

**Recommendation:** option 1, with the module's `settings` built from the aspect's model
data, plus a small `systemd.services.llama-swap.environment` overlay for
`MESA_VK_DEVICE_SELECT`.

### 7.4 Migration order

1. **Add the `swap` option set and the YAML renderer** behind `swap.enable = false`. The
   renderer consumes the existing `models`/`aliases`/`perf` data; nothing else changes.
   Verify the rendered YAML with `nix eval` and a schema check.
2. **Prove the render** for the three target models (§2.2) against a manual llama-swap
   run on a spare port, with the real children, **without** touching the running service.
3. **Land the group engine** (§2.3) and the "never evict" rule; test a grunt request
   while the orchestrator is warm and confirm the orchestrator is not evicted.
4. **Switch the compat-proxy upstream** to the llama-swap port (one line,
   [llm.nix:1355](../../../../modules/den/aspects/llm.nix#L1355)) and drop `routerProxyEnv`.
5. **Remove `services.llama-cpp` and `routerUnits`** for hosts with `swap.enable = true`;
   keep them for hosts that have not migrated.
6. **Re-enable the Qwen session cache** under the per-model `packageOverrides` (§2.6),
   once the sessions build and the Vulkan grunt build coexist behind one router.
7. **Update `docs/local-llms.md`**, `hosts/brys/performance.md` and the aspect header to
   describe llama-swap; the tier/alias tables stay.

Each step is a separate commit with its own verification (per AGENTS.md).

## 8. Risks and unknowns

1. **Tool-call translation ownership.** The compat-proxy must stay in front. If it is ever
   folded into llama-swap (llama-swap has no DSML/XML translator), OpenCode tool calls
   break. **Unknown:** whether to keep the proxy as a separate unit or make the aspect
   `includes = [ kdn.llm-proxy ]` (already flagged as a DECISION TO REVISE at
   [llm.nix:36](../../../../modules/den/aspects/llm.nix#L36)). Recommendation: keep the proxy
   as-is for the first migration; do not fold it.

2. **Alias explosion and global uniqueness.** The DS4 and Qwen tier aliases are ~30 ids
   ([llm.nix:140-178](../../../../hosts/brys/llm.nix#L140)). llama-swap requires globally
   unique aliases; the current per-router rule allowed the same alias in two routers.
   **Unknown:** whether any client depends on an alias that would now collide. Mitigation:
   a render-time assertion on alias uniqueness (replaces the current per-router check at
   [llm.nix:1270](../../../../modules/den/aspects/llm.nix#L1270)).

3. **CPU-only `llama-cpp-sessions` build vs a Vulkan build with sessions.** The core
   trade-off ([llm.nix:192-206](../../../../hosts/brys/llm.nix#L192)) is **not** solved by
   llama-swap, but llama-swap lets each child name its own binary (§2.6). **Unknown:**
   whether the sessions patches apply cleanly to the Vulkan build; if not, the Qwen child
   runs the sessions build (CPU, no Vulkan — which is what brys already does) and the
   grunt child runs the Vulkan build. That split is exactly the goal.

4. **The grunt regression.** Today the grunt is on its own router so a grunt request can
   never touch the orchestrator. In one llama-swap process the guarantee is a routing
   policy, not a process boundary. **Unknown:** whether the group/matrix engine protects
   an in-flight orchestrator request as strictly as a separate process did. The
   active-request protection (ttl resets on each request; a swap happens only between
   turns) is documented but must be **measured** on brys before the old routers are
   removed. Acceptance: a grunt request while a Qwen request is in flight must not evict
   Qwen ([definition.md](./definition.md) acceptance criteria).

5. **Memory-cap admission.** llama-swap monitors RAM/GPU but has **no admission gate**
   ([llama-router-scheduler.research.md §3-4](llama-router-scheduler.research.md)). A load
   that would OOM is not refused. Keep the measured-profile spawn gate + the
   `MemoryMax`-capped slice from the scheduler research; this work is **orthogonal** to the
   migration and stays a follow-up.

6. **Testing without disturbing the running server.** brys is the live LLM box. The
   migration must be proven on a spare port with the real children before any switch. The
   boot-specialisation model helps: a new `llm-swap` boot entry can serve the topology
   without changing the running profile. **Unknown:** whether the one-box RAM budget
   allows a parallel llama-swap run beside the live routers during the test (two DS4/Qwen
   copies do not fit). Prefer a boot entry over a live parallel run.

7. **Restart cost.** Any llama-swap restart kills every child (~90-120 s reload). This is
   worse than the current per-router reload for a single-model edit. Mitigation: §6
   (`-watch-config=false`, regenerate at activation, hitless route layer).

8. **`ServiceName`/port drift.** The aspect's `kdn-llm-status` script
   ([llm.nix:1499](../../../../modules/den/aspects/llm.nix#L1499)) and the appliance notes
   reference `llama-cpp`. Update them for llama-swap when `swap.enable` is set.

## 9. Verification ledger

**`[V]` verified this design:** `pkgs.llama-swap` is version **249**, SPDX **MIT**
(`nix eval nixpkgs#llama-swap.{version,meta.license.spdxId}`); a
`services.llama-swap` NixOS module is in the pinned nixpkgs
([.flake.patches/.../llama-swap.nix](../../../../.flake.patches/nixpkgs/repo/nixos/modules/services/networking/llama-swap.nix)),
with `settings` freeform, `listenAddress`/`port`, TLS, `CacheDirectory` and
`PrivateDevices = false`. llama-swap config: `models.<id>.cmd` with `${PORT}`,
`aliases`, `includeAliasesInList`, `ttl`/`globalTTL` (inactivity, resets on request),
`unloadTimeout`, `env`, `healthCheckTimeout`, `startPort`, `routing.router.use`
(`group`/`matrix`), `groups.persistent`, `matrix.evict_costs`, `scheduler.fifo.priority`
— from the llama-swap README, `docs/config.example.yaml` and the
groups-and-matrix / ttl-and-unloading / capacity-and-queues / writing-cmd guides.
stop-the-world reload — [router-hot-reload.research.md §2](router-hot-reload.research.md)
(llama-swap issue #1202). The aspect data, port and wiring line numbers are from
[modules/den/aspects/llm.nix](../../../../modules/den/aspects/llm.nix),
[hosts/brys/llm.nix](../../../../hosts/brys/llm.nix) and
[hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix).

**`[I]` inferred:** the suite of flag names in §2.1 (a mechanical rename of the preset
keys the aspect already emits); that the nixpkgs module's hardening permits `/dev/dri`
access for the grunt (it sets `PrivateDevices = false`, but `DeviceAllow` is untested);
that per-model package overrides render cleanly into `cmd`; the port 39700 choice.
