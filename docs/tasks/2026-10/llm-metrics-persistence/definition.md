---
type: Task
description: Persist llama-swap's per-model performance safely on brys: decide between a Prometheus scrape path, a log parser, and an event-driven JSONL collector, and put the data on the impermanent disk layout without losing it at boot.
status: in-progress
authored_by: agent
timestamp: 2026-10-27T23:55:00+01:00
---

# Persisting the LLM performance data

> **State 2026-10-28:** implemented in `hosts/brys/llm.nix` and packaged as
> `packages/llm/llm-stats`. Not yet deployed, and not yet proven over a reboot.
>
> | Piece | State |
> |---|---|
> | `llm-stats` collector (route A + textfile) | built, shellcheck clean, `collect --help` verified |
> | systemd unit `llm-stats` | wired, `ExecStart` verified by eval, hardened (no new privileges, strict `ProtectSystem`, one writable dir) |
> | `/var/lib/llm-stats` persistence | wired (`sys/state`, mode 0755 so node_exporter can read the textfile) |
> | Small Prometheus (`:9090`, 30 d / 2 GB) | wired, two scrape jobs verified by eval |
> | `/var/lib/prometheus2` persistence | wired (`sys/state`, owner `prometheus`) |
> | Both boot entries | verified: the `llms-frontier` specialisation carries the unit, the scrape configs and both persist paths |
> | Reboot proof | **pending** |
> | Per-alias attribution | implemented (aliases resolved from `/v1/models`), **unverified live** |
> | Dashboard | not built, deliberately: the aspect's Grafana stack was rejected as too heavy |

# Persisting the LLM performance data

## Context

llama-swap has the data but no memory. Verified on 2026-10-27:

- `/api/metrics/activity` — one record per request: model, input/output tokens,
  `prompt_per_second`, `tokens_per_second`, `duration_ms`, status.
- `/api/metrics/stats` — totals plus p50/p95/p99 histograms of both rates.
- `/api/captures/<id>` — the request and response, `Authorization` redacted.
- `/api/performance` — per-GPU temperature, utilisation, VRAM, fan, power.
- `/api/events` — an SSE stream carrying `activity`, `modelStatus`, `inflight`
  and `logData` events.
- `/metrics` — Prometheus, but **system-level only** (CPU per core, memory, swap,
  load, network). It carries no model data.

Everything above except `/metrics` is in memory and bounded (`captureBuffer`: 10
normally, 50 with `swap.debug`). A restart, or a burst bigger than the ring,
loses it.

This is the missing half of both
[../llama-swap-concurrency/definition.md](../llama-swap-concurrency/definition.md)
(the sidecar's collect job) and
[../gaz-den-workstation/003-fleet-evaluation/definition.md](../gaz-den-workstation/003-fleet-evaluation/definition.md)
(the per-call numbers).

## The three routes, priced

| Route | What it needs | Cost | Verdict |
|---|---|---|---|
| **A. Event-driven collector → JSONL** | a small service that subscribes to `/api/events`, writes one line per `activity` event, plus a poll of `/api/performance` | ~100 lines, RSS ~10 MB, no new port | cheapest, exact, no loss |
| **B. Same collector → Prometheus textfile** | A plus `node_exporter` with `--collector.textfile` | A plus one exporter and a `.prom` file | dashboards without a scrape endpoint |
| **C. Prometheus server + scrape** | `monitoring-prometheus-stack` plus an exporter that serves Prometheus format from the JSON API | the aspect already exists; a scrape endpoint (~150 lines) and a server | worth it only if Grafana is wanted |
| **D. Parse child logs** | `swap.debug` permanently on, a parser tied to llama.cpp's log format | highest fragility, most CPU and journal growth | reject: the structured data already exists |

The repository already has the stack: `modules/den/aspects/monitoring.nix` wires
Prometheus (with `retentionTime` and `retentionSize`), Grafana, an optional
pushgateway, and a Caddy vhost for Grafana. So "spin up Prometheus" is a
one-line inclusion plus an exporter — not a build.

## The storage rule, which is the actual risk

`brys` runs the impermanence layout: **tmpfs root**, a ZFS pool, and
`preservation` bind-mounting back only the paths listed under `kdn.disks.persist`
(`modules/den/aspects/disks.nix:573-700`). Its buckets include a
**`disposable`** set that is deliberately rolled back at boot.

Therefore:

1. `/var/lib/prometheus` **must** be a `kdn.disks.persist."sys/…".directories`
   entry. Left unlisted, it lives in tmpfs and every sample dies at reboot —
   which is the exact opposite of what this task is for.
2. Grafana's `/var/lib/grafana` and its `secret-key` file must be persisted too,
   or every boot invalidates sessions and the admin password hash.
3. **Never** put either path in the `disposable` bucket. It looks persisted and is
   not.
4. The path must be owned by the right user with the right mode; use the
   `{ directory = "…"; mode = "…"; }` form the aspect already supports.
5. ZFS is fine for a TSDB (append-heavy, sync-cheap), but do not put it in a
   dataset with `sync = disabled` unless the sample loss on power cut is
   acceptable. Monitoring data is, so that is a legitimate choice, stated
   explicitly.
6. **Version compatibility:** Prometheus refuses to open a TSDB written by a newer
   version. Both boot entries (`llms-frontier` and the default profile) come from
   the same nixpkgs, so they match today — but a flake rollback after a
   Prometheus bump makes the on-disk TSDB unreadable. Either keep the data
   directory version-suffixed, or accept and document the one-way upgrade.

## Running in both boot entries

The owner wants Prometheus available in the default profile **and** in
`llms-frontier`. That is fine, because only one entry runs at a time and both
read the same persisted directory. The requirements:

- the aspect and the collector are included from a place both entries share
  (`hosts/brys/llm.nix` is that place — it is already shared by every
  specialisation, per its own header comment);
- the data directory is identical in both, so a reboot into the other entry keeps
  the history;
- the collector is idempotent on start and tolerates a replayed event history
  (`/api/events` replays its buffer on connect).

## Deliverables

1. A collector, packaged in `packages/` if it earns its place, in the style of the
   repo's other small tools. It writes JSONL (route A) and optionally a Prometheus
   textfile (route B).
2. The persistence entries, in the shared host file, with a test or an eval proof
   that `/var/lib/<service>` appears in the preservation list.
3. If Prometheus and Grafana are adopted: the aspect included, retention capped by
   size, and one dashboard that answers "which alias is slow, and when".
4. A short section in `docs/local-llms.md` that replaces guesswork with the exact
   commands.

## Acceptance

- A reboot keeps the collected history, proven by comparing counts before and
  after.
- The collector subscribes rather than polls, and a burst of 100 requests produces
  100 records with none missing.
- Per-alias attribution works. The activity record carries the **base model id**
  (`qwen3.5-4b`), and four aliases share it, so the collector resolves the alias
  through the `hosts/brys/llm-routers.nix` map or records the model id plus the
  routing table's version.
- A query over one day answers: requests per alias, median and p95 gen tok/s,
  and the slowest requests.
- If Prometheus is adopted, a flake rollback across a Prometheus version bump is
  documented as a known break with its recovery step.

## Risks

| Risk | Mitigation |
|---|---|
| Data lands in tmpfs and silently evaporates | assert the persist entry in an evaluation check; the task's acceptance includes a reboot test |
| Record lands in the `disposable` bucket | the acceptance test names the bucket |
| The collector drops events during a reconnect | resume by timestamp; the SSE payload carries one |
| JSONL grows without bound | rotate by day and keep the last N days, matching the Prometheus retention |
| A second consumer (Prometheus plus the collector) doubles the work | one collector, two outputs |
