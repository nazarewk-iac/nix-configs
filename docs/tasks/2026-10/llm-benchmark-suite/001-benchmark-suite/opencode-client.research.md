---
type: Research
description: Client-side opencode start timings on host oams (2026-10-19): cold and warm start, in /tmp and in the nix-configs repository, with the readiness signal, the cache controls, and the brys discovery-plugin status.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T19:52:00+02:00
---

# opencode client start timings on oams (2026-10-19)

This file records the client-side start time of the `opencode` CLI on host
`oams`. It is a client measurement, not a model benchmark. The server (`brys`)
is not part of the measurement; the runs only contact it for the model list and
for one trivial reply.

## Readiness signal

`opencode start` is the wall time from the launch of `opencode` to the moment it
can accept a prompt. This file uses a **headless** run and a **machine-readable**
signal, so the result is exact and reproducible:

```
opencode run --format json '<prompt>'
```

- **Start of the timer.** The line just before the shell starts `opencode`.
- **End of the timer.** The moment the first line of stdout appears. With
  `--format json` that first line is a `step_start` event. A `step_start` event
  means opencode finished loading, built the session, and sent the first request
  to the model. Therefore the process is ready and the timer stops.
- **Why this signal.** The TUI does not print a stable, parseable "loaded"
  marker. The `step_start` event is stable and it is the first byte opencode
  emits after it is ready. It also needs no terminal, so the run is headless and
  does not touch the user's panes.
- **Stop condition.** `timeout 90` wraps every run, so a hang cannot block the
  measurement.

Each run used the fixed prompt `reply with the single word: pong`. That prompt
is short, so the time to `step_start` is dominated by client start, not by model
thinking.

## Environment

| item | value |
|---|---|
| host | oams (this host) |
| `opencode --version` | 1.19.0 |
| binary | `/nix/store/0nl0...-opencode-1.19.0/bin/opencode` |
| CPU count | 16 |
| up (at first run) | 2 days 3 h 50 min |
| one-minute load during the pass | 2.3 to 6.0 (see the tables) |

## Cache control

The only per-run start cache that this measurement can control is the models.dev
catalog:

```
~/.cache/opencode/models.json     # catalog, 5,825,408 bytes when full
```

It is a cache, not user data. opencode writes it in full when it is absent, so
it is safe to move aside. This measurement does **not** delete user data.
`~/.local/share/opencode/*` (the session database, `auth.json`) and
`~/.local/state/opencode/*` (settings) were not touched.

| mode | action before each run |
|---|---|
| cold | move `models.json` aside (to `models.json.benchbak`) if present, so the run rebuilds it |
| warm | leave `models.json` in place |

The cold action runs **before every cold run**, not only before the first one.
Without this, run 1 rebuilds the cache and runs 2 and 3 are warm, which hides
the cold cost. This is the main reason the first cold attempt (median 3.497 s)
was discarded and the pass was redone.

The `models.json` cache was restored to its full state at the end. The temporary
`.benchbak` file was removed.

## Results

All values are seconds. `median` is the middle value of the three runs.

### 1. Cold start, working directory `/tmp/opencode`

Cold action applied before each run.

| run | elapsed s | one-minute load |
|---|---|---|
| 1 | 3.447 | 5.65 |
| 2 | 3.407 | 5.52 |
| 3 | 3.613 | 5.16 |

**Median: 3.447 s**

### 2. Warm start, working directory `/tmp/opencode`

Cache left in place.

| run | elapsed s | one-minute load |
|---|---|---|
| 1 | 3.955 | 5.57 |
| 2 | 3.469 | 4.72 |
| 3 | 3.179 | 4.42 |

**Median: 3.469 s**

### 3. Cold start, working directory `nix-configs`

Cold action applied before each run. This directory loads
`opencode.jsonc`, the `.opencode/plugins/*.ts` files, the `AGENTS.md` agent
rules, and MCP.

| run | elapsed s | one-minute load |
|---|---|---|
| 1 | 3.471 | 3.79 |
| 2 | 3.607 | 3.73 |
| 3 | 3.414 | 3.51 |

**Median: 3.471 s**

### 4. Warm start, working directory `nix-configs`

Cache left in place.

| run | elapsed s | one-minute load |
|---|---|---|
| 1 | 4.011 | 4.84 |
| 2 | 3.753 | 4.53 |
| 3 | 4.083 | 4.22 |

**Median: 4.011 s**

### Summary

| cell | median s |
|---|---|
| opencode cold start | 3.447 |
| opencode warm start | 3.469 |
| opencode cold start in nix-configs | 3.471 |
| opencode warm start in nix-configs | 4.011 |

## Model-discovery plugin (brys)

The working-directory runs load
`.opencode/plugins/kdn-models-discovery.ts`. That plugin runs a `config` hook
and fetches `https://brys.priv.nb.net.int.kdn.im/v1/models`.

**It does fetch the list at startup.** Verified three ways:

1. A direct `curl` to the plugin URL returned HTTP 200 in 0.030 s, with no API
   key.
2. `opencode models brys` lists **34** ids, including ids that are not in the
   static config (for example `granite-4.2-30b`, `qwen3.8-flash-next`). Only a
   successful fetch produces those ids.
3. The environment variable `KDN_LLM_API_KEY_brys` is set but **empty**. The
   endpoint does not require a key, so the fetch succeeds anyway.

The fetch is fast (0.030 s), so it adds almost nothing to the start time. The
repo runs are still slightly slower than the `/tmp` runs (cold 3.471 against
3.447, warm 4.011 against 3.469). That gap is consistent with loading the repo
config, the plugins, and the agent rules — not with the model-list fetch.

## Honest limits

- **A clean cold/warm split is not fully controllable.** opencode keeps other
  state warm (the session database, `auth.json`, the settings file) and this
  measurement does not clear it. So "cold" here means only "the models.dev
  catalog is absent". It is a weak cold start, not a first-ever start. Both the
  cold and the warm cells are therefore **approximate** in that sense.
- **The load was not idle-stable.** The median one-minute load was about 4.
  Three other opencode processes owned by the user were already running (one
  TUI, two `--auto` sessions), and this agent's own session added load. Every
  run records its load so a reader can see this. On a truly idle host the
  numbers would likely be lower and tighter.
- **The cold and warm medians are close** (3.447 and 3.469 for `/tmp`). The
  catalog cache is small next to the rest of the start cost, so the cold/warm
  difference is inside the noise of this load. The two are reported as measured;
  treat the difference as not significant on this pass.
- **The repo warm run is the slowest** (4.011 s). Its load was also the highest
  early in that batch. Do not read a strong meaning into the repo-against-`/tmp`
  difference from this pass alone.

## Raw output

- Per-run stdout: `/tmp/opencode/out.{1,2,3}` (overwritten by the last batch).
- Per-run stderr: `/tmp/opencode/err.{1,2,3}`.
- Harness: `/tmp/opencode/run.sh`.
- Brys model list (direct fetch): `/tmp/opencode/brys-models.json`.
