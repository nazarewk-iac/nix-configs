---
type: Task
description: Split the local LLM slot into two llama-server routers, so one frontier model stays hot while the small models swap freely behind one endpoint.
status: in-progress
authored_by: agent
timestamp: 2026-09-06T00:00:00+02:00
---

# Two-router LLM split

Design: [design.md](design.md).

## Goal

Keep one frontier model resident at all times, and let every smaller model swap freely in a
separate set. A single `llama-server` router with `--models-max 1` evicts the frontier weights
whenever a second model loads, so one router cannot meet both needs. The design puts a second
router beside the primary one, and routes each request on the `model` field of the JSON body.

## Current state

The design is written and part of it is in the tree:

- `modules/slots/llm/default.nix:114-135` filters the model preset per router, and `:362-383`
  declares `kdn.llm.local.routers` with the extra `llama-server` units.
- Each model selects its router through `models.<name>.mainRouter`.
- `packages/opencode-compat-proxy/patches/router.patch` adds the `UPSTREAMS`/`ROUTE` tables and
  the `SMALL_UPSTREAM_URL` shortcut to the compat-proxy.
- No host enables an extra router yet, so the split is unused in production.

## Exit test

- The host enables a second router, and both routers answer on their own ports.
- A request to the frontier model and a request to a small model both succeed through the one
  front-facing endpoint, with no manual port choice.
- The frontier weights stay hot: a small-model swap causes no re-read of the frontier model from
  disk, measured before and after the swap.
- `/v1/models` lists the models of both routers.

## Out of scope

Model selection and per-model tuning. The design covers thread and CPU pinning; treat any further
performance work as a separate task.
