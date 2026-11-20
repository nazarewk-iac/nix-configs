---
type: Design
description: Package layout, HTTP contract, lease and drain mechanics, journal compatibility, Nix packaging and the migration order for the Go rewrite of the Strata runtime.
task: definition.md
authored_by: agent
timestamp: 2026-11-20T08:40:00+01:00
---

# Design: one Go binary for the Strata runtime

## Why Go, and why not asyncio

The runtime is I/O-bound and tiny: four to forty concurrent streams of a few hundred kilobytes per
second, against an engine that spends seconds per prefill. Throughput is not the argument for any
language here, and a rewrite for speed would be a mistake.

The argument is **robustness from the standard library and testability from the type system**:

- `net/http` plus `httputil.ReverseProxy` already implement HTTP/1.1 correctly — chunked bodies,
  keep-alive, `100-continue`, trailers, hop-by-hop header stripping, SSE flushing with
  `FlushInterval = -1`. A hand-written proxy re-implements a subset of that badly.
- The same code can be unit-tested with `httptest` and run under `-race`, which is what the drain
  logic needs (a shared lease registry touched by every request thread and by the switch).
- One static binary, no interpreter, no `LD_PRELOAD` juggling for the runtime, no shell wrappers.

asyncio would buy none of that: the fragile parser would remain, only harder to read, and `aiohttp`
would be a dependency doing what `net/http` does in the standard library.

## What is replaced, and what stays

| now                                  | after                                                                                  |
| ------------------------------------ | -------------------------------------------------------------------------------------- |
| `strata-manager.py`                  | `strata-helpers manager`                                                               |
| `strata-proxy.py`                    | `strata-helpers proxy --port N`                                                        |
| `strata-select.sh`                   | `strata-helpers select <profile> --port N` (selects, then serves the proxy in-process) |
| `strata-serve.sh`                    | `strata-helpers serve <profile> --port N`                                              |
| `hack/brys-frontier.sh`              | `strata-helpers ctl up                                                                 | down | status | stats` (the script stays as a thin wrapper until the CLI is proven) |
| `hosts-den/brys/strata-profiles.nix` | unchanged except `ExecStart` paths                                                     |
| `hack/probe-*.py`                    | unchanged; they are the acceptance suite                                               |

## Package layout

```
packages/strata-helpers/
├── go.mod                       # module, Go version, no dependencies
├── cmd/strata-helpers/main.go   # subcommand dispatch, no logic beyond wiring
└── internal/
    ├── control/                 # the HTTP API: status, select, stats, events, lease, release, unload
    │   ├── handlers.go
    │   ├── leases.go            # registry + drain condition
    │   └── leases_test.go
    ├── engine/                  # profile → config, child supervision, readiness, stop
    │   ├── profile.go
    │   ├── supervise.go
    │   └── supervise_test.go    # fake engine binary
    ├── proxy/                   # ReverseProxy, lease middleware, health bypass
    │   ├── proxy.go
    │   └── proxy_test.go
    ├── journal/                 # append-only JSONL, /stats aggregation
    │   ├── journal.go
    │   └── journal_test.go
    └── ctl/                     # human CLI against the control API
        └── ctl.go
```

Reuse is the point: `engine.profile` is used by `manager`, `serve` and `select`; `journal` is used
by `manager` and by `ctl stats`; `proxy` is used by `manager`'s self-check and by `select`.

## Behavioural contract (must not change)

Every item here is why the migration is safe:

| item             | value                                                                                                                                                                                                                                                                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ports            | control `:8181`, engine `:8080`, llama-swap `:39700`, per-entry ports from `${PORT}`                                                                                                                                                                                                                                                                     |
| files            | `manager-state.json`, `events.jsonl`, profile configs under `<data>/strata/profiles/`                                                                                                                                                                                                                                                                    |
| env              | `HOME`, `XDG_DATA_HOME`, `STRATA_DATA_HOME`, `LD_PRELOAD` (the ROCm shim)                                                                                                                                                                                                                                                                                |
| endpoints        | `/select` (`profile`, `dry_run`; `auto`/`qfn`/`qfn-max`/`qfn-colo`/`none`), `/status` (`profile`, `last_switch`, `last_switch_seconds_ago`, `loaded_companions`, `in_flight`, `draining`), `/stats` (`by_event`, `by_transition` with n/median/p90/max), `/events?limit=N`, `/lease` → `{lease}` or `{wait}`, `/release` `{lease}`, `/unload` `{model?}` |
| journal events   | `switch`, `engine_load`, `engine_stop`, `cache_drop`, `drain`, `drain_timeout`, `request`, `companion_up`, `companion_down`                                                                                                                                                                                                                              |
| privilege        | exactly one sudoers command: `systemctl start strata-drop-cache.service`                                                                                                                                                                                                                                                                                 |
| process contract | an entry command listens on `${PORT}` and stays in the foreground                                                                                                                                                                                                                                                                                        |

## The proxy, in Go

```go
type LeaseHook interface {
    Acquire(ctx context.Context) (id int64, wait bool) // wait => retry
    Release(id int64)
}

handler := &proxy.Handler{
    Target: targetURL,                 // http://127.0.0.1:8080
    Leases: control.Manager,           // the same registry the switch drains
    HealthDuringDrain: true,           // llama-swap must not see the entry die
}
```

Rules that carry over from the Python implementation, now enforced by the library:

- `FlushInterval = -1` so every SSE chunk is flushed immediately.
- `Transport` with `DisableCompression = true` (no `Accept-Encoding` injected), `ForceAttemptHTTP2 =
false` (the engine is HTTP/1.1), `MaxIdleConnsPerHost` small (one engine).
- Hop-by-hop headers dropped by `ReverseProxy`; `X-Forwarded-*` not added (nothing consumes it).
- `ModifyResponse` truncates a `101 Switching Protocols` upgrade with a clear error: the engine has
  none, and silently hanging is worse.
- `ErrorHandler` returns `502` with a JSON body instead of a bare EOF — the failure mode we hit
  (a client saw an unexplained EOF because the socket closed).
- **Health bypass**: the handler answers `GET /health` locally with `200 {"status":"switching"}`
  when the manager reports `draining`, and proxies it otherwise. This is the one intentional lie
  and it is what keeps llama-swap from killing the process that holds the delayed requests.

## Lease and drain, in Go

The Python version polls a map every 250 ms. Go does it without polling:

```go
type Leases struct {
    mu      sync.Mutex
    next    int64
    open    map[int64]time.Time
    drained chan struct{}   // closed when the set becomes empty
    draining bool
}

func (l *Leases) Acquire() (int64, bool)   // false => the switch is in progress, wait and retry
func (l *Leases) Release(id int64)         // closes `drained` when the last lease goes
func (l *Leases) BeginDrain(ctx context.Context) error // sets draining, waits for `drained` or ctx
func (l *Leases) EndDrain()
```

`select` becomes: `BeginDrain(ctx)` → unload companions → stop the engine → drop caches → start the
engine → `EndDrain()` → journal the switch. The 300 s ceiling is a `context.WithTimeout`, and hitting
it journals `drain_timeout` and proceeds, exactly as now.

## The manager

- `http.Server` on `127.0.0.1:8181`, one handler per endpoint, no global lock for reads; the switch
  serialises on its own mutex so `/status`, `/stats` and `/lease` keep answering during it (today
  they do, and an agent reads `/status` while a switch runs).
- Engine child: `exec.CommandContext` with `Setpgid` and a group kill, readiness by polling
  `GET :8080/v1/models` with a context deadline, and the child's stdout/stderr **captured to
  `<data>/strata/engine.log`** — today they go to `/dev/null`, which is why a failed load has no
  explanation.
- Companion watcher: a ticker instead of `time.Sleep` in a loop; same 3 s interval, same
  `observed` flag on the journal entries.
- Cache drop: `exec.CommandContext("sudo", "-n", "systemctl", "start", "strata-drop-cache.service")`,
  timed into the journal; failure is logged, never fatal.

## Journal and `/stats`

Same file, same one-line-per-event JSON. The reader tolerates unknown event names and missing
`seconds` (companion unload entries legitimately have `loaded_for` instead), which is what makes the
file append-compatible across the migration. `/stats` sorts the values and indexes percentiles;
the JSON shape stays identical so `ctl stats` and the probes keep working.

## Packaging

```nix
# packages/strata-helpers/default.nix
{ lib, buildGoModule, ... }:
buildGoModule {
  pname = "strata-helpers";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;          # standard library only
  meta.mainProgram = "strata-helpers";
}
```

The unit changes are one line each: `ExecStart` points at
`${pkgs.kdn.strata-helpers}/bin/strata-helpers manager` (and `select`, `serve` for the entry
commands). A temporary option `kdn.strata.runtime = "python" | "go"` keeps the rollback path for one
release; it is deleted together with the Python files.

## Testing

1. **Unit** — leases (concurrent acquire/release under `-race`, drain waits, timeout proceeds),
   journal (append, aggregate, unknown events), profile materialisation (arg patching, reserve,
   `kv-resident`).
2. **Golden HTTP** — a fake engine behind `httptest` that streams SSE in 10 chunks with 50 ms
   pauses; assert the client receives 10 chunks _as they happen_ (not buffered), that a chunked
   request body arrives intact, that keep-alive reuse works for two sequential requests on one
   connection, and that `Expect: 100-continue` is honoured.
3. **Drain** — start a slow stream, call `select`, assert the switch returns only after the stream
   ends and that a request issued during the switch is served afterwards.
4. **Compatibility** — a golden JSON file captured from the Python `/status`, `/stats` and
   `/select` responses; the Go handlers must match key-for-key.
5. **Acceptance** — the existing `hack/probe-drain-inflight.py`, `hack/probe-drain-gateway.py`, and
   the Pi-under-switch run, unchanged.

## Migration order

1. Land the package and its tests with nothing wired; CI runs `go test -race`.
2. Switch `strata-proxy` first: `select` becomes the Go binary, the manager stays Python. The
   contract between them is `/lease`/`/release`, unchanged. Run the probes.
3. Switch `strata-manager`. Same endpoints, same files; run the probes again, plus a real
   `qfn-max` ↔ `qfn-colo` switch under a Pi session.
4. Switch `ctl` (the `brys-frontier.sh` wrapper calls the Go CLI) and `serve`.
5. After a week of clean operation, delete the Python files and the `runtime` option, and record the
   journal's first Go-week numbers next to the Python ones.

## Open questions

- Does `ReverseProxy` preserve the engine's `Content-Type: text/event-stream` and its exact chunk
  boundaries? It does when `FlushInterval = -1`, but the SSE test above must assert chunk-level
  timing, not just content.
- Should `select` keep the lease in the same process as the proxy (yes) and thus drop the
  `/lease` round-trip for that entry path (it can bypass HTTP and call the registry directly when
  both live in one binary)?
- Does the engine need `Connection: close` forcing once `ReverseProxy` handles keep-alive properly?
  Likely not; the test decides.
