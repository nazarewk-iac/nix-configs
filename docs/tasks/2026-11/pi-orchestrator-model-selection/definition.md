---
type: Task
description: Give the Pi orchestrator the knowledge and live signals to pick the best local model for each delegated task — capability, context, thinking levels, operation mode, what is loaded (switch cost), and brys' resource headroom — with the pieces proved separately.
status: open
authored_by: agent
timestamp: 2026-11-01T21:40:00+01:00
---

# The orchestrator picks the model, from live data

## The ask

The orchestrator currently hands a task to whatever model its agent file names. It must instead
choose the **best model for that specific work**, from all local models, knowing:

1. what each model **is good at** (purpose alias meaning, tool-calling, vision, long context),
2. its **served context** and **output cap**,
3. its supported **thinking levels**,
4. its **operation mode** — GPU-resident fast, or CPU-resident slow with a large context,
5. **what is loaded on brys right now**, because a switch costs a cold load, and
6. **brys' live headroom** (RAM, VRAM, load, swap), because a resident CPU model halves the
   frontier.

Research, with every endpoint verified by HTTP call: [research.md](research.md). It was reviewed
independently; the accepted findings and the one refuted claim are in [review.md](review.md).

## Constraints that shape the design

- **No per-model metrics exist.** `/metrics` is host-level; `/running` is model-level. Two sources,
  two questions.
- **A swap is expensive.** Frontier cold load ~90 s; a resident CPU model halves the frontier's
  throughput (measured in this repository).
- **The orchestrator has one tool** in engaged mode (`delegate`). Adding capability means adding a
  small number of **specific** tools, not unblocking `bash`.
- **Everything is a package.** No new files under `data/`; extensions live in
  `packages/pi-coding-agent-extensions/`.

## The design

### Part 1 — the programmatic gate (the only part that can prevent the incident)

A prompt rule cannot know that a sub-agent will later open a 468 KB file. So the gate lives in the
tool, not in prose:

- `delegate` gains an optional `inputBytes` argument. The extension reads the **target model's
  served context** from `/v1/models` (cached), and **rejects** the delegation when
  `inputBytes` exceeds a safe fraction of it, returning the aliases that would fit. A rejection is
  a structured result, not an exception, so the orchestrator can retry correctly.
- A `measure` action returns `{ bytes, lines }` for a path, so the orchestrator asks instead of
  guessing. This is the one call that turns "I hope it fits" into a fact.

Both live in the `pi-orchestrator` extension, because it already owns the `delegate` tool.

### Part 2 — a capability model with cost hints

Extend `data/llm.nix` per model with an optional `capabilities` sub-attribute; `lib/llm.nix` renders
it into a **model catalog** the orchestrator can read:

```nix
models."lfm2.5-24b-a2b" = {
  aliases = [ "chat-std-fast" "tools-std-fast" ];
  contextSize = 32768;
  gpu = false;
  capabilities = {
    # Only what the alias cannot already say. `tools-std-fast` already means "tools"; do not
    # repeat it as `strengths`. These are ESTIMATES from this repo's measurements, not promises.
    operation = "cpu";    # cpu | gpu — the operation mode
    loadSeconds = 15;     # expected cold-load time (frontier ~90 s, small GPU 1-3 s)
  };
};
```

The catalog reaches the **orchestrator itself**, through the `rules` channel `devenv.nix` already
wires into the Pi wrapper (a `pkgs.writeText` file appended to the system prompt). A file only a
sub-agent can read would not help the entity choosing the model — the review's first finding.

### Part 3 — a live fleet-state tool

A `fleet-status` extension tool that performs three HTTP GETs with a short timeout and returns one
compact JSON object:

```json
{ "loaded": ["qwen3.8-flash-next"],
  "resources": { "ram_used_gb": 29, "ram_total_gb": 125, "vram_used_gb": 6.8, "vram_total_gb": 8.0,
                 "load1": 5.7, "swap_used_gb": 13 },
  "models": [ { "alias": "chat-std-fast", "context": 32768, "loaded": false, "load_seconds_est": 15 } ] }
```

It must: use the CA cert and bearer key the client already has, cap total time (e.g. 3 s), and
**degrade to a cached/static answer** when brys is unreachable, never throw.

### Part 4 — the decision rule, in the orchestrator's prompt

Not a heuristic in code: a short, ordered policy the model applies with the two inputs above.

1. **Hard filter on context** — the input must fit the model's served context with room to answer.
   This is the rule that would have prevented the 468 KB mistake.
2. **Prefer a resident model** — no load cost. If none is suitable, prefer one whose load cost fits
   the task's expected duration.
3. **Respect headroom** — do not schedule a CPU model beside a resident frontier; that halves it.
4. **Match capability** — `tools-*` for tool calling, `vision-*` for images, `code-*` for edits.
5. **Escalate on evidence only** — two failures from a tier, then up one.

### Part 5 — proof, one file per function

Each piece gets its own proof file under this task, with the exact command and its real output:

| File | Proves |
|---|---|
| `proof-catalog.md` | the rendered catalog parses and carries capability + cost hints |
| `proof-fleet-status.md` | the tool returns live state; and degrades correctly when brys is unreachable |
| `proof-context-filter.md` | a delegation declaring a 468 KB input is **rejected by the extension**, showing the message and the aliases it suggests |

## Out of scope

- A second router. llama-swap already routes; this only informs a choice.
- Per-model metrics. They do not exist upstream; do not fake them.
- Anything under `data/` beyond the catalog data.

## Acceptance

- `data/llm.nix` carries `capabilities` for every model that has a purpose alias, and the rendered
  catalog is reproducible (`nix eval`).
- The `fleet-status` tool returns real values on this host and a static fallback when `brys` is
  down; both shown in `proof-fleet-status.md`.
- A `delegate` call that declares an oversized input is rejected **by code**, with the reason and
  the fitting aliases, shown in `proof-context-filter.md`. A prompt rule alone does not satisfy
  this acceptance.
- A new Pi session runs with the tooling and delegates with a stated model rationale.
- Every caveat found during the work is recorded in this task, not hidden.
