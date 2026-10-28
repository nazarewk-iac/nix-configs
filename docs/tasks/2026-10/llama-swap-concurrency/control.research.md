---
type: Research
description: The verified llama-swap control surface, the fact that an unload silently truncates an in-flight stream, and the resource limits a watcher can read.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T10:20:00+01:00
---

# llama-swap control surface & admission policy — brys (llama-swap v249, commit f94c94a)

**Control endpoints (from `/ui/assets/api-BqGyz_4A.js` + probes on :39700).**
1. `GET /v1/models` — model list incl. `status.value` (unloaded|ready). `GET /running` — `{"running":[{name,state,cmd,port...}]}`. `GET /health` — 200.
2. `POST /api/models/unload` → `200 {"msg":"ok"}` (all). `POST /api/models/unload/{model}` → `200 "OK"` (named; unknown → `404 {"error":"model not found","src":"llama-swap"}`).
3. **Load path = `GET /upstream/{model}/?_=<ts>`** (JS `Pc`). It returns `404 "File Not Found"` (llama-server has no `/`) but the side effect loads the model. No `/api/models/load|start|preload` exists (all 404, both verbs).
4. Others: `GET /api/version`, `GET /api/performance` (growing NDJSON host+GPU stream), `/api/hardware`, `/api/events` (SSE), `/api/captures/{m}`, `/api/profiles` + `PUT /api/profiles/active`, `/api/metrics/activity|stats`, `POST /api/inflight/{m}/cancel` (404 while not throttled).

**Minimal load/unload (verified).** Idle `unload/tiny-dumb-fast` → `200 OK` (no-op OK). `GET /upstream/tiny-dumb-fast/` → 404 body, then `/running` shows `qwen3.5-0.8b` `state:"ready"` **with no chat request**. Unload → `/running` empty. (Note: an external client also runs `granite-4.2-8b`/`qwen3.5-4b`; box left idle, `/running:[]`.)

**Critical: unload DURING an in-flight request = silent TRUNCATION.** Streaming `chat-dumb-fast` (max_tokens 200) then `POST unload` mid-stream: client got `HTTP 200`, 39 `data:` chunks, **0 `[DONE]`**, `finish_reason` only `null`, `curl` exit 0 (clean TCP EOF). Stream tail quoted: `...delta":{"content":" Ant"}}]...}` then EOF — cut mid-word. Journal: `[qwen3.5-4b] sending stop signal with timeout 30s` → `process_new_: terminate` → `recovered from upstream disconnection during streaming` → `process exited cleanly`. **llama-swap does NOT drain in-flight requests; it kills the backend and the client sees a malformed-but-cleanly-closed SSE.** No error object, no 5xx.

**Limits available to a watcher.**
5. `systemctl show llama-swap`: `MainPID=14765`, `MemoryCurrent=44541890560` (~41.9 GiB), `MemoryMax=infinity`, `Delegate=no`, `ControlGroup=/system.slice/llama-swap.service`.
6. cgroup `/sys/fs/cgroup/system.slice/llama-swap.service`: `memory.current≈41.8 GiB`, **`memory.max = max` (unlimited)**, `memory.peak≈50.4 GiB`, `memory.events oom_kill 0`, `pids.current 65`. **Caveat: memory.stat `anon=654 MiB`, `file=41996 MiB` — `memory.current` is almost all page cache from `--load-mode mmap` GGUF; unusable as a VRAM/RSS proxy, and no cap exists.** Use `anon` + host `MemAvailable` (111621 MiB) instead.
7. Children **share the same cgroup**: `llama-server pid=112409` → `/proc/112409/cgroup = 0::/system.slice/llama-swap.service` (identical to MainPID); port 10029 → pid 112409 via `sudo ss -tlnp`.
8. VRAM via `GET /api/performance` → `gpu_stats[]` each `{id,name,mem_used_mb,mem_total_mb}`: `id0 "AMD Radeon Pro W6600 card0 (gfx1032)" 47/8176 MiB`, `id1 "AMD Radeon RX 550 card1 (gfx803)" 13/4096 MiB`. Cross-check `/sys/class/drm/card*/device/mem_info_vram_{used,total}`: card0=13/4096 (pci 0e:00.0, dev 0x699f=RX550), card1=47/8176 (pci 0d:00.0, dev 0x73e3=W6600). **Naming mismatch: perf `name` "...card0" is sysfs `card1`; match by `mem_total_mb`+gfx arch, never by the JSON `cardN` label or id.**
9. Config: `globalTTL: 0` (models never auto-expire), **no `groups`, no `swap`, no per-model `ttl`/`persistent`/`exclusive`** → llama-swap enforces **no** VRAM admission; concurrent loads are allowed and unbounded by the cgroup.

**Invariants llama-swap already guarantees vs. what the watcher must enforce.** llama-swap guarantees only: single-writer state machine per model, eviction-on-swap accounting (`matrix: starting swap ... evicting [...]`), clean process teardown. It **violates** any "never unload with in-flight request" invariant (proven above) and does **not** evict on memory pressure, does not protect persistent models, does not queue. The watcher must own all admission.

```text
# ---- admission policy (watcher-owned invariants) ----
INPUTS
  req.model            requested model id/alias
  gguf_bytes[m]        file size of model m (qwen3.5-0.8b=532MB, 4b=2740MB, granite-3b=2244MB, ...)
  running[]            GET /running  -> {name,state}
  inflight[m]          watcher's own req-count per model (llama-swap has no API; TRACK IT OURSELVES)
  memavail_mb          host /proc/meminfo MemAvailable      # NOT cgroup memory.current (page cache)
  anon_mb              cgroup memory.stat anon              # true private RSS
  vram_used,gpu_total  /api/performance gpu_stats (W6600: match mem_total_mb==8176, gfx1032)
  persistent[m]        policy table, NOT llama-swap (no such flag in config)

CONSTANTS  RAM_FLOOR=8GiB (memavail), VRAM_HEADROOM=1GiB, EST_VRAM(m)≈gguf_bytes + 0.9GiB overhead
INV1 (mandatory, llama-swap VIOLATES): never unload m while inflight[m] > 0
INV2 (mandatory, llama-swap VIOLATES): never evict persistent[m] for a non-persistent "grunt"
INV3 never load a model whose EST_VRAM > free VRAM on its target GPU, nor exceed RAM_FLOOR

admit(req):
  if running.req.state == ready:                      return ALLOW            # fast path
  need_vram = EST_VRAM(req); need_ram = gguf_bytes(req)
  if free_vram >= need_vram + VRAM_HEADROOM and memavail_mb - need_ram_mb >= RAM_FLOOR:
        return LOAD(req)                                                    # => GET /upstream/{req}/
  # must free space: candidate victims
  victims = [m in running if inflight[m]==0 and not persistent[m]]
            sorted by (last_used asc, EST_VRAM asc)
  if persistent[req]:
        victims = [m in running if inflight[m]==0]        # persistent may evict idle non-persistent
        # NEVER evict another persistent to make room -> refuse if only persistents idle
  freed=0
  for m in victims:
        EVICT(m)   # POST /api/models/unload/{m}  (safe: inflight==0 checked)
        freed += EST_VRAM(m)
        if freed >= need_vram: break
  if freed >= need_vram: return LOAD(req)
  else:                  return QUEUE(req, retry=T)   # or REFUSE if queue full / client timeout

on_request_end(model): inflight[model] -= 1   # MUST bookend every proxied request ourselves
# unload path: watcher only ever calls unload with inflight[m]==0 (llama-swap will NOT check)
```
