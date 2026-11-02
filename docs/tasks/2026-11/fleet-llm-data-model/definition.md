---
type: Task
description: Unify the LLM fleet data into one centrally-configured model that servers, clients and fleet members all read, replacing the split between data/llm.nix and hosts/brys/llm-routers.nix.
status: done
authored_by: agent
timestamp: 2026-11-02T13:33:00+01:00
---

# Central fleet LLM data model

> **Done.** Implemented in the same month. See [done.md](done.md) for the solution and the
> eval-diff that proves it, and [review.md](review.md) for the four review rounds and the
> implementation findings. `data/llm.nix` is now the single source; `llm-routers.nix` is gone.

## Context

The LLM fleet data is split across two files:

- `data/llm.nix` — the _declared_ single source of truth: per-model
  `aliases`, `contextSize`, `gpu`, `capabilities`, `pi`, `vision`, plus
  `endpoints` and `pi.defaults`.
- `hosts/brys/llm-routers.nix` — the _serving_ data, grouped into three router
  sets (`small`, `grunt`, `surveyed`): `hfRepo`, `hfFile`, `download`,
  `mainRouter`, `perf` (device, threads, nGpuLayers, contextSize, rope, kv),
  `mmproj`, `draft`.

Every consumer reads one file or the other, never both:

| Consumer                    | Reads                                   | Host role       |
| --------------------------- | --------------------------------------- | --------------- |
| `lib/llm.nix` (Pi client)   | `data/llm.nix` (aliases, ctx, pi, caps) | client          |
| `hosts/brys/llm.nix`        | `llm-routers.nix` sets + `data/llm.nix` | server          |
| `hosts/brys/llm-agents.nix` | `llm-routers.nix` sets (alias → model)  | server + member |
| `hosts/oams/devenv.nix`     | imports `brys/llm-agents.nix`           | member          |

`hosts/brys/llm-agents.nix` and `hosts/oams/devenv.nix` read the _router_ file
directly. So the alias set is declared in `data/llm.nix` but the model-to-alias
mapping that members use is re-derived from `llm-routers.nix`. Two files hold
overlapping truth: `contextSize` lives in both, aliases live in both.

The two brys boot profiles differ in exactly two places: DeepSeek's
`contextSize` (desktop 128K, appliance 320K) and the Qwen perf block. Both are
passed today as function flags into `hosts/brys/llm.nix`.

## Problem

1. Two files hold model truth; they can drift. Editing "a model" means editing
   `data/llm.nix` AND the right `llm-routers.nix` set.
2. A member host cannot answer "which models exist and how do I reach them?"
   from the data file alone; it must import a host-specific router file.
3. Per-host and per-profile variation (device pin, threads, context size) has
   no home in the data model. It lives in host code, or is passed as flags.

## Goal

One central data model in `data/llm.nix` that is the single place to configure
the whole fleet. A consumer selects **its host** and **its profile** and reads
the resolved view it needs:

- a **server** reads the serving data (how to load and route a model),
- a **client** reads the intent view (alias → model, context budget, vision),
- a **member** reads enough to address any served model without importing a
  host file.

The model must stay host-agnostic where it can, and carry per-host and
per-profile deltas where it must. See [design.md](design.md).

## Non-goals

- Adding new models or changing the served fleet. This is a data-shape change
  only; the rendered server configuration must be byte-identical for both brys
  profiles after migration.
- A remote store or a database. The model stays Nix, evaluated at build time.

## Acceptance

- The desktop profile renders `kdn.llm.local.models` **identical** to today. The
  appliance profile renders identical **except** DeepSeek's served context, which
  now really is 320K (the design fixed a dead override; see R14 in [review.md](review.md)).
- The Pi `models.json` (`lib/llm.nix`) and the orchestrator catalog render
  identical to today.
- `oams` still resolves every alias it uses today, now from `data/llm.nix`.
- `hosts/brys/llm-routers.nix` is deleted.
- The design is reviewed independently: at least two review rounds recorded in
  this directory.
