---
type: Design
description: Package layout, HTTP contract, lease and drain mechanics, journal compatibility, Nix packaging and the migration order for the Go rewrite of the Strata runtime.
task: definition.md
authored_by: agent
timestamp: 2026-11-20T08:40:00+01:00
---

# Design: one Go binary for the inference runtime

> Renamed while it was still unwired: the package is `packages/kdn-inference-helpers/` and the
> binary is `kdn-inference-helpers`. Strata is the first engine adapter, not the subject.

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

## Extension points, not hardcoded use cases

The runtime is built as a small core plus three explicit extension points. The rule is: a _new use
case_ is configuration or a new adapter, never an edit to the core.

| extension point                         | what it decides                                                                                                                                                | how it is supplied                                                                       |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **engine adapter** (`engine.Adapter`)   | which profiles exist, how a profile is materialised into a command, how a leftover engine is stopped, the readiness path                                       | one Go file per engine (`internal/engine/strata`), selected with `--engine`              |
| **deployment config** (`config.Config`) | data dir, ports, the model-name → profile aliases (`qfn` → `auto`), which model ids must survive a switch, the cache-drop command, the engine log path         | a JSON file passed as `--config`, with complete defaults for brys so nothing is required |
| **hooks**                               | the privileged cache drop is a command list in the config; an engine that does not need it sets it empty and the switch simply journals nothing for that phase | `config.Config.CacheDropCommand`                                                         |

What stays in the core on purpose: the lease registry, the drain, the proxy, the journal and the
HTTP contract. Those are the parts that are expensive to get wrong, and none of them needs to know
which engine is running.

Two consequences worth stating, because they are the difference between an extension point and a
configuration spiral:

- The **profile table is the adapter's**, overridable per profile from the config (reserve, resident
  K/V). Adding a profile for a new card is a config entry; adding a _new kind_ of profile is an
  adapter change.
- **Companion handling is a config list of ids that survive a switch.** Everything else that is
  loaded gets unloaded before the engine stops; that is what frees the companion's VRAM, and it works
  for any companion model, not just omni.

## Package layout

```
packages/kdn-inference-helpers/
├── go.mod                            # module, Go version, no dependencies
├── cmd/kdn-inference-helpers/main.go # subcommand dispatch, no logic beyond wiring
└── internal/
    ├── config/                       # deployment data: ports, aliases, companions, hooks
    │   ├── config.go
    │   └── config_test.go
    ├── control/                      # the HTTP API: status, select, stats, events, lease, release, unload
    │   ├── manager.go
    │   ├── leases.go                 # registry + drain condition
    │   └── leases_test.go
    ├── engine/                       # the Adapter interface and the supervisor
    │   ├── engine.go
    │   ├── supervise.go
    │   ├── supervise_test.go
    │   └── strata/                   # the first adapter: profiles, config patching, launch --stop
    │       ├── strata.go
    │       └── strata_test.go
    ├── proxy/                        # ReverseProxy, lease middleware, health bypass
    │   ├── proxy.go
    │   └── proxy_test.go
    ├── journal/                      # append-only JSONL, /stats aggregation
    │   ├── journal.go
    │   └── journal_test.go
    └── ctl/                          # human CLI against the control API
        └── ctl.go
```

Reuse is the point: `engine.profile` is used by `manager`, `serve` and `select`; `journal` is used
by `manager` and by `ctl stats`; `proxy` is used by `manager`'s self-check and by `select`.

## Behavioural contract (must not change)

Every item here is why the migration is safe:

| item             | value                                                                                                                                                                                                                                                                                                                                                         |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ports            | control `:8181`, engine `:8080`, llama-swap `:39700`, per-entry ports from `${PORT}`                                                                                                                                                                                                                                                                          |
| files            | `manager-state.json`, `events.jsonl`, profile configs under `<data>/strata/profiles/`                                                                                                                                                                                                                                                                         |
| env              | `HOME`, `XDG_DATA_HOME`, `STRATA_DATA_HOME`, `LD_PRELOAD` (the ROCm shim)                                                                                                                                                                                                                                                                                     |
| endpoints        | `/select` (`profile`, `dry_run`; `auto`/`qfn`/`qfn-max`/`qfn-fast-colo`/`none`), `/status` (`profile`, `last_switch`, `last_switch_seconds_ago`, `loaded_companions`, `in_flight`, `draining`), `/stats` (`by_event`, `by_transition` with n/median/p90/max), `/events?limit=N`, `/lease` → `{lease}` or `{wait}`, `/release` `{lease}`, `/unload` `{model?}` |
| journal events   | `switch`, `engine_load`, `engine_stop`, `cache_drop`, `drain`, `drain_timeout`, `request`, `companion_up`, `companion_down`                                                                                                                                                                                                                                   |
| privilege        | exactly one sudoers command: `systemctl start strata-drop-cache.service`                                                                                                                                                                                                                                                                                      |
| process contract | an entry command listens on `${PORT}` and stays in the foreground                                                                                                                                                                                                                                                                                             |

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

**The listener is dual-stack.** llama-swap resolves `localhost` to `::1` first, so the entry must
accept IPv6; Go's `net.Listen("tcp", ":N")` binds both families on Linux, but a `127.0.0.1:N` bind
does not, and llama-swap would kill the entry after a failed health check.

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
- **The wait contract**: retry `/lease` every 500 ms for up to 900 s, then answer `503` with a JSON
  body. An unreachable manager is _not_ a reason to fail: keep waiting, because a manager restart
  is shorter than a failed request.
- **Signal handling**: on `SIGTERM` the proxy releases its outstanding leases before exiting, so a
  switch does not inherit a phantom request. A `SIGKILL` cannot do that, hence the lease age limit.

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

Three rules keep the channel honest, each of which a review round caught:

- **A fresh channel per drain.** A closed `drained` channel stays closed; reusing it would make the
  next `BeginDrain` return instantly and cut a request that had just started.
- **One mutex for check-and-grant.** `Acquire` (refuse while draining, else insert a lease) and
  `BeginDrain` (set the flag, read the set) must not interleave, or a request slips past the flag
  and reaches an engine that is being stopped.
- **A lease has an age limit.** A proxy killed with `SIGKILL` cannot release, and a stale lease
  would burn the full 300 s ceiling on every later switch. Leases older than 30 minutes are ignored
  by the drain (a 1M-token prefill is ~10 minutes, so a real request is never cut) and journaled as
  `stale_lease`.

## The manager

- `http.Server` on `127.0.0.1:8181`, one handler per endpoint, no global lock for reads; the switch
  serialises on its own mutex so `/status`, `/stats` and `/lease` keep answering during it (today
  they do, and an agent reads `/status` while a switch runs).
- **Startup restore is part of the manager, not an afterthought.** The state file is read at start;
  if it names a profile and the engine does not answer, the manager starts that profile and journals
  `switch` with `cause: "restore"` (as the Python version does). A corrupt or absent state file
  means no restore, not a crash.
- Engine child: `exec.CommandContext` with `Setpgid` and a group kill, readiness by polling
  `GET :8080/v1/models` with a context deadline, and the child's stdout/stderr **captured to
  `<data>/strata/engine.log`** — today they go to `/dev/null`, which is why a failed load has no
  explanation.
- Companion watcher: a ticker instead of `time.Sleep` in a loop; same 3 s interval, same
  `observed` flag on the journal entries.
- Cache drop: `exec.CommandContext("sudo", "-n", "systemctl", "start", "strata-drop-cache.service")`,
  timed into the journal; failure is logged, never fatal.
- **Stopping also runs `strata launch --stop`**, as the Python version does: a previous manager
  instance (or the manual `strata-frontier` fallback) can leave an engine that this manager did not
  spawn, and `serve` has no PID file of its own.

## The `/select` surface, exactly

Accepted values are `max`, `omni-max`, `omni-fast`, `auto`, `none`, plus the aliases `qfn` → `auto`,
`qfn-max` → `max`, `qfn-fast-colo` → `omni-fast`. Anything else is `400 {"error": "unknown profile ..."}`.
`auto` answers `{"changed": false, "profile": <current>, "note": "auto: kept the current profile"}`.
A failed start answers `{"error": <detail>, "profile": null}` and journals the switch with `ok: false`.

## Journal and `/stats`

Same file, same one-line-per-event JSON. The reader tolerates unknown event names and missing
`seconds` (companion unload entries legitimately have `loaded_for` instead), which is what makes the
file append-compatible across the migration. `/stats` sorts the values and indexes
percentiles with **round-half-to-even**, because Python's `round()` is banker's rounding and the
aggregate must not drift by one index (n=6 median is index 2, not 3). The JSON shape stays identical
so `ctl stats` and the probes keep working.

## Packaging

```nix
# packages/kdn-inference-helpers/default.nix
{ lib, buildGoModule, ... }:
buildGoModule {
  pname = "kdn-inference-helpers";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;          # standard library only
  meta.mainProgram = "strata-helpers";
}
```

The unit changes are one line each: `ExecStart` points at
`${pkgs.kdn.inference-helpers}/bin/kdn-inference-helpers manager --config <path>` (and `select`,
`serve` for the entry commands; `--engine strata` is the default). A temporary option `kdn.strata.runtime = "python" | "go"` **switches all four pieces
together** — a half-switched pair is not a supported configuration, even though the HTTP contract
would allow it. The option is deleted together with the Python files.

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
   `qfn-max` ↔ `qfn-fast-colo` switch under a Pi session.
4. Switch `ctl` (the `brys-frontier.sh` wrapper calls the Go CLI) and `serve`.
5. After a week of clean operation, delete the Python files and the `runtime` option, and record the
   journal's first Go-week numbers next to the Python ones.

## Open questions

- Does `ReverseProxy` preserve the engine's `Content-Type: text/event-stream` and its exact chunk
  boundaries? It does when `FlushInterval = -1`, but the SSE test above must assert chunk-level
  timing, not just content.
- ~~Should `select` bypass `/lease` because both live in one binary?~~ **No.** `select` runs as a
  process of its own, spawned by llama-swap, so the lease registry lives in the manager and the
  round trip is the contract. The one-binary packaging is about code sharing, never about sharing
  memory across processes.
- Does the engine need `Connection: close` forcing once `ReverseProxy` handles keep-alive properly?
  Likely not; the test decides.
