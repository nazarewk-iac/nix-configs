---
type: Task
description: Replace the four hand-written Strata runtime pieces (manager, proxy, select, serve) with one stdlib-only Go binary at packages/kdn-inference-helpers/, keeping the HTTP API, the event journal and llama-swap's process contract unchanged.
status: open
authored_by: agent
timestamp: 2026-11-20T08:30:00+01:00
---

# Move the Strata runtime into one Go binary

## Context

The frontier on brys is served by four small programs that grew around one idea — one engine, many
names, no interrupted requests:

| piece               | language | size       | job                                                                                                                                                           |
| ------------------- | -------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `strata-manager.py` | Python   | ~700 lines | owns the engine child; `/select`, `/status`, `/stats`, `/events`, `/lease`, `/release`, `/unload`; drains, drops the page cache, journals, watches companions |
| `strata-proxy.py`   | Python   | ~230 lines | per-entry listener: lease per request, wait while draining, relay to `:8080`, local `/health` while draining                                                  |
| `strata-select.sh`  | bash     | ~40 lines  | the llama-swap entry command: ask the manager, then exec the proxy                                                                                            |
| `strata-serve.sh`   | bash     | ~90 lines  | materialise a profile config, exec `strata serve` (the unit fallback)                                                                                         |

They work — the drain is proven at three levels and the four-name surface is live — but the runtime
carries three avoidable weaknesses:

1. **The HTTP proxy is hand-rolled.** It parses the request line, `Content-Length` and chunked
   bodies itself, closes after one request per connection, and has no answer for
   `Expect: 100-continue`, trailers or keep-alive. The workload only exercises the subset
   llama-swap sends, so this is a correctness risk with no test coverage, not a bug today.
2. **Everything is untested.** The only verification is a set of Python probes run by hand against
   the live host. A drain regression would be found by a user, not by CI.
3. **Four processes, four languages, four failure surfaces.** The lease protocol between proxy and
   manager exists only because they are separate programs; the shell scripts duplicate engine
   knowledge (profile → config → command) that the Python files also hold.

The two production bugs so far were ours, not the language's — a 30 s connect timeout reused as a
read timeout, and unloading the child whose request asked for a switch. Both are the kind of thing a
typed, tested implementation prevents structurally.

## Goal

One repository package, `packages/kdn-inference-helpers/`, producing **one static binary** with
subcommands, using only the Go standard library, that replaces the four pieces while keeping every
observable contract: the HTTP API and its JSON, the event journal, the file paths, the environment
variables, the sudoers line, and llama-swap's expectation that an entry command listens on `${PORT}`.

## Scope

- `strata-helpers manager` — the current `strata-manager.py`.
- `strata-helpers proxy --port N` — the current `strata-proxy.py`, built on `httputil.ReverseProxy`.
- `strata-helpers select <profile> --port N` — selects and then serves the proxy in the same process.
- `strata-helpers serve <profile> --port N` — the current `strata-serve.sh`.
- `strata-helpers ctl up|down|status|stats` — the human interface now in `hack/brys-frontier.sh`.
- Nix packaging (`buildGoModule`) and the unit `ExecStart` changes.
- Tests: unit, golden-HTTP, a fake streaming engine, and the existing drain probes as acceptance.

## Non-goals

- No change to the profile model, the four names, the reserve sizes or the engine itself.
- No new API surface; the JSON shapes stay byte-compatible for existing clients.
- No replacement for llama-swap: the per-entry `${PORT}` contract stays.
- No port of the benchmark probes (`probe-power-*`, `probe-drain-*`); they are test harnesses and
  stay Python.

## Acceptance criteria

1. `go test ./...` passes with `-race`, including a drain test that asserts a switch waits for an
   in-flight request and that a request arriving mid-switch is served afterwards.
2. The proxy passes a conformance table it cannot pass today: chunked request body, keep-alive
   reuse, `Expect: 100-continue`, SSE with pauses, trailers, and a client that disconnects mid-stream.
3. `/status`, `/stats`, `/events`, `/select` (with `dry_run` and `auto`), `/lease`, `/release` and
   `/unload` return the same JSON keys and types as the Python implementation, checked by a golden
   file captured from the live host.
4. The journal file is append-compatible: old lines stay readable by the new `/stats` (unknown event
   names are aggregated, not rejected).
5. `hack/probe-drain-inflight.py`, `hack/probe-drain-gateway.py` and the Pi-under-switch run pass
   against the Go runtime unchanged.
6. The binary replaces all four scripts on brys with one commit per piece, each revertible on its
   own, and the Python files are deleted only after a week of clean operation.

## Risks

- **Health-check timing.** llama-swap kills an entry whose `/health` fails; the local-200-during-drain
  behaviour is load-bearing. It must be reproduced exactly, including the moment draining clears.
- **Journal compatibility.** `/stats` aggregates whatever is in the file; a stricter parser would
  silently drop yesterday's data.
- **Process identity.** `strata-select` currently `exec`s a second program; in Go it must be one
  process, so signal handling and the lease release on SIGTERM need explicit care.
- **Migration window.** Two implementations of the same API in the tree invites drift. Keep the
  Python only as a rollback for one release, behind an explicit Nix option, and delete it on
  schedule.

## Follow-up work

The design is in [design.md](design.md): package layout, the HTTP proxy contract, the lease and
drain mechanics in Go, the journal, the Nix packaging and the migration order.
