---
type: Research
description: The verified llama-swap data surface on brys: activity ring size, event payloads, alias-vs-base-id, captures, and the collector schema built on them.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T10:20:00+01:00
---

# llama-swap data surface — verified on `brys` (v249) + stats-collector design

Repo: `/home/kdn/dev/github.com/nazarewk-iac/nix-configs` (read only).
Host: `brys`, llama-swap `http://127.0.0.1:39700`, binary
`/nix/store/b419b8zjk5y1sr11s7bmbx0lcjlzbx9m-llama-swap-249/bin/llama-swap`.
Config: `/nix/store/vhssi9i9857zg6qkm8dwp66smakvcr1a-config.yaml`.
Service: `llama-swap.service`, `DynamicUser=true`, `PrivateTmp=true`,
`CacheDirectory=llama-swap`, `ProtectSystem=strict`, cwd `/tmp`.

This is a custom fork ("matrix" fast-path, captures, typed events, `/api/metrics/*`),
**not upstream llama-swap**. Upstream docs do not apply. All numbers below were measured
2026-10-28 with `curl --max-time` against the live service.

The four promoted facts from the prompt were re-verified and hold:
`/api/metrics/activity` (per-request records), `/api/metrics/stats` (totals + p50/p95/p99),
`/api/performance` (per-GPU), `/api/hardware` (one-shot inventory), and `/api/events`
(SSE, replays buffered history on connect). Three of the five event types listed in the
prompt are wrong/incomplete — corrected in §2 and §7.

---

## 1. Does `/api/events?no-history` suppress the replay? — **No.**

Command (connect 2 s, both, count event types and bytes):

```
for q in "" "?no-history"; do
  curl -sS --max-time 2 "http://127.0.0.1:39700/api/events$q" \
    | tee /tmp/ev.$$ | grep -aoE '"type":"[a-zA-Z]+"' | sort | uniq -c
  echo "bytes=$(wc -c </tmp/ev.$$)"; rm -f /tmp/ev.$$
done
```

Output:

```
== /api/events ==
      1 "type":"inflight"
      2 "type":"logData"
      1 "type":"modelStatus"
      1 "type":"profileChanged"
      1 "type":"uiConfig"
bytes=219241
== /api/events?no-history ==
      1 "type":"inflight"
      2 "type":"logData"
      1 "type":"modelStatus"
      1 "type":"profileChanged"
      1 "type":"uiConfig"
bytes=219253
```

Identical. `?no-history` is ignored by `/api/events`. The 2 `logData` events are the
replayed log history (~219 KB). The `no-history` string exists in the binary but belongs
to `/logs/stream` (`GET /logs/stream` … `no-history`), not `/api/events`.

**Consequence:** a collector that connects to `/api/events` always receives the full
`modelStatus` + `logData` + `uiConfig` + `profileChanged` + `inflight:snapshot` replay.
It must tolerate that (drop `logData`, dedup the rest).

---

## 2. Exact payloads of `activity`, `modelStatus`, `inflight`

Wire format of every SSE frame: one `event:message` line, one `data:` line whose value is
`{"type":"<t>","data":"<JSON encoded as a STRING>"}` — the payload is **double-encoded**.

### `modelStatus` — full list, sent on every state change and on connect

```
data:{"type":"modelStatus","data":"[{\"id\":\"deepseek-v4-flash\",...,\"state\":\"stopped\",\"unlisted\":false,\"peerID\":\"\",\"aliases\":[\"frontier\",\"orchestrate-deep-slow-alt\"]},{...,\"id\":\"granite-4.2-8b\",\"state\":\"ready\",\"aliases\":[\"tools-std-fast-alt\"]},{...,\"id\":\"qwen3.5-4b\",\"state\":\"stopped\",\"aliases\":[\"grunt\",\"chat-dumb-fast\",\"code-quick-fast\",\"tiny-quick-fast\"]},...]"}
```

Element shape: `{ id, name, description, state, unlisted, peerID, aliases? }`.
`state ∈ stopped|loading|ready`; `aliases` present only when non-empty.

### `inflight` — three operations

```
data:{"type":"inflight","data":"{\"operation\":\"snapshot\"}"}
data:{"type":"inflight","data":"{\"operation\":\"upsert\",\"request\":{\"id\":\"620\",\"timestamp\":\"2026-10-28T10:06:15.153740649+01:00\",\"model\":\"qwen3.5-0.8b\",\"req_path\":\"/v1/chat/completions\",\"method\":\"POST\",\"req_headers\":{\"Accept\":\"*/*\",\"Authorization\":\"[REDACTED]\",\"Content-Length\":\"104\",\"Content-Type\":\"application/json\",\"User-Agent\":\"curl/8.22.0\"},\"remote_ip\":\"127.0.0.1\",\"resp_headers\":{},\"resp_bytes\":0,\"elapsed_ms\":0}}"}
data:{"type":"inflight","data":"{\"operation\":\"remove\",\"id\":\"621\"}"}
```

`upsert` repeats many times during one request (progress); `remove` closes it;
`snapshot` opens the stream. `Authorization` is `[REDACTED]` in `req_headers`.
The `request.id` is the same integer id used by the activity record and the capture.

### `activity` — **only the id, not the record**

```
data:{"type":"activity","data":"{\"id\":621}"}
```

**Critical:** the `activity` event carries `{"id":N}` only. The full record must be read
from `/api/metrics/activity` (there is **no** `GET /api/metrics/activity/<id>` — it 404s).

### The full record the collector actually wants (`/api/metrics/activity` → `.data[]`)

```json
{
  "id": 631,
  "timestamp": "2026-10-28T10:09:07+01:00",
  "model": "granite-4.2-3b",
  "req_path": "/v1/chat/completions",
  "resp_content_type": "application/json; charset=utf-8",
  "resp_status_code": 200,
  "tokens": {
    "cache_tokens": 0,
    "draft_tokens": -1,
    "draft_acc_tokens": -1,
    "input_tokens": 16,
    "output_tokens": 6,
    "prompt_per_second": 195.70907845487682,
    "tokens_per_second": 81.10563197508435
  },
  "duration_ms": 2416,
  "has_capture": true,
  "metadata": { "fifo_priority": "0" }
}
```

Keys (exact): `id timestamp model req_path resp_content_type resp_status_code tokens
duration_ms has_capture metadata`. `tokens` keys: `cache_tokens draft_tokens
draft_acc_tokens input_tokens output_tokens prompt_per_second tokens_per_second`.
`draft_tokens`/`draft_acc_tokens` are `-1` when speculative decode was off. `metadata` is
`{"fifo_priority":"<string>"}`. `timestamp` is **second** precision (the `inflight` one is
nanosecond precision). `resp_content_type` distinguishes streaming (`text/event-stream`)
from non-stream (`application/json; charset=utf-8`).

### Empirical: the `activity` event is emitted on **streaming responses only**

- Streaming (`tiny-dumb-fast`, id 621/622): `data:{"type":"activity","data":"{\"id\":621}"}`
  observed, followed by `inflight:remove`.
- Non-streaming (`granite-4.2-3b`, id 631; and `tiny-dumb-fast`, ids 619/620): **no**
  `activity` event observed after 6–8 s wait, **but the record IS present** in
  `/api/metrics/activity`.

Therefore the `activity` event is an unreliable trigger for non-stream calls. The
collector **must poll** `/api/metrics/activity`; it may additionally use the event as a
fast wake-up for streaming calls.

---

## 3. Base model id or alias? — **Base id.**

Request sent: `{"model":"chat-dumb-fast",...}` (an alias of `qwen3.5-4b`).
Record read back:

```
{"id":618,"model":"qwen3.5-4b", ... "input_tokens":14,"output_tokens":8, ...}
```

The response `model` field is the checkpoint path
`/var/lib/kdn/llms/models/surveyed/qwen3.5-4b.gguf`; the **activity record's `model` is the
base router model id `qwen3.5-4b`**, not the alias `chat-dumb-fast`.

**Consequence:** the JSONL `model` alone cannot attribute four aliases
(`grunt`, `chat-dumb-fast`, `code-quick-fast`, `tiny-quick-fast`) that share `qwen3.5-4b`.
The collector must resolve id → aliases. The authoritative live map is the `modelStatus`
event's `aliases` arrays (see §Design B). `hosts/brys/llm-routers.nix` is a valid offline
source but the live `modelStatus` already encodes the launched routing table.

---

## 4. Ring sizes

- **Activity ring = 25 records (measured, hard cap).** Sending 5 sequential tiny requests:
  ```
  total_requests before: 623   activity .data length before: 25   ids: [599, 623]
  total_requests after:  628   activity .data length after:  25   ids: [604, 628]
  ```
  Length stays 25 while `total_requests` grows; the window slides by one per request.
- **Capture ring = `captureBuffer` = 50** (`/nix/store/vhssi9i9857zg6qkm8dwp66smakvcr1a-config.yaml`
  line 3: `captureBuffer: 50`). This bounds the compressed request/response bodies, a
  **different** ring from the activity list.

**Consequence:** only the last **25** finished requests are queryable. A poll that misses
more than 25 completions between two reads loses data. The collector must poll well under
that (design assumes ≤ 2 s, i.e. 12 req/s of headroom) or use event+wake for streaming.

## 5. `/api/captures/<id>` redaction — **confirmed**

```
$ curl -sS http://127.0.0.1:39700/api/captures/618 | jq -c .req_headers.Authorization
"[REDACTED]"
```

Top-level keys: `id req_path req_headers req_body resp_headers resp_body`.
`req_body`/`resp_body` are base64. `Authorization` in `req_headers` is always
`[REDACTED]`, including for a request that carried a real `Bearer` token (id 618).
No key is needed to read captures, activity or stats (only `/v1/*` needs the API key).

## 6. Is `/api/metrics/activity` cleared by `systemctl restart llama-swap`? — **Yes (design implies it).** No restart performed.

Evidence that nothing persists it:

- `/proc/<pid>/cwd -> /tmp` (PrivateTmp; tmpfs root on brys).
- Writable dirs hold no metrics DB: `/var/cache/private/llama-swap/` = `api-keys`,
  `mesa_shader_cache`, `radv_builtin_shaders`; `/var/lib/kdn/llms/sessions/` = `*.bin`
  llama.cpp KV sessions only. No `.db`/`.sqlite`/`.jsonl` anywhere.
- `config.yaml` top-level keys (`captureBuffer globalTTL healthCheckTimeout
includeAliasesInList logLevel logTimeFormat logToStdout models routing startPort
unloadTimeout`) contain **no** persistence key.
- The sqlite strings in the binary (`PRAGMA journal_mode = WAL`, `migrations`) are from a
  linked library / unused code — no DB file is ever created.
- `id` is a per-process monotonic counter (now 631 after 15 h of uptime); after a restart
  it restarts from 1. This is the in-memory design's tell.

**Consequence:** the collector needs a _generation_ marker (service start time) so it can
tell a restarted id sequence from a continued one, and must persist the JSONL itself.

---

## 7. Corrections to `docs/tasks/2026-10/llm-metrics-persistence/research.md`

1. §2 claims `activity` payload = "the finished request record". It is `{"id":N}` only (§2).
2. §2 lists 5 event types; the stream also emits `uiConfig` and `profileChanged` on every
   connect, and `inflight` has `snapshot`/`upsert`/`remove`.
3. It assumes `captureBuffer` bounds the activity ring. It does not: activity is a fixed
   **25**; `captureBuffer`=50 bounds _captures_ (§4).
4. It leaves `?no-history` "not verified". Verified: it does nothing on `/api/events` (§1).
5. `activity` is emitted for streaming calls only; non-stream calls are silent on the SSE
   stream (§2). Polling is mandatory.

---

# Design: the stats collector

One small systemd service (`llm-stats-collector`) on `brys`, subscribing/polling the local
API, appending JSONL, and (optionally) writing a Prometheus textfile. No new port, no DB.

## A. JSONL schema — one line per finished request

File: `/var/lib/llm-stats/requests/YYYY-MM-DD.jsonl` (UTC day).

| field               | type           | source                                   | notes                                |
| ------------------- | -------------- | ---------------------------------------- | ------------------------------------ |
| `ts`                | string RFC3339 | `record.timestamp`                       | second precision, +01:00 offset      |
| `id`                | integer        | `record.id`                              | monotonic **within a generation**    |
| `generation`        | string         | `systemctl show -p ActiveEnterTimestamp` | id sequence scope (§6)               |
| `host`              | string         | const `"brys"`                           | multi-host future                    |
| `model`             | string         | `record.model`                           | **base id**, e.g. `qwen3.5-4b`       |
| `aliases`           | array<string>  | `modelStatus` map                        | aliases at write time (`[]` if none) |
| `routing_version`   | string         | `sha256` of sorted id→aliases map        | detects routing-table change (§B)    |
| `req_path`          | string         | `record.req_path`                        | e.g. `/v1/chat/completions`          |
| `status`            | integer        | `record.resp_status_code`                | HTTP status                          |
| `content_type`      | string         | `record.resp_content_type`               | stream vs json                       |
| `duration_ms`       | integer        | `record.duration_ms`                     | wall time                            |
| `input_tokens`      | integer        | `tokens.input_tokens`                    |                                      |
| `output_tokens`     | integer        | `tokens.output_tokens`                   |                                      |
| `cache_tokens`      | integer        | `tokens.cache_tokens`                    | prompt-cache hits                    |
| `draft_tokens`      | integer        | `tokens.draft_tokens`                    | `-1` when spec-decode off            |
| `draft_acc_tokens`  | integer        | `tokens.draft_acc_tokens`                | `-1` when off                        |
| `prompt_per_second` | number         | `tokens.prompt_per_second`               | prefill rate                         |
| `tokens_per_second` | number         | `tokens.tokens_per_second`               | decode rate                          |
| `fifo_priority`     | string         | `metadata.fifo_priority`                 | string, keep as string               |
| `has_capture`       | boolean        | `record.has_capture`                     | capture ring may have rotated        |
| `collected_at`      | string RFC3339 | collector clock                          | when the line was written            |

Notes: `aliases` is a JSON array; keep it as data (not just a label) so historical lines
stay self-describing after the routing table changes. Numeric rates are floats; keep full
precision. `status` distinguishes 200 from errors.

## B. Alias resolution and routing-table change detection

- Source of truth: the `modelStatus` event. Build `id → aliases` from the latest event
  (`aliases` defaults to `[]`). This is what the running process actually launched, so it
  tracks edits to `hosts/brys/llm-routers.nix` after the next `nixos-rebuild switch`
  **without** the collector parsing Nix.
- `routing_version = sha256( canonical_json( [ {id, aliases} ] sorted by id ) )`.
- On each `modelStatus` event, recompute the hash. If it changed, every subsequent JSONL
  line carries the new `routing_version`; optionally append one sidecar line
  `{"event":"routing","routing_version":...,"ts":...,"map":{...}}` to
  `requests/YYYY-MM-DD.jsonl` so a reader can reconstruct the map for any window.
- Offline fallback (if the event replay is unavailable): generate the same `{id,aliases}`
  map from `hosts/brys/llm-routers.nix` (`kdn.llm.local.models.*.aliases`) and feed it in;
  the hash scheme makes the two sources directly comparable.
- Per-alias attribution in reports: `alias ∈ aliases ? aliases : [model]`.

## C. Resume / dedup across reconnects

- Persist a tiny state file `/var/lib/llm-stats/.state.json`:
  `{"generation":"<ActiveEnterTimestamp>","last_id":<int>,"counters":{...}}`.
- Dedup key = `(generation, id)`. Activity ids restart at 1 on restart, so a bare `id`
  watermark is wrong across a restart; compare the current generation first — if it
  differs, reset `last_id=0` and start a new generation (a new id space).
- On start (and on every poll) `GET /api/metrics/activity`, keep records with
  `id > last_id`, sort by id, append. Because the API replays history and the ring is 25,
  a short outage re-fetches whatever is still in the ring; anything older than 25 is gone
  — hence poll interval ≤ 2 s.
- The SSE `activity`/`inflight` events are an optional low-latency wake-up (force an
  immediate poll); the poll is the correctness path. Ignore `logData` entirely; use
  `modelStatus` only for the alias map.

## D. Rotation

- By UTC day: `requests/YYYY-MM-DD.jsonl`.
- Keep `N = 30` days: a `systemd.timer` (or `logrotate`) runs daily:
  `find /var/lib/llm-stats/requests -name '*.jsonl' -mtime +30 -delete`.
- Total size cap `CAP = 512M`: after the age prune, while
  `du -sb requests > CAP`, delete the oldest `*.jsonl`. (Metrics JSONL is ~0.5–1 KB per
  request; 512 MB ≈ 0.5–1 M requests ≈ weeks at brys' rate.)
- Same timer writes the `.prom` snapshot (below) so dashboards stay fresh even when idle.

## E. Prometheus textfile variant

The collector also writes `/var/lib/node-exporter/textfile/llm-stats.prom` (atomic:
write `*.tmp` then `mv`). It maintains cumulative counters in `.state.json` so the values
are monotonic across polls (a counter reset on collector restart is fine — Prometheus
handles it).

```
# HELP llamaswap_requests_total Finished requests.
# TYPE llamaswap_requests_total counter
llamaswap_requests_total{model="qwen3.5-4b",alias="chat-dumb-fast",status="200"} 812
# HELP llamaswap_input_tokens_total Input (prompt) tokens.
# TYPE llamaswap_input_tokens_total counter
llamaswap_input_tokens_total{model="qwen3.5-4b",alias="chat-dumb-fast"} 128800
# HELP llamaswap_output_tokens_total Output (generated) tokens.
# TYPE llamaswap_output_tokens_total counter
llamaswap_output_tokens_total{model="qwen3.5-4b",alias="chat-dumb-fast"} 41200
# HELP llamaswap_cache_tokens_total Prompt-cache tokens served.
# TYPE llamaswap_cache_tokens_total counter
llamaswap_cache_tokens_total{model="qwen3.5-4b",alias="chat-dumb-fast"} 51200
# HELP llamaswap_prompt_tokens_per_second Last observed prefill rate.
# TYPE llamaswap_prompt_tokens_per_second gauge
llamaswap_prompt_tokens_per_second{model="qwen3.5-4b",alias="chat-dumb-fast"} 195.71
# HELP llamaswap_gen_tokens_per_second Last observed decode rate.
# TYPE llamaswap_gen_tokens_per_second gauge
llamaswap_gen_tokens_per_second{model="qwen3.5-4b",alias="chat-dumb-fast"} 81.11
# HELP llamaswap_duration_seconds Request duration.
# TYPE llamaswap_duration_seconds summary
llamaswap_duration_seconds_sum{model="qwen3.5-4b",alias="chat-dumb-fast"} 1460.2
llamaswap_duration_seconds_count{model="qwen3.5-4b",alias="chat-dumb-fast"} 812
# HELP llamaswap_up Collector heartbeat.
# TYPE llamaswap_up gauge
llamaswap_up 1
```

Label policy: `model` = base id (always present). `alias` = one series per alias the model
answers to (a model with 4 aliases yields 4 series; a model with none uses `alias="model"`).
`status` only on `_requests_total`. Cardinality ≈ 40 models × ≤5 aliases × 8 metrics ≈ a
few hundred series.

### NixOS wiring — option 1: node_exporter textfile collector (recommended, standard)

`node_exporter` is not enabled anywhere in the repo today, so add it:

```nix
services.prometheus.exporters.node = {
  enable = true;
  enabledCollectors = [ "textfile" ];
  extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter/textfile" ];
};
services.prometheus.scrapeConfigs = [{
  job_name = "node";
  static_configs = [{
    targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
  }];
}];
```

The collector's systemd unit gets `ReadWritePaths = [ "/var/lib/node-exporter/textfile" ]`
and writes the `.prom` file there.

### NixOS wiring — option 2: dedicated exporter (no node_exporter)

The collector serves `GET /metrics` on `127.0.0.1:39701` in Prometheus format; scrape it:

```nix
services.prometheus.scrapeConfigs = [{
  job_name = "llm-stats";
  static_configs = [{ targets = [ "127.0.0.1:39701" ]; }];
}];
```

Both sit beside `services.prometheus.enable = true` from
`modules/den/aspects/monitoring.nix` (which already wires Prometheus + Grafana + Caddy and
sets `retentionTime`/`retentionSize`).

## F. Storage — the exact `kdn.disks.persist` entry

`brys` uses the impermanence layout from `modules/den/aspects/disks.nix`: **tmpfs root**
(`disko.devices.nodev."/"` = tmpfs, `:543-556`), only paths listed under
`kdn.disks.persist` are bind-mounted back by `preservation` (`:713-735`). Unlisted paths
live in tmpfs and **vanish at reboot**. The `disposable` bucket is deliberately rolled
back on every boot (`:678`, `rollback to @empty`) — putting data there looks persisted and
is not. The shape is declared by `modules/den/common/persist.nix`: each bucket is
`{ directories = [...]; files = [...]; }`; an entry is either a string path or an
attribute set (`{ directory; mode; user; group; ... }`, freeform → tmpfiles-style).

Put the JSONL history in the non-disposable `sys/state` bucket (stateful, `snapshots=false`,
survives reboot and is not rolled back — the same bucket that already holds `/var/log`):

```nix
users.users.llm-stats = { isSystemUser = true; group = "llm-stats"; };
users.groups.llm-stats = { };

kdn.disks.persist."sys/state".directories = [
  { directory = "/var/lib/llm-stats"; mode = "0750"; user = "llm-stats"; group = "llm-stats"; }
];
# The node_exporter textfile directory is regenerated every poll; it MAY be ephemeral
# (tmpfs). Persist it only if you want the last .prom to survive a reboot:
kdn.disks.persist."sys/state".directories = [
  { directory = "/var/lib/node-exporter/textfile"; mode = "0755"; }
];
```

Do **not** use `kdn.disks.persist."disposable"`. If ZFS snapshots of the metrics are
wanted, use `sys/data` (`snapshots=true`) instead of `sys/state` — same shape.

The collector unit then needs `ReadWritePaths = [ "/var/lib/llm-stats" ]` (and the textfile
dir for option 1). It runs as `User=llm-stats`, so the persist entry must create the dir
with that owner — which the `{ directory; user; group; }` form above does.

## G. Implementation sketch (bash + jq, ~40 lines)

```bash
#!/usr/bin/env bash
# llm-stats-collector: poll the 25-record activity ring, append JSONL, emit .prom
set -euo pipefail
BASE=http://127.0.0.1:39700
DIR=/var/lib/llm-stats
STATE=$DIR/.state.json
PROM=/var/lib/node-exporter/textfile/llm-stats.prom
GEN=$(systemctl show -p ActiveEnterTimestamp --value llama-swap)
DAY=$(date -u +%F); OUT=$DIR/requests/$DAY.jsonl
mkdir -p "$DIR/requests" "$(dirname "$PROM")"

prev_gen=$(jq -r '.generation // ""' "$STATE" 2>/dev/null || echo "")
last=$(jq -r '.last_id // 0'       "$STATE" 2>/dev/null || echo 0)
[ "$prev_gen" = "$GEN" ] || last=0                       # id space restarted (§C)

map=$(curl -sS --max-time 3 "$BASE/api/events?no-history" 2>/dev/null \
      | grep -a '"type":"modelStatus"' | head -1 \
      | sed 's/^data://' | jq -c '.data | fromjson')     # id -> aliases (§B)
rver=$(printf '%s' "$map" | jq -Sc '[.[]|{id,aliases:(.aliases//[])}]|sort_by(.id)' \
       | sha256sum | cut -d' ' -f1)

resp=$(curl -sS --max-time 5 "$BASE/api/metrics/activity")
lines=$(printf '%s' "$resp" | jq -c --argjson last "$last" \
        '.data|map(select(.id>$last))|sort_by(.id)')
printf '%s' "$lines" | jq -c --argjson map "$map" --arg gen "$GEN" --arg rver "$rver" \
  --arg host brys --arg now "$(date -Iseconds)" '
    .[] as $r | {ts:$r.timestamp,id:$r.id,generation:$gen,host:$host,
      model:$r.model,aliases:([$map[]|select(.id==$r.model)|.aliases][0]//[]),
      routing_version:$rver,req_path:$r.req_path,status:$r.resp_status_code,
      content_type:$r.resp_content_type,duration_ms:$r.duration_ms,
      input_tokens:$r.tokens.input_tokens,output_tokens:$r.tokens.output_tokens,
      cache_tokens:$r.tokens.cache_tokens,draft_tokens:$r.tokens.draft_tokens,
      draft_acc_tokens:$r.tokens.draft_acc_tokens,
      prompt_per_second:$r.tokens.prompt_per_second,
      tokens_per_second:$r.tokens.tokens_per_second,
      fifo_priority:$r.metadata.fifo_priority,has_capture:$r.has_capture,
      collected_at:$now}' >>"$OUT"

newlast=$(printf '%s' "$lines" | jq 'if length>0 then .[-1].id else $last end' --argjson last "$last")
jq -n --arg gen "$GEN" --argjson last "$newlast" '{generation:$gen,last_id:$last}' >"$STATE.tmp"
mv "$STATE.tmp" "$STATE"

# rotation: drop >30 days and enforce a size cap (also run from the daily timer)
find "$DIR/requests" -name '*.jsonl' -mtime +30 -delete
while [ "$(du -sb "$DIR/requests" | cut -f1)" -gt $((512*1024*1024)) ]; do
  oldest=$(ls -1t "$DIR/requests"/*.jsonl 2>/dev/null | tail -1) || break
  [ -n "$oldest" ] && rm -f "$oldest" || break
done
# (textfile emission from .state.json counters is the same shape; omitted here)
```

Run as `systemd.services.llm-stats-collector` (Type=oneshot on a 2 s `.timer`, or a
Type=simple loop `while sleep 2; do run; done`) so the 25-record ring never overflows.

---

## Evidence appendix (raw, trimmed)

```
# activity record for an alias request (§3)
{"id":618,"model":"qwen3.5-4b","req_path":"/v1/chat/completions",
 "resp_content_type":"application/json; charset=utf-8","resp_status_code":200,
 "tokens":{"input_tokens":14,"output_tokens":8,"prompt_per_second":103.8,
           "tokens_per_second":58.5,...},"duration_ms":2598,...}

# ring cap (§4)
total_requests before 623, .data length 25, ids [599,623]
total_requests after  628, .data length 25, ids [604,628]

# capture redaction (§5)
/api/captures/618 .req_headers.Authorization == "[REDACTED]"

# non-stream has no activity event, but the record exists (§2)
max id before 630; "activity" events seen: (none); newest record id 631 exists

# streaming emits activity={id only} (§2)
data:{"type":"activity","data":"{\"id\":621}"}
data:{"type":"inflight","data":"{\"operation\":\"remove\",\"id\":\"621\"}"}
```
