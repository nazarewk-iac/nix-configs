---
type: Research
description: Cost and correctness of persisting llama-swap statistics — the measured event stream, what Prometheus can and cannot see, the series and disk arithmetic, and the impermanence rules that decide whether a sample survives a reboot.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T00:00:00+01:00
---

# Research: cost of persisting the LLM stats

Measured on `brys` on 2026-10-27, plus the repository's own disk and monitoring
code.

## 1. What can be scraped, and what cannot

`GET /metrics` on `:39700` returns, verified by reading the body:

```
llamaswap_cpu_util_percent{core="0..31"}
llamaswap_memory_total_bytes / _used_bytes / _free_bytes
llamaswap_swap_total_bytes / _used_bytes
llamaswap_load_average{interval="1m|5m|15m"}
llamaswap_network_bytes_total{interface,direction}
```

No model, token or throughput series. So a plain Prometheus scrape of
llama-swap's own endpoint persists **system** stats only — useful for "the box was
busy", useless for "which alias was slow".

The model data lives in JSON:

| Endpoint                | Content                 | Shape                     |
| ----------------------- | ----------------------- | ------------------------- |
| `/api/metrics/activity` | one record per request  | JSON array, ring-buffered |
| `/api/metrics/stats`    | totals + histograms     | JSON object               |
| `/api/performance`      | GPU stats               | JSON array                |
| `/api/captures/<id>`    | request/response bodies | JSON, auth redacted       |
| `/api/events`           | live typed events       | SSE                       |

An exporter is therefore **required** for any Prometheus route. There is no
configuration that makes llama-swap emit model metrics in Prometheus format.

## 2. The event stream, measured

Held `GET /api/events` open for 25 s while one request ran. Event types by count:

| Type                         | Count  | Payload                                                                                   |
| ---------------------------- | ------ | ----------------------------------------------------------------------------------------- |
| `logData`                    | 2866   | a log line                                                                                |
| `modelStatus`                | 5      | full model list: `id`, `name`, `state` (`stopped`/`loading`/`ready`), `aliases`, `peerID` |
| `inflight`                   | 4      | `{"operation":"upsert"                                                                    | "snapshot","request":{id,model,req_path,method,headers}}` |
| `activity`                   | 1      | the finished request record                                                               |
| `uiConfig`, `profileChanged` | 1 each | UI state                                                                                  |

Two practical notes:

1. The stream **replays its buffered history** on connect (8634 lines arrived
   before the live event of interest), so a collector must skip what it already
   has, or pass `?no-history` if that flag applies here (documented for
   `/logs/stream`).
2. `modelStatus` is the load/unload event a sidecar needs. `inflight` gives
   active-request awareness. Both are event-driven, so no polling is needed for
   control.

## 3. Series arithmetic, for the Prometheus route

Assume the collector exports, per model: requests total, input tokens total,
output tokens total, prompt tok/s gauge, gen tok/s gauge, duration gauge, plus one
`up`-style series. About 7 per model.

- 40 models → ~280 series.
- A 15 s scrape → 280 / 15 ≈ 19 samples/s ≈ 1.6 M samples/day.
- At 1–2 bytes per compressed sample, that is **2–4 MB/day**, so roughly
  **60–120 MB per 30 days**. The aspect already caps growth with
  `--storage.tsdb.retention.size`.

Memory and CPU:

| Component                      | RSS                     | CPU                                 |
| ------------------------------ | ----------------------- | ----------------------------------- |
| Prometheus (this series count) | ~120–200 MB             | ~0.1 % idle, brief spike per scrape |
| Grafana                        | ~180–300 MB             | ~0.1 %                              |
| One shell/Go collector         | ~10 MB, or 0 on a timer | negligible                          |

On a 128 GB box that is nothing in absolute terms. The real objection is not
memory, it is that `llms-frontier` exists to give the models the whole machine —
so a monitoring stack belongs on the entry that already hosts a desktop, or on
another host scraping over the network. The owner has accepted it in both entries.

## 4. The impermanence rules, read from the code

`modules/den/aspects/disks.nix`:

- root is tmpfs; only `kdn.disks.persist` paths are bind-mounted back by
  `preservation` (`:713-735`);
- the persist buckets include a **`disposable`** set (`:678`), which is
  deliberately not kept across boots;
- the existing entries show the shape: `kdn.disks.persist."sys/state".directories
= [ "/var/lib/systemd/coredump" ]`, and the `{ directory = "…"; mode = "…"; }`
  form for paths that need a mode.

So the deliverable is one entry per data directory in a **non-disposable** bucket,
e.g.:

```nix
kdn.disks.persist."sys/state".directories = [
  { directory = "/var/lib/prometheus"; mode = "0700"; }
  { directory = "/var/lib/grafana"; mode = "0700"; }
];
```

Unlisted, `/var/lib/prometheus` is a tmpfs directory and every sample is lost at
reboot. Listed under `disposable`, it looks persisted and is still lost. Both are
silent failures, which is why the acceptance test in the task is a reboot
comparison.

Version caveat: Prometheus refuses to open a TSDB written by a newer version, so a
flake rollback after a Prometheus bump is a one-way door unless the data directory
is version-suffixed.

## 5. Why log parsing is the worst of the four routes

- It needs `swap.debug` permanently, which puts every child's `--verbose` output
  in the journal.
- The format is llama.cpp's, so a llama.cpp update can break the parser — and this
  repository already carries custom llama-cpp builds
  (`packages/llama-cpp/`), so the format is not even the only one in play.
- The same numbers are already structured in a JSON record. A parser re-derives
  them from text, and loses the model id precision the JSON gives with each
  child's `--alias`.

It is a legitimate fallback only if a future llama-swap removes the JSON API.

## 6. Cost summary, to answer "how much"

| Route                              | New processes | New code   | RAM               | Disk                |
| ---------------------------------- | ------------- | ---------- | ----------------- | ------------------- |
| JSONL collector, event-driven      | 1             | ~100 lines | ~10 MB            | ~1 MB/1000 requests |
| Collector + node_exporter textfile | 2             | ~120 lines | ~30 MB            | same                |
| Prometheus + Grafana + exporter    | 3–4           | ~150 lines | ~350–500 MB total | 60–120 MB / 30 days |
| Log parser                         | 1             | ~200 lines | ~20 MB            | + journal growth    |

Recommended order: JSONL collector first (it satisfies both tasks and is the
cheapest), Prometheus second if dashboards are actually wanted, log parsing never
unless forced.

## 7. Not verified

- Whether `?no-history` applies to `/api/events` (documented only for
  `/logs/stream`).
- Whether the `activity` event arrives before or after the response finishes — it
  arrived once, after, in the 25 s window.
- The exact default `stateDir` Prometheus uses under the nixpkgs module on this
  pin (assumed `/var/lib/prometheus`).
