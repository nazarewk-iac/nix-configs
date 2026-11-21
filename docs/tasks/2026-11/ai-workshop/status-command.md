---
type: Reference
description: The `kdn-inference-helpers status` subcommand — the one screen that answers what the host can serve and what is serving now, its three views, the source of every fact, and what it prints when a source is missing.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T20:12:00+01:00
---

# The `status` subcommand

`kdn-inference-helpers status` answers one question in one screen: **what can this host serve, and
what is serving right now**. The configured half comes from the deployment file and the placement
policy. The live half comes from the manager, llama-swap, `/proc/meminfo`, the card's sysfs and the
engine's own log.

It is a view, not a control plane. It never switches, unloads or starts anything; `ctl` does that.
It is also the command an operator runs when the host is already broken, so a source that does not
answer is a line of output, never an error and never a non-zero exit.

## The table

One line per profile, in three groups:

| group       | what it is                                                                  | where the rows come from      |
| ----------- | --------------------------------------------------------------------------- | ----------------------------- |
| `frontier`  | the engine profiles; one of them holds the whole card at a time             | `textProfiles`                |
| `companion` | a model that sits beside a colo profile, owned by llama-swap                | the policy, `tier: companion` |
| `image`     | a diffusion server of the same manager; asking for it replaces the frontier | `commands`                    |

The columns are the profile, the pack, the window × the slot count, the names that reach it, and one
word for what it is for (`resting`, `long`, `swarm`, `multi`, `colo`, `companion`, `image`). The
resting profile is marked with `*`, and it is the row that carries `qfn`: `qfn` is profile-neutral,
so with nothing loaded it starts the resting profile and with something loaded it changes nothing.

`base × 1` means the profile keeps the base config's own window, which is what the two colo profiles
do. A `—` is a fact the deployment does not have, not a zero.

## The three views

The default is the table plus one trailing line. When something is loaded the live block follows
the table instead, because an idle host has nothing to add to it and a loaded one has a lot. `--long`
asks for the live block on an idle host too.

```
now  profile none · companions none · 31.8 GiB VRAM free, 98.5 GiB RAM free
```

```
now
  profile     max-multi · UD-IQ4_XS · 512k × 6 · 23.2 GiB weights + 7.6 GiB K/V
  rates       41.2 t/s (the engine's last completed request, just now)
  companions  none
  leases      0 in flight, draining no
  eviction    18d0985d-3953-4b63-9f10-5eb008206657
  switch      none → max-multi · 64 s (select) · 4 s ago
  llama-swap  qfn
  free        VRAM 1.0 GiB of 31.9 GiB (3%) · RAM 5.9 GiB of 125.7 GiB (4%)
```

A companion line carries its footprint and its measured decode rate. The rate is always labelled
with the profile it was measured beside, because a number measured next to another profile is still
useful but is not this profile's rate:

```
  companions  qwen3-omni 20.2 GiB, 6.1 t/s beside max
```

`--json` emits the same snapshot as one object (`host`, `now`, `profiles[]`, `manager`, `swap`,
`free`, `engineRateTps`, `engineRateAt`, `policy`), so a script reads what the screen shows.

## Where each fact comes from

| fact                               | source                                                                 |
| ---------------------------------- | ---------------------------------------------------------------------- |
| profiles, aliases, image commands  | `/etc/kdn-inference-helpers/config.json`                               |
| pack, window, slot count           | the engine adapter's profile table, with the config's overrides        |
| `vramMiB`, `kvReserveMiB`, seconds | the placement policy's `models` facts                                  |
| companions, their rates            | the policy's `tier: companion` entries                                 |
| current profile, leases, eviction  | the manager's `/status`                                                |
| entries that are up                | llama-swap's `/running`                                                |
| free VRAM                          | `/sys/class/drm/card*/device/mem_info_vram_{total,used}`, biggest card |
| free RAM                           | `/proc/meminfo`, `MemAvailable` not `MemFree`                          |
| the engine's own decode rate       | the tail of the engine log                                             |

The card is chosen by the most VRAM, so an integrated GPU on the same host is never reported as the
one that holds a model. `MemAvailable` is read because the page cache is what a model load is about
to need.

## When a source is missing

| missing                    | what happens                                                                                                                                                                 |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the manager                | the table still prints; the trailing line says it is unreachable, and `--long` names the URL and the reason                                                                  |
| the policy file            | a `policy …` line gives the path and the error; the table prints without facts, and the companion group is empty because the policy is the only place those models are named |
| llama-swap                 | `llama-swap unreachable at <url>` in the live block                                                                                                                          |
| the card or the engine log | the free line or the rate line is left out                                                                                                                                   |

A rate line above the newest `ready:` marker in the log is suppressed: the log is appended across
restarts, so that rate belongs to an engine that no longer exists.

## Acceptance

The package is `internal/status`; the command is `cmd/kdn-inference-helpers/status.go`.

- `internal/status` tests: the table from a fixture config and policy (marker, window, aliases,
  column alignment), the long view, a closed manager listener, the JSON shape, and the three live
  probes against a fake sysfs, a fake meminfo and a fake engine log.
- Live on `brys` 2026-11-21: `status`, `status --long`, `status --json`, with the manager stopped,
  and with `--policy` pointing at a missing file.
